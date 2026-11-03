# RAW capture fixture

`generate.py` builds `L1000921.DNG` using Python's standard library. The output has a complete, uncompressed 6000 x 4000 RGGB sensor plane, 16-bit samples holding a deterministic 12-bit ramp, DNG version and color calibration tags, and a decodable 1620 x 1080 embedded JPEG. It is generated test data, not a photograph from a camera. No generated DNG is checked into the repository.

The JPEG seed in `preview.jpg.b64` was made with FFmpeg 7.1.5 using this command:

```sh
ffmpeg -v error -f lavfi -i testsrc=size=1620x1080:rate=1 -frames:v 1 \
  -c:v mjpeg -q:v 3 -pix_fmt yuvj420p -threads 1 -fflags +bitexact \
  -flags:v +bitexact -map_metadata -1 preview.jpg
```

The committed seed makes generator output independent of the installed encoder version. Its decoded SHA-256 is `15df570e067e83527c5142010bdd416a032bbc7418d80960f558e3f85bdac85d`; `SHA256SUMS` pins the generated DNG. To rebuild, create a fresh absolute directory with its own `.flea-test-sandbox` marker, then run `python3 tests/fixtures/raw/generate.py /absolute/marked/root`. The generator refuses existing output.

IFD0 holds the uncompressed CFA plane, Make `Canon`, Model `Canon EOS R6`, Orientation 1, and pointers to the EXIF IFD and reduced-preview SubIFD. The latter carries Compression 7, StripOffsets and StripByteCounts for the real JPEG. EXIF carries ExposureTime 1/250, FNumber 28/10, ISO 400, LensModel `RF35mm F1.8 MACRO IS STM`, FocalLength 35/1, DateTimeOriginal `2026:09:12 18:31:00`, and PixelXDimension/PixelYDimension 6000/4000.

This exercises `rawembed::inspect`, `rawtiff::inspect_file` and `walk_ifd`, the JPEG single-strip candidate path, EXIF-only fact extraction, and `rawpreview::ensure_in`. `raw-fixture.sh` checks the output hash, every written DNG extension tag's type/count, and the live backend's meta and Properties replies. The extracted JPEG must have the seed's exact SHA-256 and a 1620 x 1080 SOF, then fully decode with FFmpeg's `-xerror -err_detect explode`. Regression controls feed the checker a truncated JPEG and a real 1 x 1 JPEG despite forged meta dimensions; both must be rejected. The valid seed must pass, the strict decoder must reject corruption independently, and the legacy CFAPlaneColor SHORT[1] encoding must fail the tag audit.

CFAPlaneColor is BYTE[3] with values 0, 1, 2, corresponding to the RGGB CFAPattern. The type/count rules come from the DNG Tags section of [Adobe's DNG 1.6 specification](https://paulbourke.org/dataformats/dng/dng_spec_1_6_0_0.pdf), including the CFAPlaneColor subsection. The checker audits all 13 DNG extension tags the generator writes.

Native selectors are `ui:cap_raw_grid`, `ui:cap_raw_columns`, `ui:cap_raw_quicklook`, and `ui:cap_raw_properties`. They run only by name through `tests/ui.sh`; they need Hyprland, the native input driver and whole-window screenshots. The grid uses the board's five filename stems with `.DNG` extensions, and all other captures select `L1000921.DNG`. DNG's kind and generated file size replace the board's CR3 kind and size. The six photo facts and capture/modified timestamps retain the board values.

Each native case prints `SHOT` and `CROP` paths. Crops include every grid tile, the preview frame and complete fact card, the Quick Look surface and its 27-pixel caption band, and the Properties card. Existing IPC exposes column fact strings, decoded thumbnail readiness and Properties source facts. Quick Look's caption text and the Properties photo labels have no IPC reader, so those crops still require native visual review. `preview-raw.sh` separately asserts the caption in the real QML component over its stub backend.
