#!/usr/bin/env python3
"""Feed the real backend checker forged cache bytes without trusting meta's dimensions."""

import base64
import contextlib
import io
import json
from pathlib import Path
import subprocess
import struct
import sys

import check
import generate

FFMPEG_TIMEOUT_S = 20
STUB = '''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
config = json.loads(Path(__file__).with_name("reply.json").read_text())
# Sample input, one request per line: {"c":"meta","row":0}
for line in sys.stdin:
    request = json.loads(line)
    if request["c"] == "list":
        reply = {"t": "listed", "n": 1}
    elif request["c"] == "meta":
        reply = {"t": "meta", "photo": config["photo"],
                 "raw": {"file": config["cached"], "w": 1620, "h": 1080, "orient": 1}}
    else:
        reply = {"t": "menuaction", "op": request["op"], "ok": True,
                 "photo": config["photo"], "path": config["path"], "bytes": config["bytes"]}
    print(json.dumps(reply), flush=True)
'''


# Sample input: a generated little-endian DNG whose IFD0 includes BYTE[3] CFAPlaneColor.
def dng_control():
    data = generate.build()
    offset = struct.unpack_from("<I", data, 4)[0]
    fields = check.ifd(data, offset)
    check.require(check.DNG_TAGS.keys() <= fields.keys() and fields[0xC616] == bytes((0, 1, 2)),
                  "generated DNG tags or CFAPlaneColor values differ")
    count = struct.unpack_from("<H", data, offset)[0]
    for index in range(count):
        at = offset + 2 + index * 12
        if struct.unpack_from("<H", data, at)[0] == 0xC616:
            struct.pack_into("<HI", data, at + 2, 3, 1)
            break
    try:
        check.ifd(data, offset)
    except ValueError as error:
        check.require("type/count differs: 0xc616" in str(error), "unexpected DNG refusal: " + str(error))
        print("raw-check-selftest: all 13 DNG tags passed; legacy SHORT[1] CFAPlaneColor rejected")
        return
    raise ValueError("legacy SHORT[1] CFAPlaneColor was accepted")


def main():
    root = Path(sys.argv[1]).resolve(strict=True)
    check.require((root / ".flea-test-sandbox").is_file(), "selftest root has no marker")
    dng_control()
    seed = base64.b64decode(Path(__file__).with_name("preview.jpg.b64").read_bytes())
    failed = 0
    for name in ("seed", "corrupt", "one"):
        case = root / ("check-" + name)
        case.mkdir()
        (case / ".flea-test-sandbox").touch()
        (case / "cache").mkdir()
        path = case / "L1000921.DNG"
        path.write_bytes(b"owned test selection")
        cached = case / "cache" / "preview.jpg"
        if name == "one":
            source = case / "seed.jpg"
            source.write_bytes(seed)
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-vf", "scale=1:1",
                            "-pix_fmt", "yuvj444p", "-c:v", "mjpeg", "-threads", "1", str(cached)],
                           check=True, timeout=FFMPEG_TIMEOUT_S)
        else:
            cached.write_bytes(seed if name == "seed" else seed[:len(seed) // 2])
        stub = case / "backend"
        stub.write_text(STUB)
        stub.chmod(0o700)
        (case / "reply.json").write_text(json.dumps({"photo": check.PHOTO, "cached": str(cached),
                                                    "path": str(path), "bytes": path.stat().st_size}))
        rejected = False
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                check.backend(str(stub), case, path)
        except ValueError as error:
            check.require("extracted JPEG SHA-256 differs" in str(error), "unexpected checker refusal: " + str(error))
            rejected = True
        correct = rejected == (name != "seed")
        failed += not correct
        print("raw-check-selftest: " + name + (" passed" if correct else " FAILED")
              + (" (rejected)" if rejected else " (accepted)"))
        check.require(check.jpeg_size(cached.read_bytes()) == ((1, 1) if name == "one" else (1620, 1080)),
                      "the negative control's actual SOF dimensions differ")
        if name == "corrupt":
            try:
                check.decode_preview(cached)
            except subprocess.CalledProcessError:
                print("raw-check-selftest: strict decode rejected corrupt JPEG")
            else:
                print("raw-check-selftest: strict decode FAILED (accepted corrupt JPEG)")
                failed += 1
    return int(failed > 0)


if __name__ == "__main__":
    sys.exit(main())
