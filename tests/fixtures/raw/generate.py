#!/usr/bin/env python3
"""Build a deterministic CFA DNG with a real JPEG preview, using only the stdlib."""

import base64
import hashlib
import os
from pathlib import Path
import struct
import sys

WIDTH, HEIGHT = 6000, 4000
PREVIEW_WIDTH, PREVIEW_HEIGHT = 1620, 1080
PREVIEW_SHA256 = "15df570e067e83527c5142010bdd416a032bbc7418d80960f558e3f85bdac85d"
NAME = "L1000921.DNG"
MARKER = ".flea-test-sandbox"


class Tiff:
    """Classic little-endian TIFF, with aligned values and sorted IFD entries."""

    def __init__(self):
        self.data = bytearray(b"II\x2a\0\0\0\0\0")

    def blob(self, value):
        if len(self.data) % 2:
            self.data.append(0)
        offset = len(self.data)
        self.data.extend(value)
        return offset

    def ifd(self, entries):
        encoded = []
        for tag, kind, count, value in sorted(entries):
            slot = value.ljust(4, b"\0") if len(value) <= 4 else struct.pack("<I", self.blob(value))
            encoded.append(struct.pack("<HHI", tag, kind, count) + slot)
        return self.blob(struct.pack("<H", len(encoded)) + b"".join(encoded) + b"\0" * 4)


def short(tag, *values):
    return tag, 3, len(values), struct.pack("<" + "H" * len(values), *values)


def long(tag, *values):
    return tag, 4, len(values), struct.pack("<" + "I" * len(values), *values)


def text(tag, value):
    value = value.encode("ascii") + b"\0"
    return tag, 2, len(value), value


def rational(tag, *pairs):
    return tag, 5, len(pairs), b"".join(struct.pack("<II", *pair) for pair in pairs)


def build():
    preview = base64.b64decode(Path(__file__).with_name("preview.jpg.b64").read_bytes())
    if hashlib.sha256(preview).hexdigest() != PREVIEW_SHA256:
        raise ValueError("the committed JPEG seed has changed")
    tiff = Tiff()
    jpeg_offset = tiff.blob(preview)
    preview_ifd = tiff.ifd([
        long(0x00FE, 1), long(0x0100, PREVIEW_WIDTH), long(0x0101, PREVIEW_HEIGHT),
        short(0x0102, 8, 8, 8), short(0x0103, 7), short(0x0106, 6),
        long(0x0111, jpeg_offset), short(0x0115, 3), long(0x0116, PREVIEW_HEIGHT),
        long(0x0117, len(preview)), short(0x011C, 1), short(0x0212, 2, 2),
    ])
    exif_ifd = tiff.ifd([
        rational(0x829A, (1, 250)), rational(0x829D, (28, 10)), short(0x8827, 400),
        text(0x9003, "2026:09:12 18:31:00"), rational(0x920A, (35, 1)),
        long(0xA002, WIDTH), long(0xA003, HEIGHT), text(0xA434, "RF35mm F1.8 MACRO IS STM"),
    ])
    # An actual uncompressed 16-bit RGGB sensor plane, with a deterministic 12-bit ramp.
    row = struct.pack("<" + "H" * WIDTH, *(x % 4096 for x in range(WIDTH)))
    sensor_offset = tiff.blob(row * HEIGHT)
    matrix = b"".join(struct.pack("<ii", int(x == y), 1) for y in range(3) for x in range(3))
    ifd0 = tiff.ifd([
        long(0x00FE, 0), long(0x0100, WIDTH), long(0x0101, HEIGHT), short(0x0102, 16),
        short(0x0103, 1), short(0x0106, 32803), text(0x010F, "Canon"),
        text(0x0110, "Canon EOS R6"), long(0x0111, sensor_offset), short(0x0112, 1),
        short(0x0115, 1), long(0x0116, HEIGHT), long(0x0117, WIDTH * HEIGHT * 2),
        short(0x011C, 1), long(0x014A, preview_ifd), short(0x828D, 2, 2),
        (0x828E, 1, 4, bytes((0, 1, 1, 2))), long(0x8769, exif_ifd),
        (0xC612, 1, 4, bytes((1, 4, 0, 0))), (0xC613, 1, 4, bytes((1, 1, 0, 0))),
        text(0xC614, "Canon EOS R6"), (0xC616, 1, 3, bytes((0, 1, 2))), short(0xC619, 1, 1),
        rational(0xC61A, (0, 1)), long(0xC61D, 4095),
        rational(0xC61E, (1, 1), (1, 1)), short(0xC61F, 0, 0),
        long(0xC620, WIDTH, HEIGHT),
        (0xC621, 10, 9, matrix), rational(0xC628, (1, 1), (1, 1), (1, 1)), short(0xC65A, 21),
    ])
    struct.pack_into("<I", tiff.data, 4, ifd0)
    return tiff.data


def main():
    if len(sys.argv) != 2:
        raise ValueError("usage: generate.py ABSOLUTE_MARKED_ROOT")
    requested = Path(sys.argv[1])
    root = requested.resolve(strict=True)
    if not requested.is_absolute() or requested != root or not (root / MARKER).is_file():
        raise ValueError("output must be an absolute sandbox root with its own marker")
    data = build()
    path = root / NAME
    # Exclusive creation refuses every overwrite, including a pre-existing symlink.
    with path.open("xb") as output:
        output.write(data)
    os.chmod(path, 0o644)
    print(hashlib.sha256(data).hexdigest() + "  " + NAME)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit("raw fixture: " + str(error))
