// Usage: swift tools/inspect-earbud.swift "DEVICE_NAME_OR_LOCAL_UUID" --ble-info
// Read: --read-nvkey KEY, --peer-read-nvkey KEY, --flash-map, --read-flash START SIZE
// Explicit configuration change: --set-nvkey KEY EXPECTED NEW or --peer-set-nvkey KEY EXPECTED NEW.
// Writes are limited to FB00/FB03/FC04 and guarded DeviceInfo cache synchronization on one exact firmware.
// The OS may show a local alias; this API uses the earbud's original name.
// Default: SDP discovery. --race-info: only RACE SDK/build metadata queries.
import Foundation
import IOBluetooth
import CoreBluetooth
setbuf(stdout, nil)
umask(0o077) // Runtime backups and their directory are private to the current user.

func normalized(_ name: String) -> String {
    name.lowercased()
        .replacingOccurrences(of: "‘", with: "'")
        .replacingOccurrences(of: "’", with: "'")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func request(_ command: UInt16, payload: [UInt8] = []) -> [UInt8] {
    let length = payload.count + 2
    precondition(length <= 4096)
    return [0x05, 0x5A, UInt8(length & 255), UInt8(length >> 8), UInt8(command & 255), UInt8(command >> 8)] + payload
}

func addressBytes(_ address: UInt32) -> [UInt8] {
    (0..<4).map { UInt8((address >> ($0 * 8)) & 255) }
}

func number(_ value: String) -> UInt32? {
    value.lowercased().hasPrefix("0x") ? UInt32(value.dropFirst(2), radix: 16) : UInt32(value)
}

func validFlashRange(_ start: UInt32, _ size: UInt32) -> Bool {
    // This device's observed partition map spans 0x08000000..<0x08800000.
    start >= 0x08000000 && size > 0 && start % 256 == 0 && size % 256 == 0 &&
        UInt64(start) + UInt64(size) <= 0x08800000
}

func flashPage(_ frame: [UInt8], expectedAddress: UInt32, size: Int = 256) -> [UInt8]? {
    guard frame.count == size + 14, isReply(frame, to: 0x0403), frame[6] == 0,
          frame[7] == 0, Array(frame[10..<14]) == addressBytes(expectedAddress) else { return nil }
    return Array(frame.dropFirst(14))
}

func nvkeyValue(_ frame: [UInt8]) -> [UInt8]? {
    guard frame.count >= 8, isReply(frame, to: 0x0A00) else { return nil }
    let length = Int(frame[6]) | (Int(frame[7]) << 8)
    guard length <= 1000, frame.count == length + 8 else { return nil }
    return Array(frame.dropFirst(8))
}

func unwrapPeer(_ frame: [UInt8], destination: [UInt8]) -> [UInt8]? {
    guard frame.count >= 14, frame[1] == 0x5D, isReply(frame, to: 0x0D01),
          Array(frame[6..<8]) == destination else { return nil }
    let inner = Array(frame.dropFirst(8))
    guard inner[0] == 5, inner[1] == 0x5B,
          (Int(inner[2]) | Int(inner[3]) << 8) + 4 == inner.count else { return nil }
    return inner
}

func isReply(_ frame: [UInt8], to command: UInt16) -> Bool {
    frame.count >= 6 && [0x5B, 0x5D].contains(frame[1]) &&
        frame[4] == UInt8(command & 255) && frame[5] == UInt8(command >> 8)
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

func textFields(_ frame: [UInt8]) -> [String] {
    frame.dropFirst(7).split(separator: 0).compactMap { bytes in
        guard bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}

struct RaceFrames {
    var pending: [UInt8] = []
    mutating func consume(_ bytes: [UInt8]) -> [[UInt8]] {
        pending += bytes
        var result: [[UInt8]] = []
        while pending.count >= 6 {
            guard pending[0] == 0x05 else { pending.removeFirst(); continue }
            let length = Int(pending[2]) | (Int(pending[3]) << 8)
            guard (2...8192).contains(length) else { pending.removeFirst(); continue }
            guard pending.count >= length + 4 else { break }
            result.append(Array(pending.prefix(length + 4)))
            pending.removeFirst(length + 4)
        }
        return result
    }
}

final class RaceReader: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var parser = RaceFrames()
    var frames: [[UInt8]] = []
    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard length > 0, length <= 8192, let pointer = pointer else { return }
        frames += parser.consume(Array(UnsafeRawBufferPointer(start: pointer, count: length)))
        if frames.count > 64 { frames.removeFirst(frames.count - 64) }
    }
}

final class BLEProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let target: String
    let readInfo: Bool
    let readFlashMap: Bool
    let flashStart: UInt32
    let flashLength: Int
    let flashPageSize: Int
    let nvkeyID: UInt16?
    let expectedValue: UInt8?
    let writeValue: UInt8?
    let relayToPeer: Bool
    let checkInfoCache: Bool
    let syncInfoCache: Bool
    let checkRole: Bool
    var inspectedRAMAddress: UInt32 { checkRole ? 0x1423485C : (checkInfoCache ? 0x1423B29C : 0x142082F0) }
    var persistentInfoFlag: UInt8?
    var originalInfoWord: [UInt8]?
    var desiredInfoWord: [UInt8]?
    var relayDestination: [UInt8]?
    var infoOffset: Int { relayToPeer ? 1 : 0 }
    let serviceID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    let txID = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")
    let rxID = CBUUID(string: "43484152-2DAB-3141-6972-6F6861424C45")
    let commands: [(UInt16, String)]
    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var tx: CBCharacteristic?
    var done = false
    var failed = false
    var index = 0
    var parser = RaceFrames()
    var queryDeadline: Date?
    var flashBytes: [UInt8] = []
    init(target: String, readInfo: Bool, readFlashMap: Bool = false, flashStart: UInt32 = 0, flashLength: Int = 4096, flashPageSize: Int = 256, nvkeyID: UInt16? = nil, expectedValue: UInt8? = nil, writeValue: UInt8? = nil, discoverDestinations: Bool = false, relayToPeer: Bool = false, checkMenuCache: Bool = false, checkInfoCache: Bool = false, syncInfoCache: Bool = false, checkRole: Bool = false) {
        self.target = target
        self.readInfo = readInfo
        self.readFlashMap = readFlashMap
        self.flashStart = flashStart
        self.flashLength = flashLength
        self.flashPageSize = flashPageSize
        self.nvkeyID = nvkeyID
        self.expectedValue = expectedValue
        self.writeValue = writeValue
        self.relayToPeer = relayToPeer
        self.checkInfoCache = checkInfoCache
        self.syncInfoCache = syncInfoCache
        self.checkRole = checkRole
        self.commands = (relayToPeer ? [(0x0D00, "Relay destinations")] : []) +
            [(0x0301, "SDK information"), (0x1E08, "Build version")] +
            (readFlashMap ? Array(repeating: (0x0403, "Flash page"), count: flashLength / flashPageSize) : []) +
            (nvkeyID == nil ? [] : [(0x0A00, "NVKEY value")]) +
            (writeValue == nil ? [] : [(0x0A01, "NVKEY write"), (0x0A00, "NVKEY readback")]) +
            (discoverDestinations ? [(0x0D00, "Relay destinations")] : []) +
            ((checkMenuCache || checkInfoCache || checkRole) && !syncInfoCache ? [(0x1680, "Runtime state")] : []) +
            (syncInfoCache ? [(0x1680, "Cache preflight"), (0x1680, "Cache stability check"), (0x1681, "Cache flag update"), (0x1680, "Cache readback")] : [])
        super.init()
    }
    func fail(_ message: String) { print(message); failed = true; done = true }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting { fail("Bluetooth state: \(central.state.rawValue)") }
            return
        }
        let matches = central.retrieveConnectedPeripherals(withServices: [serviceID])
            .filter { normalized($0.name ?? "") == target || normalized($0.identifier.uuidString) == target }
        print("Matching connected RACE peripherals: \(matches.count)")
        guard matches.count == 1 else { fail("Connect the named earbud in Bluetooth settings first."); return }
        peripheral = matches[0]
        peripheral?.delegate = self
        central.connect(matches[0])
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BLE connected to: \(peripheral.name ?? target)")
        peripheral.discoverServices([serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail("BLE connection failed: \(String(describing: error))")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if !done { fail("BLE disconnected before completing the query: \(String(describing: error))") }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            fail("Service discovery failed: \(String(describing: error))"); return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { fail("Characteristic discovery failed: \(error!)"); return }
        let characteristics = service.characteristics ?? []
        for c in characteristics { print("Characteristic: \(c.uuid) properties=\(c.properties.rawValue)") }
        guard readInfo else { done = true; return }
        tx = characteristics.first { $0.uuid == txID && $0.properties.contains(.write) }
        guard tx != nil, let rx = characteristics.first(where: { $0.uuid == rxID && $0.properties.contains(.notify) }) else {
            fail("Expected RACE write/notify characteristics unavailable."); return
        }
        peripheral.setNotifyValue(true, for: rx)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == rxID else { return }
        guard error == nil, characteristic.isNotifying else { fail("RACE notification subscription failed."); return }
        nextQuery()
    }
    func nextQuery() {
        guard !done else { return }
        guard index < commands.count else {
            if readFlashMap {
                let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("work")
                let destination = directory.appendingPathComponent("flash-\(String(format: "%08x", flashStart))-\(UUID().uuidString).bin")
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try Data(flashBytes).write(to: destination, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                    print("Read-only flash backup saved (\(flashBytes.count) bytes): \(destination.path)")
                } catch { fail("Could not save flash map: \(error)"); return }
            }
            done = true
            return
        }
        guard let tx = tx, let peripheral = peripheral else { fail("RACE transport unavailable."); return }
        queryDeadline = Date().addingTimeInterval(5)
        // Upstream RACE_STORAGE_PAGE_READ: storage 0, one 256-byte page, LE offset.
        // No erase/program commands exist here.
        var payload: [UInt8] = []
        if commands[index].0 == 0x0403 {
            payload = [0, UInt8(flashPageSize / 256)] + addressBytes(flashStart + UInt32((index - 2) * flashPageSize))
        } else if commands[index].0 == 0x0A00, let key = nvkeyID {
            // UT SDK: key ID LE, maximum response data length 1000 LE.
            payload = [UInt8(key & 255), UInt8(key >> 8), 0xE8, 0x03]
        } else if commands[index].0 == 0x0A01, let key = nvkeyID, let value = writeValue {
            payload = [UInt8(key & 255), UInt8(key >> 8), value]
        } else if commands[index].0 == 0x1680 {
            // Exact analyzed-firmware FC04 cache location; read four bytes, report only the first.
            payload = [0, 0] + addressBytes(inspectedRAMAddress)
        } else if commands[index].0 == 0x1681 {
            guard syncInfoCache, let word = desiredInfoWord, word.count == 4, index == 5 + infoOffset else {
                fail("No validated cache update prepared; no RAM write sent."); return
            }
            payload = [0, 0] + addressBytes(0x1423B29C) + word
        }
        var packet = request(commands[index].0, payload: payload)
        if relayToPeer && index > 0 {
            guard let destination = relayDestination else { fail("No discovered AWS peer; no relayed command sent."); return }
            packet = request(0x0D01, payload: destination + packet)
        }
        peripheral.writeValue(Data(packet), for: tx, type: .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { fail("Metadata query failed: \(error)") }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !done, characteristic.uuid == rxID else { return }
        guard error == nil, let data = characteristic.value else { fail("RACE receive failed."); return }
        for rawFrame in parser.consume(Array(data)) {
            var frame = rawFrame
            if relayToPeer && index > 0 {
                guard let destination = relayDestination, let inner = unwrapPeer(rawFrame, destination: destination) else { continue }
                frame = inner
            }
            guard index < commands.count, isReply(frame, to: commands[index].0) else { continue }
            if relayToPeer && index == 0 {
                let destinations = Array(frame.dropFirst(6))
                guard destinations.count % 2 == 0 else { fail("Malformed relay destination list."); return }
                let peers = stride(from: 0, to: destinations.count, by: 2).filter { destinations[$0] == 5 }
                guard peers.count == 1 else { fail("Expected one discovered AWS peer; no fallback destination used."); return }
                relayDestination = Array(destinations[peers[0]..<peers[0] + 2])
                print("Using discovered AWS peer: \(hex(relayDestination!))")
            } else if commands[index].0 == 0x0403 {
                guard let page = flashPage(frame, expectedAddress: flashStart + UInt32((index - 2) * flashPageSize), size: flashPageSize) else {
                    fail("Flash read rejected or invalid; no further pages requested. Reply prefix: \(hex(Array(frame.prefix(14))))")
                    return
                }
                flashBytes += page
                if flashBytes.count % 65536 == 0 { print("Backed up \(flashBytes.count)/\(flashLength) bytes") }
            } else if commands[index].0 == 0x0A00 {
                guard let value = nvkeyValue(frame), let key = nvkeyID else {
                    fail("NVKEY read response does not match the documented layout: \(hex(Array(frame.prefix(14))))")
                    return
                }
                print("NVKEY \(String(format: "%04x", key)), \(value.count) bytes: \(hex(value))")
                if syncInfoCache {
                    guard key == 0xFB00, value.count == 1, [0, 1].contains(value[0]) else {
                        fail("Unexpected persistent DeviceInfo flag; no RAM update sent."); return
                    }
                    persistentInfoFlag = value[0]
                }
                if let desired = writeValue {
                    if index == 2 + infoOffset {
                        if value == [desired] { print("Already at the requested value; no write sent."); done = true; return }
                        guard let expected = expectedValue, value == [expected] else {
                            fail("Original value differs from the reviewed change. No write sent."); return
                        }
                        let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("work")
                        let path = directory.appendingPathComponent("nvkey-change-\(String(format: "%04x", key))-\(UUID().uuidString).json")
                        let record: [String: Any] = ["device": target, "peripheral": peripheral.identifier.uuidString,
                            "target": relayToPeer ? "aws_peer" : "connected_earbud",
                            "key": String(format: "%04x", key), "before": hex(value), "requested": hex([desired]),
                            "captured_at": ISO8601DateFormatter().string(from: Date()),
                            "firmware_profile": "ab157x_evk / IoT_SDK_for_BT_Audio_V3.10.0.c43sp_YFY_1 / 2026/09/14 15:40:24 GMT +08:00"]
                        do {
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
                            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                            print("Original value saved: \(path.path)")
                        } catch { fail("Could not preserve original value: \(error)"); return }
                    } else if index == 4 + infoOffset {
                        guard value == [desired] else { fail("Write readback does not match requested value."); return }
                        print("Persistent value readback verified; runtime cache and phone UI still require verification.")
                    }
                }
            } else if commands[index].0 == 0x1680 {
                guard frame.count == 17, frame[6] == 0, Array(frame[9..<13]) == addressBytes(inspectedRAMAddress) else {
                    fail("Runtime cache read did not match the documented response layout."); return
                }
                if checkRole {
                    print("AWS role byte: \(hex([frame[15]]))")
                } else if checkInfoCache {
                    print("DeviceInfo loaded flag: \(hex([frame[13]])); FB00 runtime flag: \(hex([frame[14]]))")
                    if syncInfoCache {
                        let word = Array(frame[13..<17])
                        guard word[0] == 1, let desiredFlag = persistentInfoFlag else {
                            fail("Metadata is not fully loaded; no cache update allowed."); return
                        }
                        if index == 3 + infoOffset {
                            if word[1] == desiredFlag { print("Runtime DeviceInfo flag already matches persistent config; no RAM write sent."); done = true; return }
                            guard [0, 1].contains(word[1]) else { fail("Unexpected runtime flag; no RAM update sent."); return }
                            originalInfoWord = word
                        } else if index == 4 + infoOffset {
                            guard word == originalInfoWord else { fail("Cache changed during preflight; no RAM update sent."); return }
                            var updated = word
                            updated[1] = desiredFlag
                            let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("work")
                            let path = directory.appendingPathComponent("info-cache-change-\(UUID().uuidString).json")
                            let record: [String: Any] = ["target": relayToPeer ? "aws_peer" : "connected_earbud", "peripheral": peripheral.identifier.uuidString,
                                "word_address": "0x1423B29C", "flag_address": "0x1423B29D", "before_flag": hex([word[1]]), "requested_flag": hex([desiredFlag]),
                                "other_bytes": "preserved in memory; not logged", "captured_at": ISO8601DateFormatter().string(from: Date())]
                            do {
                                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                                try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
                                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                                print("Cache flag change record saved: \(path.path)")
                            } catch { fail("Could not record cache change: \(error)"); return }
                            desiredInfoWord = updated
                        } else if index == 6 + infoOffset {
                            guard word == desiredInfoWord else { fail("Cache readback differs from prepared word; inspect before further operations."); return }
                            print("Runtime DeviceInfo flag synchronized; the other three bytes are unchanged.")
                        }
                    }
                } else {
                    print("FC04 runtime cache byte: \(hex([frame[13]]))")
                }
            } else if commands[index].0 == 0x1681 {
                guard syncInfoCache, frame[1] == 0x5B, frame.count == 7, frame[6] == 0 else {
                    fail("Runtime cache update was not acknowledged."); return
                }
                print("Cache update acknowledged; verifying the complete aligned word privately.")
            } else if commands[index].0 == 0x0A01 {
                guard frame[1] == 0x5B, frame.count >= 7, frame[6] == 0 else {
                    fail("NVKEY write rejected or unrecognized: \(hex(frame))"); return
                }
                print("NVKEY write acknowledged with status 0; checking readback.")
            } else {
                if writeValue != nil || commands.contains(where: { $0.0 == 0x1680 }) {
                    let fields = textFields(frame)
                    let sdk = "IoT_SDK_for_BT_Audio_V3.10.0.c43sp_YFY_1"
                    if (index == infoOffset && fields != [sdk]) ||
                        (index == 1 + infoOffset && fields != ["ab157x_evk", sdk, "2026/09/14 15:40:24 GMT +08:00"]) {
                        fail("Firmware profile differs from the analyzed image. No configuration writes sent."); return
                    }
                }
                print("\(commands[index].1) raw reply: \(hex(frame))")
                print("  Payload text: \(textFields(frame).joined(separator: " | "))")
            }
            index += 1
            nextQuery()
        }
    }
}

if CommandLine.arguments.count == 1 || CommandLine.arguments == [CommandLine.arguments[0], "--help"] {
    print("""
    Earbud interoperability research tool (macOS)
    Usage: inspect-earbud DEVICE_NAME_OR_LOCAL_UUID MODE [ARGS]

    Offline: --help | --self-test (no Bluetooth connection)
    Read:    --ble-info | --ble | --race-info | --check-identity
             --read-nvkey KEY | --peer-read-nvkey KEY | --relay-destinations
             --check-info-cache | --peer-check-info-cache | --check-menu-cache
             --check-role | --peer-check-role
             --flash-map | --read-flash START SIZE [PAGE_SIZE]
    Write:   --set-nvkey KEY EXPECTED NEW | --peer-set-nvkey KEY EXPECTED NEW
             --sync-info-cache | --peer-sync-info-cache

    Only reviewed FB00/FB03 (00/01), FC04 (01/7A), and one firmware's
    DeviceInfo cache update are implemented. This is not a general firmware flasher.
    Write/cache operations check SDK, platform and build time, not a full MCU hash.
    Connect your authorized device in macOS first. Both earbuds must be reachable
    for peer operations. Local logs and work/ backups can contain private identifiers.
    Read docs/TOOLS.md and docs/PUBLICATION_AND_LEGAL.md before hardware operations.
    """)
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--self-test" {
    assert(normalized("Example‘s Earbuds 3") == normalized("Example's Earbuds 3"))
    assert(normalized("Example’s Earbuds 2") != normalized("Example's Earbuds 3"))
    assert(request(0x0301) == [5, 0x5a, 2, 0, 1, 3])
    let frame: [UInt8] = [5, 0x5b, 3, 0, 1, 3, 0]
    var parser = RaceFrames()
    assert(parser.consume([0xff, 5, 0x5b, 3]).isEmpty)
    assert(parser.consume(Array(frame.dropFirst(3)) + frame) == [frame, frame])
    assert(isReply(frame, to: 0x0301) && !isReply(request(0x0301), to: 0x0301))
    assert(!isReply(frame, to: 0x1E08))
    assert(textFields([5, 0x5b, 7, 0, 1, 3, 4, 65, 66, 67, 0]) == ["ABC"])
    assert(request(0x0403, payload: [0, 1] + addressBytes(256)) == [5, 0x5a, 8, 0, 3, 4, 0, 1, 0, 1, 0, 0])
    var pageReply = request(0x0403, payload: [0, 0, 0, 0] + addressBytes(256) + Array(repeating: 0xaa, count: 256))
    pageReply[1] = 0x5b
    assert(flashPage(pageReply, expectedAddress: 256)?.count == 256)
    assert(flashPage(pageReply, expectedAddress: 0) == nil)
    pageReply[6] = 1
    assert(flashPage(pageReply, expectedAddress: 256) == nil)
    var largePage = request(0x0403, payload: [0, 0, 0, 0] + addressBytes(256) + Array(repeating: 0xbb, count: 512))
    largePage[1] = 0x5b
    assert(flashPage(largePage, expectedAddress: 256, size: 512)?.count == 512)
    assert(flashPage(largePage, expectedAddress: 256) == nil)
    assert(number("0x087f0000") == 0x087f0000 && number("oops") == nil)
    assert(validFlashRange(0x087f0000, 0x10000))
    assert(!validFlashRange(0x087f0000, 0x10100) && !validFlashRange(0x08000001, 256))
    let nvReply: [UInt8] = [5, 0x5b, 6, 0, 0, 10, 2, 0, 0xab, 0xcd]
    assert(nvkeyValue(nvReply) == [0xab, 0xcd])
    assert(nvkeyValue(Array(nvReply.dropLast())) == nil)
    assert(request(0x0A01, payload: [0x03, 0xFB, 0]) == [5, 0x5A, 5, 0, 1, 10, 3, 0xFB, 0])
    var relayed = request(0x0D01, payload: [5, 6] + nvReply)
    relayed[1] = 0x5D
    assert(unwrapPeer(relayed, destination: [5, 6]) == nvReply)
    assert(unwrapPeer(relayed, destination: [5, 7]) == nil)
    relayed[1] = 0x5B
    assert(unwrapPeer(relayed, destination: [5, 6]) == nil)
    let testWord: [UInt8] = [1, 0, 0xA5, 0x5A]
    var updatedWord = testWord
    updatedWord[1] = 1
    assert(zip(testWord, updatedWord).enumerated().filter { $0.element.0 != $0.element.1 }.map { $0.offset } == [1])
    assert(request(0x1681, payload: [0, 0] + addressBytes(0x1423B29C) + updatedWord) == [5, 0x5A, 12, 0, 0x81, 0x16, 0, 0, 0x9C, 0xB2, 0x23, 0x14, 1, 1, 0xA5, 0x5A])
    print("Self-test passed; no Bluetooth connection attempted.")
    exit(0)
}
guard [2, 3, 4, 5, 6].contains(CommandLine.arguments.count),
      !normalized(CommandLine.arguments[1]).isEmpty,
      CommandLine.arguments.count == 2 ||
        (CommandLine.arguments.count == 3 && ["--race-info", "--ble", "--ble-info", "--flash-map", "--relay-destinations", "--check-identity", "--check-menu-cache", "--check-info-cache", "--peer-check-info-cache", "--sync-info-cache", "--peer-sync-info-cache", "--check-role", "--peer-check-role"].contains(CommandLine.arguments[2])) ||
        (CommandLine.arguments.count == 4 && ["--read-nvkey", "--peer-read-nvkey"].contains(CommandLine.arguments[2])) ||
        (CommandLine.arguments.count == 6 && ["--set-nvkey", "--peer-set-nvkey"].contains(CommandLine.arguments[2])) ||
        ([5, 6].contains(CommandLine.arguments.count) && CommandLine.arguments[2] == "--read-flash") else {
    fputs("Use --ble-info, --read-nvkey KEY, --peer-read-nvkey KEY, --set-nvkey KEY EXPECTED NEW, --peer-set-nvkey KEY EXPECTED NEW, --flash-map, --read-flash START SIZE, or --self-test.\n", stderr)
    exit(2)
}
let name = normalized(CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
if mode.hasPrefix("--ble") || ["--flash-map", "--read-flash", "--read-nvkey", "--set-nvkey", "--peer-read-nvkey", "--peer-set-nvkey", "--relay-destinations", "--check-menu-cache", "--check-info-cache", "--peer-check-info-cache", "--sync-info-cache", "--peer-sync-info-cache", "--check-role", "--peer-check-role"].contains(mode) {
    let flashMap = ["--flash-map", "--read-flash"].contains(mode)
    var start: UInt32 = 0
    var length = 4096
    var pageSize = 256
    var nvkeyID: UInt16?
    var expectedValue: UInt8?
    var writeValue: UInt8?
    if mode.contains("sync-info-cache") { nvkeyID = 0xFB00 }
    if ["--read-nvkey", "--set-nvkey", "--peer-read-nvkey", "--peer-set-nvkey"].contains(mode) {
        guard let key = number(CommandLine.arguments[3]), key <= 0xffff else {
            fputs("NVKEY must be a 16-bit ID, such as 0x1002.\n", stderr)
            exit(2)
        }
        nvkeyID = UInt16(key)
        if ["--set-nvkey", "--peer-set-nvkey"].contains(mode) {
            guard let before = number(CommandLine.arguments[4]), let after = number(CommandLine.arguments[5]),
                  ([0xFB00, 0xFB03].contains(key) && [0, 1].contains(before) && [0, 1].contains(after)) ||
                  (key == 0xFC04 && [1, 0x7A].contains(before) && [1, 0x7A].contains(after)) else {
                fputs("Only reviewed FB00/FB03 00/01 or FC04 01/7A changes are supported.\n", stderr)
                exit(2)
            }
            expectedValue = UInt8(before)
            writeValue = UInt8(after)
        }
    }
    if mode == "--read-flash" {
        guard let address = number(CommandLine.arguments[3]), let size = number(CommandLine.arguments[4]), validFlashRange(address, size) else {
            fputs("Range must be page aligned and lie within this device's observed 8 MiB flash map.\n", stderr)
            exit(2)
        }
        start = address
        length = Int(size)
        if CommandLine.arguments.count == 6 {
            guard let page = number(CommandLine.arguments[5]), [256, 512, 1024, 2048, 4096].contains(Int(page)), length % Int(page) == 0 else {
                fputs("PAGE_SIZE must be 256, 512, 1024, 2048, or 4096 and divide SIZE.\n", stderr)
                exit(2)
            }
            pageSize = Int(page)
        }
    }
    let probe = BLEProbe(target: name, readInfo: mode == "--ble-info" || flashMap || nvkeyID != nil || ["--relay-destinations", "--check-menu-cache", "--check-info-cache", "--peer-check-info-cache", "--check-role", "--peer-check-role"].contains(mode), readFlashMap: flashMap, flashStart: start, flashLength: length, flashPageSize: pageSize, nvkeyID: nvkeyID, expectedValue: expectedValue, writeValue: writeValue, discoverDestinations: mode == "--relay-destinations", relayToPeer: mode.hasPrefix("--peer-"), checkMenuCache: mode == "--check-menu-cache", checkInfoCache: mode.contains("info-cache"), syncInfoCache: mode.contains("sync-info-cache"), checkRole: mode.contains("check-role"))
    probe.central = CBCentralManager(delegate: probe, queue: nil)
    let deadline = Date().addingTimeInterval(flashMap ? min(900, max(20, Double(length / 256) + 10)) : 20)
    while !probe.done && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        if let queryDeadline = probe.queryDeadline, !probe.done && Date() > queryDeadline {
            probe.fail("Metadata query timed out without a matching RACE response.")
        }
    }
    if let peripheral = probe.peripheral { probe.central.cancelPeripheralConnection(peripheral) }
    if !probe.done { probe.fail("BLE discovery timed out.") }
    exit(probe.failed ? 1 : 0)
}
let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
    .filter { normalized($0.name ?? "") == name }
guard devices.count == 1, let device = devices.first else {
    print("Found \(devices.count) paired devices matching this name. No query sent.")
    exit(2)
}
guard device.isConnected() else {
    print("The selected earbud is paired but disconnected. Connect it in Bluetooth settings first.")
    exit(2)
}

final class SDPQuery: NSObject {
    var result: IOReturn?
    @objc(sdpQueryComplete:status:)
    func complete(_ device: IOBluetoothDevice, status: IOReturn) { result = status }
}
let query = SDPQuery()
let started = device.performSDPQuery(query)
guard started == kIOReturnSuccess else {
    print("Service query could not start: \(started)")
    exit(1)
}
let deadline = Date().addingTimeInterval(15)
while query.result == nil && Date() < deadline {
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}
guard let status = query.result, status == kIOReturnSuccess else {
    print("Service query failed or timed out: \(String(describing: query.result))")
    exit(1)
}
let records = device.services as? [IOBluetoothSDPServiceRecord] ?? []
print("Device: \(device.name ?? "") | SDP records: \(records.count)")
var pnpIdentities: [(vendor: Int, product: Int, source: Int)] = []
for record in records {
    var channel: BluetoothRFCOMMChannelID = 0
    let hasChannel = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess
    let classes = record.getAttributeDataElement(0x0001)
    print("Service: \(record.getServiceName() ?? "(unnamed)")")
    print("  UUIDs: \(String(describing: classes))")
    if hasChannel { print("  RFCOMM channel: \(channel)") }
    if String(describing: classes).contains("00 00 12 00") {
        for (attribute, label): (UInt16, String) in [(0x0200, "PnP specification"), (0x0201, "PnP vendor"), (0x0202, "PnP product"), (0x0203, "PnP version"), (0x0205, "PnP vendor source")] {
            print("  \(label): \(String(describing: record.getAttributeDataElement(attribute)))")
        }
        if let vendor = record.getAttributeDataElement(0x0201)?.getNumberValue()?.intValue,
           let product = record.getAttributeDataElement(0x0202)?.getNumberValue()?.intValue,
           let source = record.getAttributeDataElement(0x0205)?.getNumberValue()?.intValue {
            pnpIdentities.append((vendor, product, source))
        }
    }
}

if mode == "--check-identity" {
    guard pnpIdentities.count == 1 else {
        print("FAIL: expected one complete PnP identity record, found \(pnpIdentities.count).")
        exit(1)
    }
    let identity = pnpIdentities[0]
    print(String(format: "Fresh PnP identity: vendor=%04X product=%04X source=%d", identity.vendor, identity.product, identity.source))
    guard identity.vendor == 0x004C && identity.product == 0x2027 && identity.source == 1 else {
        print("FAIL: runtime identity is not the Pro 3 identity compiled into this firmware.")
        exit(1)
    }
    print("PASS: fresh remote PnP identity matches the compiled AirPods Pro 3 profile; iPhone artwork still needs visual verification.")
    exit(0)
}

if mode == "--race-info" {
    let appRecords = records.filter { $0.getServiceName() == "Airoha_APP" }
    var channelID: BluetoothRFCOMMChannelID = 0
    guard appRecords.count == 1,
          appRecords[0].getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
        print("No unique advertised Airoha_APP RFCOMM endpoint. No vendor query sent.")
        exit(2)
    }
    let reader = RaceReader()
    var channel: IOBluetoothRFCOMMChannel?
    let result = device.openRFCOMMChannelSync(&channel, withChannelID: channelID, delegate: reader)
    guard result == kIOReturnSuccess, let channel = channel else {
        print("Airoha_APP connection failed: \(result)")
        exit(1)
    }
    defer { _ = channel.close() }
    for (command, label): (UInt16, String) in [(0x0301, "SDK information"), (0x1E08, "Build version")] {
        reader.frames.removeAll()
        var bytes = request(command)
        let sent = bytes.withUnsafeMutableBytes { channel.writeSync($0.baseAddress!, length: UInt16($0.count)) }
        guard sent == kIOReturnSuccess else { print("Query send failed: \(sent)"); exit(1) }
        let deadline = Date().addingTimeInterval(5)
        while !reader.frames.contains(where: { isReply($0, to: command) }) && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        let replies = reader.frames.filter { isReply($0, to: command) }
        print("\(label): \(replies.isEmpty ? "no matching reply within 5 seconds" : replies.map(hex).joined(separator: " | "))")
    }
}
