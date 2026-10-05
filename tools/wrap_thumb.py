"""Wrap an owned raw Thumb firmware dump as ELF for macOS llvm-objdump."""
from pathlib import Path
import struct
import sys


def wrap(data, address):
    image = bytearray(256)
    image += data
    image += b"\0" * (-len(image) % 4)
    strings_offset = len(image)
    image += b"\0$t\0"
    symbols_offset = len(image)
    image += bytes(16) + struct.pack("<IIIBBH", 1, address, 0, 0, 0, 1)
    names = b"\0.text\0.strtab\0.symtab\0.shstrtab\0"
    names_offset = len(image)
    image += names
    image += b"\0" * (-len(image) % 4)
    section_offset = len(image)
    section = struct.Struct("<IIIIIIIIII")
    image += bytes(40)
    image += section.pack(1, 1, 6, address, 256, len(data), 0, 0, 2, 0)
    image += section.pack(7, 3, 0, 0, strings_offset, 4, 0, 0, 1, 0)
    image += section.pack(15, 2, 0, 0, symbols_offset, 32, 2, 2, 4, 16)
    image += section.pack(23, 3, 0, 0, names_offset, len(names), 0, 0, 1, 0)
    ident = b"\x7fELF" + bytes([1, 1, 1, 0]) + bytes(8)
    header = ident + struct.pack("<HHIIIIIHHHHHH", 2, 40, 1, address | 1, 0, section_offset, 0x05000000, 52, 0, 0, 40, 5, 4)
    image[:52] = header
    return bytes(image)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        raw = bytes.fromhex("00bf7047")
        result = wrap(raw, 0x08000000)
        assert result[256:260] == raw and result[:4] == b"\x7fELF"
        offset = struct.unpack_from("<I", result, 32)[0]
        assert offset + 5 * 40 == len(result)
        print("Thumb ELF wrapper self-test passed")
    elif len(sys.argv) == 4:
        destination = Path(sys.argv[3])
        with destination.open("xb") as handle:
            handle.write(wrap(Path(sys.argv[1]).read_bytes(), int(sys.argv[2], 0)))
        print(destination)
    else:
        raise SystemExit("Usage: wrap_thumb.py INPUT BASE_ADDRESS NEW_OUTPUT | --self-test")
