"""Check the native clip card at the lifecycle fixture's page sample."""
import json
import math
from pathlib import Path
import subprocess
import sys

# Capture height over window height may differ from the width ratio by this much before the capture is refused.
ASPECT_TOLERANCE = 0.02
# The sampled pixel must be nearly opaque, so a half-faded frame never passes.
OPAQUE_ALPHA = 240
# The fixture page is flat (35, 69, 188); a drawn page lands within 11 per channel after RHI blending.
PAGE_RGB = (35, 69, 188)
PAGE_TOLERANCE = 11
# The cleared card shows the canvas (16, 19, 21) within 3 per channel.
CANVAS_RGB = (16, 19, 21)
CANVAS_TOLERANCE = 3


def check(png, state, phase):
    # Sample input: magick identify -format '%w %h' prints "380 280".
    width, height = map(int, subprocess.check_output(['magick', 'identify', '-format', '%w %h', str(png)], text=True).split())
    scale = width / state['window']['width']
    assert abs(height / state['window']['height'] - scale) < ASPECT_TOLERANCE, 'capture and window aspect differ'
    # Sample input: frame "40 40 300 200", window 380x280; p{20,20} samples PNG pixel (60,60) at scale 1.
    x, y, w, h = map(float, state['frame'].split())
    assert w > 20 and h > 20, 'card sample is outside the card'
    px, py = math.floor((x + 20) * scale), math.floor((y + 20) * scale)
    assert 0 <= px < width and 0 <= py < height, 'card sample is outside the capture'
    rgba = subprocess.check_output(['magick', str(png), '-crop', '1x1+%s+%s' % (px, py), '+repage', '-depth', '8', 'rgba:-'])
    assert len(rgba) == 4, 'card sample is not one RGBA pixel'
    painted = rgba[3] > OPAQUE_ALPHA and max(abs(rgba[i] - PAGE_RGB[i]) for i in range(3)) <= PAGE_TOLERANCE
    if phase == 'ready':
        assert painted, 'ready page texture missing at card p{20,20}'
        return 'HTML_CLIP PASS ready page pixels at card p{20,20}'
    assert phase in ('failed', 'large'), 'unknown clip phase'
    cleared = rgba[3] > OPAQUE_ALPHA and max(abs(rgba[i] - CANVAS_RGB[i]) for i in range(3)) <= CANVAS_TOLERANCE
    assert cleared, phase + ' retains page pixels at card p{20,20}'
    return 'HTML_CLIP PASS ' + phase + ' leaves no stale page pixels at card p{20,20}'


def main():
    try:
        # Sample input: argv[3] is '{"frame": "40 40 300 200", "window": {"width": 380, "height": 280}}'.
        print(check(Path(sys.argv[2]), json.loads(sys.argv[3]), sys.argv[1]), flush=True)
    except (AssertionError, KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print('HTML_CLIP FAIL ' + str(error), flush=True)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
