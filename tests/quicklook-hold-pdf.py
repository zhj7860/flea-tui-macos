# Wraps one JPEG as a one-page PDF whose page is the picture at one point per pixel: quicklook-hold-pdf.py IN.jpg OUT.pdf.
import struct
import sys


def jpeg_size(data):
    # Sample input: a baseline JPEG whose SOF0 segment reads height 4000 and width 3000 gives (3000, 4000).
    at = 2
    while at < len(data):
        marker, length = data[at + 1], struct.unpack(">H", data[at + 2:at + 4])[0]
        if 0xC0 <= marker <= 0xC2:
            height, width = struct.unpack(">HH", data[at + 5:at + 9])
            return width, height
        at += 2 + length
    raise SystemExit("no SOF segment in " + sys.argv[1])


picture = open(sys.argv[1], "rb").read()
width, height = jpeg_size(picture)
draw = b"q %d 0 0 %d 0 0 cm /I Do Q" % (width, height)
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << /XObject << /I 4 0 R >> >> /Contents 5 0 R >>"
    % (width, height),
    b"<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8"
    b" /Filter /DCTDecode /Length %d >>\nstream\n" % (width, height, len(picture)) + picture + b"\nendstream",
    b"<< /Length %d >>\nstream\n" % len(draw) + draw + b"\nendstream",
]
out = bytearray(b"%PDF-1.4\n")
offsets = []
for number, body in enumerate(objects, 1):
    offsets.append(len(out))
    out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
out += b"".join(b"%010d 00000 n \n" % at for at in offsets)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
open(sys.argv[2], "wb").write(out)
