"""Check the frame arc and the page boundary in a captured HTML preview."""
import json
import math
from pathlib import Path
import subprocess
import sys


def color(text):
    # Sample input: "#ff2345bc" (#aarrggbb) and "#2345bc" both return (35, 69, 188).
    text = text.lstrip('#')
    if len(text) == 8:
        text = text[2:]
    return tuple(int(text[index:index + 2], 16) for index in (0, 2, 4))


def check(png, state):
    # Sample input: magick identify -format '%w %h' answers "1100 700".
    width, height = map(int, subprocess.check_output(['magick', 'identify', '-format', '%w %h', str(png)], text=True).split())
    pixels = subprocess.check_output(['magick', str(png), '-depth', '8', 'rgba:-'])
    assert len(pixels) == width * height * 4
    scale = width / state['window']['width']
    assert abs(height / state['window']['height'] - scale) < 0.02, 'capture and window aspect differ'
    x, y, w, h = [float(part) * scale for part in state['frame'].split()]
    radius = min(state['radius'] * scale, w / 2, h / 2)
    line = state['hairline'] * scale
    if radius <= line + 1:
        print('HTML_CORNER square compositor radius=%s %s' % (state['radius'], png), flush=True)
        return
    ring, page = color(state['ringColor']), color(state.get('pageColor', '#ffffff'))

    def pixel(dx, dy, right, bottom):
        px = math.floor(x + w - 1 - dx if right else x + dx)
        py = math.floor(y + h - 1 - dy if bottom else y + dy)
        assert 0 <= px < width and 0 <= py < height, (px, py, width, height)
        start = (py * width + px) * 4
        return tuple(pixels[start:start + 4])

    interior = [pixel(w * fx, h * fy, False, False) for fx in (0.2, 0.5, 0.8) for fy in (0.4, 0.6, 0.8)]
    assert any(p[3] > 240 and max(abs(p[i] - page[i]) for i in range(3)) < 12 for p in interior), 'page interior is missing'
    corners = [(False, True), (True, True)]
    if state['column']:
        corners += [(False, False), (True, False)]
    for right, bottom in corners:
        arc = []
        outside = []
        inside = []
        for dy in range(math.ceil(line), math.ceil(radius)):
            for dx in range(math.ceil(line), math.ceil(radius)):
                distance = math.hypot(radius - dx - 0.5, radius - dy - 0.5)
                sample = pixel(dx, dy, right, bottom)
                if radius - line <= distance <= radius:
                    arc.append(sample)
                if distance >= radius - line + 0.5:
                    outside.append(sample)
                if max(0, radius - line - 1.25) <= distance <= radius - line - 0.75:
                    inside.append(sample)
        assert arc and outside and inside, 'radius has no observable inner arc'
        present = [p for p in arc if p[3] > 100 and max(abs(p[i] - ring[i]) for i in range(3)) <= 48]
        leaked = [p for p in outside if p[3] > 240 and max(abs(p[i] - page[i]) for i in range(3)) < 12]
        filled = [p for p in inside if p[3] > 225 and max(abs(p[i] - page[i]) for i in range(3)) < 24]
        label = ('bottom' if bottom else 'top') + ('-right' if right else '-left')
        assert present, '%s ring absent on arc: %s' % (label, arc)
        assert not leaked, '%s page paints outside inner arc: %s' % (label, leaked)
        assert len(filled) >= len(inside) * 0.75, '%s page does not reach inner arc: %s' % (label, inside)
        print('HTML_CORNER PASS %s ring=%s outside=%s inside=%s/%s %s' % (label, len(present), len(outside), len(filled), len(inside), png), flush=True)


def main():
    if sys.argv[1] == '--log':
        count = 0
        failures = []
        for line in Path(sys.argv[2]).read_text().splitlines():
            # Sample input: qml: HTML_CORNER_STATE {"name":"html-column","accelerated":true,"column":true}
            if 'HTML_CORNER_STATE ' not in line:
                continue
            state = json.loads(line.split('HTML_CORNER_STATE ', 1)[1])
            assert state.get('accelerated'), 'corner probe requires the RHI renderer: %s' % state
            try:
                check(Path(sys.argv[3]) / (state['name'] + '.png'), state)
            except AssertionError as error:
                failures.append(str(error))
                print('HTML_CORNER FAIL ' + state['name'] + ': ' + str(error), flush=True)
            count += 1
        assert count == 2, 'expected both HTML frame captures, got %s' % count
        assert not failures, failures
    else:
        check(Path(sys.argv[1]), json.loads(sys.argv[2]))


if __name__ == '__main__':
    main()
