# What each GUI entrant can actually thumbnail

Written by tools/flea-bench-capability on 2026-09-01T18:13:37-04:00. Eight files, one per format, a
private cache per entrant, and 45 seconds each. **Nothing here is ranked and no
timing is taken.** The field bench's format column answers a different question, how far an
entrant got through a 2000-file directory whose names sort by format, and it was being read
as this one.

Formats offered: jpg png webp heic mp4 webm mkv txt

**strata's row was re-measured on 2026-09-03 and its earlier reading was wrong.** Every other row
is the 45-second cache-counting pass named above. strata persists no thumbnail: it renders each one
in a sandboxed helper that writes `result.png` into `/tmp/strata-preview-<pid>-<n>` and deletes the
directory on drop, then holds the image in a 256-entry, 64 MiB in-memory cache. A cache count is
structurally blind to that, so this file previously read "strata thumbnails nothing" while strata
drew every format it supports on screen. Its row below is counted by a live watch instead, one
format at a time, and is not comparable to the other rows' instrument.

- **flea** thumbnails jpg, png, webp, heic, mp4, webm, mkv
  - cannot produce: txt
  - raw: produced `heic=1;jpg=1;mkv=1;mp4=1;png=1;txt=0;webm=1;webp=1;unknown=0`, refused `none=0`; last new thumbnail at 1s of 45s
- **nautilus** thumbnails jpg, png, webp, heic, mp4, webm
  - cannot produce: mkv, txt
  - raw: produced `heic=1;jpg=1;mkv=0;mp4=1;png=1;txt=0;webm=1;webp=1;unknown=0`, refused `none=0`; last new thumbnail at 1s of 45s
- **thunar** thumbnails jpg, png, webp, heic, mp4, webm, mkv
  - cannot produce: txt
  - raw: produced `heic=1;jpg=1;mkv=1;mp4=1;png=1;txt=0;webm=1;webp=1;unknown=0`, refused `none=0`; last new thumbnail at 2s of 45s
- **pcmanfm** thumbnails png, mp4, webm
  - cannot produce: jpg, webp, heic, mkv, txt
  - raw: produced `heic=0;jpg=0;mkv=0;mp4=1;png=1;txt=0;webm=1;webp=0;unknown=0`, refused `none=0`; last new thumbnail at 2s of 45s
- **nemo** thumbnails jpg, webp
  - cannot produce: png, heic, mp4, webm, mkv, txt
  - raw: produced `heic=0;jpg=1;mkv=0;mp4=0;png=0;txt=0;webm=0;webp=1;unknown=0`, refused `none=0`; last new thumbnail at 1s of 45s
- **dolphin** thumbnails jpg, png, webp, mp4, webm, mkv
  - cannot produce: heic, txt
  - raw: produced `heic=0;jpg=1;mkv=1;mp4=1;png=1;txt=0;webm=1;webp=1;unknown=0`, refused `none=0`; last new thumbnail at 1s of 45s
- **strata** thumbnails jpg, png, webp, mp4, webm, mkv
  - cannot produce: heic, txt
  - raw: rendered `jpg=1;png=1;webp=1;heic=0;mp4=1;webm=1;mkv=1;txt=0`; counted live, one format at a time, 30s each
  - **measured by live watch, not by cache count.** This entrant writes each thumbnail
    to a scratch directory it deletes immediately, so it persists nothing a cache count
    can see and a cache count reports it as capable of nothing.

**txt is the control.** No thumbnailer draws a text file, so an entrant that claims one here
is a broken measurement rather than a capable entrant.
