#!/usr/bin/env python3
"""Prove that the generated fixture reaches the real RAW and Properties paths."""

import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import selectors
import struct
import subprocess
import sys
import time

REPLY_TIMEOUT_S = 20
PIPE_READ_BYTES = 65536
DECODE_TIMEOUT_S = 20
SHUTDOWN_TIMEOUT_S = 10
KILL_WAIT_S = 5
DNG_TAGS = {
    0xC612: ((1,), 4),  # DNGVersion
    0xC613: ((1,), 4),  # DNGBackwardVersion
    0xC614: ((2,), 13),  # UniqueCameraModel, including its NUL
    0xC616: ((1,), 3),  # CFAPlaneColor, ColorPlanes = 3
    0xC619: ((3,), 2),  # BlackLevelRepeatDim
    0xC61A: ((3, 4, 5), 1),  # BlackLevel, RepeatRows * RepeatCols * SamplesPerPixel
    0xC61D: ((3, 4), 1),  # WhiteLevel, SamplesPerPixel = 1
    0xC61E: ((5,), 2),  # DefaultScale
    0xC61F: ((3, 4, 5), 2),  # DefaultCropOrigin
    0xC620: ((3, 4, 5), 2),  # DefaultCropSize
    0xC621: ((10,), 9),  # ColorMatrix1, ColorPlanes * 3
    0xC628: ((3, 5), 3),  # AsShotNeutral, ColorPlanes
    0xC65A: ((3,), 1),  # CalibrationIlluminant1
}
PHOTO = {
    "make": "Canon", "model": "Canon EOS R6", "lens": "RF35mm F1.8 MACRO IS STM",
    "exp": [1, 250], "fnum": [28, 10], "iso": 400, "focal": [35, 1],
    "taken": "2026:09:12 18:31:00", "w": 6000, "h": 4000,
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


# Sample input: II 2A 00 08 00 00 00, then an IFD with 16 C6 01 00 03 00 00 00 00 01 02 00 (BYTE[3] CFAPlaneColor).
def ifd(data, offset):
    count = struct.unpack_from("<H", data, offset)[0]
    entries = {}
    sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 10: 8}
    for index in range(count):
        at = offset + 2 + index * 12
        tag, kind, n = struct.unpack_from("<HHI", data, at)
        if tag >= 0xC600:
            require(tag in DNG_TAGS, "unaudited DNG tag: " + hex(tag))
            types, count = DNG_TAGS[tag]
            require(kind in types and n == count, "DNG tag type/count differs: " + hex(tag))
        length = sizes[kind] * n
        value_at = at + 8 if length <= 4 else struct.unpack_from("<I", data, at + 8)[0]
        entries[tag] = data[value_at:value_at + length]
    return entries


# Sample input: FF D8 ... FF C0 00 11 08 04 38 06 54 ... (SOF0, height 1080, width 1620).
def jpeg_size(data):
    require(data[:2] == b"\xff\xd8", "extracted preview has no JPEG SOI")
    at = 2
    while at < len(data):
        require(data[at] == 0xFF, "invalid JPEG marker")
        while at < len(data) and data[at] == 0xFF:
            at += 1
        require(at < len(data), "truncated JPEG marker")
        marker = data[at]
        at += 1
        require(marker not in (0xD8, 0xD9, 0xDA), "JPEG ended before its SOF")
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue
        require(at + 2 <= len(data), "truncated JPEG segment length")
        length = struct.unpack_from(">H", data, at)[0]
        require(length >= 2 and at + length <= len(data), "truncated JPEG segment")
        if marker in (0xC0, 0xC1, 0xC2):
            require(length >= 8, "truncated JPEG SOF")
            height, width = struct.unpack_from(">HH", data, at + 3)
            return width, height
        at += length
    raise ValueError("extracted preview has no JPEG SOF")


def decode_preview(path):
    subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-err_detect", "explode", "-i", str(path), "-f", "null", "-"],
                   check=True, timeout=DECODE_TIMEOUT_S, stdout=subprocess.DEVNULL)


def extracted_preview(path):
    data = path.read_bytes()
    seed = base64.b64decode(Path(__file__).with_name("preview.jpg.b64").read_bytes())
    digest = hashlib.sha256(data).hexdigest()
    require(digest == hashlib.sha256(seed).hexdigest(), "extracted JPEG SHA-256 differs from embedded preview")
    require(jpeg_size(data) == (1620, 1080), "extracted JPEG SOF dimensions differ")
    decode_preview(path)
    print("raw-fixture: extracted sha256=" + digest + " SOF=1620x1080 strict decode passed")


def fixture(path):
    data = path.read_bytes()
    expected = Path(__file__).with_name("SHA256SUMS").read_text().split()[0]
    require(hashlib.sha256(data).hexdigest() == expected, "generated DNG SHA-256 differs")
    root = ifd(data, struct.unpack_from("<I", data, 4)[0])
    require(DNG_TAGS.keys() <= root.keys(), "a required fixture DNG tag is absent")
    require(root[0xC616] == bytes((0, 1, 2)), "CFAPlaneColor is not the RGGB RGB mapping")
    sensor_at = struct.unpack("<I", root[0x0111])[0]
    sensor_size = struct.unpack("<I", root[0x0117])[0]
    require(sensor_size == 6000 * 4000 * 2, "the full sensor plane is absent")
    require(len(data[sensor_at:sensor_at + sensor_size]) == sensor_size, "sensor data is truncated")
    require(struct.unpack_from("<4H", data, sensor_at) == (0, 1, 2, 3), "sensor ramp differs")
    preview = ifd(data, struct.unpack("<I", root[0x014A])[0])
    at = struct.unpack("<I", preview[0x0111])[0]
    size = struct.unpack("<I", preview[0x0117])[0]
    seed = base64.b64decode(Path(__file__).with_name("preview.jpg.b64").read_bytes())
    require(data[at:at + size] == seed, "the embedded JPEG differs from the real seed")
    print("raw-fixture: sha256=" + expected + " sensor=6000x4000 preview=1620x1080")


def backend(binary, root, path):
    environment = dict(os.environ, XDG_CACHE_HOME=str(root / "cache"),
                       XDG_STATE_HOME=str(root / "state"), HOME=str(root / "home"),
                       FLEA_UNDO_DIR=str(root / "undo"))
    buffer = bytearray()
    with (root / "backend.log").open("xb") as log:
        process = subprocess.Popen([binary, "--backend"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=log, env=environment)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        def send(request):
            process.stdin.write((json.dumps(request) + "\n").encode())
            process.stdin.flush()

        # Sample input: {"t":"meta","row":0,"raw":{"file":"/sandbox/cache/a.jpg","w":1620,"h":1080}} followed by a newline.
        def receive(predicate):
            deadline = time.monotonic() + REPLY_TIMEOUT_S
            while time.monotonic() < deadline:
                if b"\n" in buffer:
                    line, _, rest = buffer.partition(b"\n")
                    buffer[:] = rest
                    reply = json.loads(line)
                    require(reply.get("t") != "error", "backend refused: " + str(reply))
                    if predicate(reply):
                        return reply
                elif selector.select(max(0, deadline - time.monotonic())):
                    chunk = os.read(process.stdout.fileno(), PIPE_READ_BYTES)
                    require(bool(chunk), "backend ended before its reply")
                    buffer.extend(chunk)
            raise ValueError("backend reply timed out")

        try:
            send({"c": "list", "path": str(path.parent), "first": 8})
            listed = receive(lambda r: r.get("t") == "listed")
            require(listed.get("n") == 1, "fixture listing does not contain one RAW")
            send({"c": "meta", "row": 0})
            meta = receive(lambda r: r.get("t") == "meta")
            require(meta.get("photo") == PHOTO, "live meta photo facts differ: " + str(meta))
            raw = meta.get("raw") or {}
            require((raw.get("w"), raw.get("h"), raw.get("orient")) == (1620, 1080, 1),
                    "live RAW extraction did not return the preview dimensions")
            cached = Path(raw["file"]).resolve(strict=True)
            require(cached.is_relative_to(root / "cache"), "extraction escaped the owned cache")
            extracted_preview(cached)
            send({"c": "menuaction", "op": "snapshot", "id": 41, "rows": [0]})
            snapshot = receive(lambda r: r.get("t") == "menuaction" and r.get("op") == "snapshot")
            require(snapshot.get("ok") is True, "Properties snapshot failed")
            send({"c": "menuaction", "op": "properties", "id": 41})
            props = receive(lambda r: r.get("t") == "menuaction" and r.get("op") == "properties")
            require(props.get("ok") is True and props.get("photo") == PHOTO,
                    "live Properties photo facts differ: " + str(props))
            require(props.get("path") == str(path) and props.get("bytes") == path.stat().st_size,
                    "Properties describes a different file")
            print("raw-fixture: meta and Properties photo=" + json.dumps(PHOTO, separators=(",", ":")))
            print("raw-fixture: extracted JPEG fully decoded")
            process.stdin.close()
            require(process.wait(timeout=SHUTDOWN_TIMEOUT_S) == 0, "backend shutdown failed")
        finally:
            selector.close()
            if process.poll() is None:
                process.kill()
                process.wait(timeout=KILL_WAIT_S)


def main():
    binary, directory = sys.argv[1:]
    root = Path(directory).resolve(strict=True)
    require((root / ".flea-test-sandbox").is_file(), "test root has no marker")
    path = root / "raw" / "L1000921.DNG"
    fixture(path)
    stamp = datetime(2026, 9, 18, 20, 10, tzinfo=timezone.utc).timestamp()
    os.utime(path, (stamp, stamp))
    backend(binary, root, path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit("FAIL raw-fixture: " + str(error))
