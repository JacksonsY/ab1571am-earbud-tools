// Brief, silent output to the already-selected headset; no default-device or system-volume changes.
import AVFoundation
import Foundation
setbuf(stdout, nil)
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
buffer.frameLength = 48000
for channel in 0..<2 {
    buffer.floatChannelData![channel].initialize(repeating: 0, count: 48000)
}
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: format)
engine.mainMixerNode.outputVolume = 0
do {
    try engine.start()
    player.scheduleBuffer(buffer, at: nil, options: .loops)
    player.play()
    print("SILENT_AUDIO_ACTIVE")
    RunLoop.current.run(until: Date().addingTimeInterval(45))
    player.stop()
    engine.stop()
    print("SILENT_AUDIO_STOPPED")
} catch {
    fputs("Audio link activation failed: \(error)\n", stderr)
    exit(1)
}
