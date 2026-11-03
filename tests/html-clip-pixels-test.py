"""Exercise the native pixel check with the real software reload captures."""
import json
from pathlib import Path
import subprocess
import sys

folder = Path(sys.argv[1])
state = json.dumps({'frame': '0 0 300 200', 'window': {'width': 300, 'height': 200}})
checker = Path(__file__).with_name('html-clip-pixels.py')
records = []
blank = folder / 'html-clip-blank.png'
assert not blank.exists(), 'refusing existing pixel-control image'
subprocess.run(['magick', str(folder / 'html-reload-before.png'), '-fill', '#101315', '-colorize', '100', str(blank)], check=True)
for phase in ('ready', 'failed', 'large'):
    for good in (True, False):
        blue = (phase == 'ready') == good
        png = folder / 'html-reload-after.png' if blue else blank
        result = subprocess.run([sys.executable, str(checker), phase, str(png), state], capture_output=True, text=True)
        expected = ('HTML_CLIP PASS ready page pixels at card p{20,20}' if phase == 'ready' else
                    'HTML_CLIP PASS ' + phase + ' leaves no stale page pixels at card p{20,20}') if good else (
                    'HTML_CLIP FAIL ready page texture missing at card p{20,20}' if phase == 'ready' else
                    'HTML_CLIP FAIL ' + phase + ' retains page pixels at card p{20,20}')
        records.append({'phase': phase, 'good': good, 'exit': result.returncode,
                        'stdout': result.stdout, 'stderr': result.stderr})
        assert result.returncode == (0 if good else 1), records[-1]
        assert result.stdout.strip() == expected and not result.stderr, records[-1]
        print('HTML_CLIP_CONTROL PASS %s %s exits %s' % (phase, 'valid capture' if good else 'bad capture', result.returncode), flush=True)
with (folder / 'html-clip-controls.json').open('x') as output:
    json.dump(records, output, indent=2)
