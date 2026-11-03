#!/usr/bin/env python3
"""Build the two tiny, uncompressed SquashFS v4 images used by the real 7z test."""

import argparse
import hashlib
from pathlib import Path
import struct
import zlib

# struct.calcsize("<5I6H8Q"): file data starts right after the superblock.
SUPERBLOCK_SIZE = 96


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def icon_png():
    header = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    # A fixed zlib stream containing one unfiltered red RGBA pixel, without encoder-version drift.
    pixels = bytes.fromhex("7801010500faff00ff0000ff050001ff")
    assert zlib.decompress(pixels) == b"\x00\xff\x00\x00\xff"
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", pixels) + chunk(b"IEND", b"")


def metadata(data):
    assert len(data) < 8192
    return struct.pack("<H", 0x8000 | len(data)) + data


def squashfs(with_link):
    # Disk layouts: https://github.com/plougher/squashfs-tools/blob/master/squashfs-tools/squashfs_fs.h
    entries = [("AppRun", 2, b"#!/bin/sh\n", 0o755), ("app.png", 2, icon_png(), 0o644)]
    if with_link:
        entries.insert(0, (".DirIcon", 3, b"app.png", 0o777))
    data = bytearray()
    inodes = bytearray()
    directory = bytearray(struct.pack("<III", len(entries) - 1, 0, 1))
    for number, (name, kind, payload, mode) in enumerate(entries, 1):
        offset = len(inodes)
        inodes.extend(struct.pack("<HHHHII", kind, mode, 0, 0, 0, number))
        if kind == 3:
            inodes.extend(struct.pack("<II", 1, len(payload)) + payload)
        else:
            inodes.extend(struct.pack("<IIIII", SUPERBLOCK_SIZE + len(data), 0xFFFFFFFF, 0, len(payload), 0x1000000 | len(payload)))
            data.extend(payload)
        encoded = name.encode("ascii")
        directory.extend(struct.pack("<HhHH", offset, number - 1, kind, len(encoded) - 1) + encoded)
    root_inode = len(inodes)
    inode_count = len(entries) + 1
    inodes.extend(struct.pack("<HHHHII", 1, 0o755, 0, 0, 0, inode_count))
    inodes.extend(struct.pack("<IIHHI", 0, 2, len(directory) + 3, 0, inode_count + 1))
    inode_start = SUPERBLOCK_SIZE + len(data)
    inode_block = metadata(inodes)
    directory_start = inode_start + len(inode_block)
    directory_block = metadata(directory)
    id_start = directory_start + len(directory_block)
    id_block = metadata(struct.pack("<I", 0))
    id_index = id_start + len(id_block)
    bytes_used = id_index + 8
    invalid = 0xFFFFFFFFFFFFFFFF
    # No compressed blocks, fragments, xattrs, export table or duplicate detection; one root-owned id.
    flags = 1 | 2 | 8 | 16 | 256 | 512 | 2048
    superblock = struct.pack("<5I6H8Q", 0x73717368, inode_count, 0, 131072, 0,
        1, 17, flags, 1, 4, 0, root_inode, bytes_used, id_index, invalid,
        inode_start, directory_start, id_start, invalid)
    assert len(superblock) == SUPERBLOCK_SIZE
    return superblock + data + inode_block + directory_block + id_block + struct.pack("<Q", id_start)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="compare committed fixtures without writing")
    mode.add_argument("--output", type=Path, help="an absolute, marked scratch root for a fresh build")
    args = parser.parse_args()
    outputs = {"with-dir-icon.sqfs": squashfs(True), "without-dir-icon.sqfs": squashfs(False)}
    checksums = "".join(hashlib.sha256(data).hexdigest() + "  " + name + "\n" for name, data in outputs.items())
    if args.check:
        root = Path(__file__).resolve().parent
        for name, data in outputs.items():
            assert (root / name).read_bytes() == data, name + " differs from the deterministic generator"
        assert (root / "SHA256SUMS").read_text() == checksums
    else:
        root = args.output
        if not root.is_absolute() or not (root / ".flea-test-sandbox").is_file():
            parser.error("--output needs an absolute root with .flea-test-sandbox")
        for name, data in outputs.items():
            with (root / name).open("xb") as output:
                output.write(data)
        with (root / "SHA256SUMS").open("x") as output:
            output.write(checksums)
    print(checksums, end="")


if __name__ == "__main__":
    main()
