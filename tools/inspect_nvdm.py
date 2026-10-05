"""Inspect a local NVDM backup; values stay private unless one key is selected.

Layout/checksum reference: dangkhoalk95/demoMT middleware/MTK/nvdm_core.
This parses the observed version-1, 4096-byte block layout, not every NVDM variant.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

HEADER = struct.Struct("<BBHHBBHBBII")


def checksum(*parts):
    low = sum(sum(part[::2]) for part in parts) & 255
    high = sum(sum(part[1::2]) for part in parts) & 255
    return low | (high << 8)


def parse(data):
    if not data or len(data) % 4096:
        raise ValueError("Backup must contain complete 4096-byte blocks")
    records = []
    for base in range(0, len(data), 4096):
        if data[base:base + 4] != b"NVDM" or data[base + 10] != 1:
            raise ValueError(f"Unrecognized block at {base:#x}")
        if data[base + 8] != 0xE0:
            continue
        offset = base + 12
        while offset + HEADER.size <= base + 4096 and data[offset] in (0xF8, 0xFC, 0xFE):
            status, block, _, position, group_len, name_len, value_len, _, kind, sequence, _ = HEADER.unpack_from(data, offset)
            start = offset + HEADER.size
            value_start = start + group_len + name_len
            end = value_start + value_len
            if block != base // 4096 or position != offset - base - 12 or end + 2 > base + 4096:
                raise ValueError(f"Invalid record bounds at {offset:#x}")
            if not (1 <= group_len <= 64 and 1 <= name_len <= 64):
                raise ValueError(f"Invalid name lengths at {offset:#x}")
            group = data[start:start + group_len]
            name = data[start + group_len:value_start]
            if not group.endswith(b"\0") or not name.endswith(b"\0"):
                raise ValueError(f"Unterminated name at {offset:#x}")
            value = data[value_start:end]
            actual = checksum(data[offset + 1:start], group + name, value)
            expected = struct.unpack_from("<H", data, end)[0]
            if actual != expected:
                raise ValueError(f"Checksum mismatch at {offset:#x}")
            if status == 0xFC:
                records.append(dict(offset=offset, group=group[:-1].decode("ascii"), key=name[:-1].decode("ascii"),
                                    length=value_len, type=kind, sequence=sequence, value=value))
            offset = end + 2
    if len({(r['group'], r['key']) for r in records}) != len(records):
        raise ValueError("Multiple valid records for one key; resolve freshness before using values")
    return records


def self_test():
    block = bytearray(b"\xff" * 4096)
    block[:12] = b"NVDM" + struct.pack("<I", 1) + bytes([0xE0, 0xF0, 1, 0xFF])
    header = HEADER.pack(0xFC, 0, 0xFF00, 0, 5, 5, 2, 0, 1, 1, 0)
    names, value = b"AB15\x001002\x00", b"\x12\x34"
    item = header + names + value + struct.pack("<H", checksum(header[1:], names, value))
    block[12:12 + len(item)] = item
    assert parse(block)[0]['value'] == value
    block[43] ^= 1
    try:
        parse(block)
    except ValueError:
        pass
    else:
        raise AssertionError("Corrupt record accepted")
    print("NVDM parser self-test passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?")
    parser.add_argument("--key")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if not args.path:
            parser.error("Specify a local backup")
        data = Path(args.path).read_bytes()
        records = parse(data)
        print(f"SHA256 {hashlib.sha256(data).hexdigest()}; {len(records)} unique valid keys; all record checksums verified")
        if args.key:
            selected = [r for r in records if r['key'].upper() == args.key.upper()]
            print(json.dumps([{**r, 'value': r['value'].hex()} for r in selected]))
        else:
            print(" ".join(f"{r['key']}:{r['length']}" for r in records))
