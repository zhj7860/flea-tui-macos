"""Create the preview specimen only when the suite requests it."""
import pathlib
import sys

# The remote-marker listener's port, shared with html-engine.py: the jail must never reach it.
LISTENER_PORT = 0

folder = pathlib.Path(sys.argv[1])
lines = [
    '<!doctype html>', '<html><head><meta charset="utf-8">',
    '<title>Static HTML</title>',
    '<style>body{margin:0;background:white;color:#333;font:13px sans-serif}',
    'nav{display:flex;gap:16px;padding:10px 18px;border-bottom:1px solid #ddd}',
    'h1{font-size:18px;color:#111;margin:16px 22px 12px}',
    'p{margin:0 22px 12px;line-height:1.7}.note{margin:12px 22px;padding:12px;border:1px solid #ddd}',
    'img{width:32px;height:32px}section{height:1800px}</style>',
    '<script>document.title="SCRIPT-RAN";document.body.style.background="#ab1234"</script>',
    '</head><body>', '<nav><b>Ridgeline</b><span>Huts</span><span>Weather</span></nav>',
    '<h1>Walking the col</h1>',
    '<p>The ridgeline trail leaves the car park at first light and climbs through pine forest for an hour.</p>',
    '<img src="local.png"><img src="http://127.0.0.1:%d/remote.png">' % LISTENER_PORT,
    '<img src="../outside.png"><img src="escape.png">',
    '<div class="note">Carry a map. The waymarks are red and white paint on rock cairns.</div>',
    '<section></section>', '</body></html>',
]
lines[17:17] = ['<!-- source line %d -->' % n for n in range(43)]
assert len(lines) == 61
(folder / 'index.html').write_text('\n'.join(lines) + '\n')
(folder / 'notes.md').write_text('# Notes\n\nMarkdown keeps its own view.\n')
long_lines = ['<!doctype html><html><body>'] + ['<p data-line="%d">%s</p>' % (n, 'The col stays visible while Source wraps. ' * 8) for n in range(1, 799)] + ['</body></html>']
assert len(long_lines) == 800
(folder / 'long.html').write_text('\n'.join(long_lines) + '\n')
