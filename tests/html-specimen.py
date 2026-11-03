"""Write the binding board's HTML specimen on demand, with 61 lines and 1.6 kB."""
from pathlib import Path
import sys

folder = Path(sys.argv[1])
folder.mkdir(parents=True, exist_ok=True)
paragraphs = [
    'The ridgeline trail leaves the car park at first light and climbs through pine forest for an hour.',
    'Water runs beside the path after rain; the crossing has stepping stones and a handrail.',
    'The hut at the col serves soup from noon and keeps a drying room for wet gear.',
    'Descend by the scree path when the cloud drops, and allow two hours for the return leg.',
    'The bus back to town leaves the trailhead at half past four in winter.',
    'The col itself is broad and grassy, with a stone shelter on its eastern lip.',
    'From the shelter the summit path is marked but steep, and loose after a frost.',
    'In bad weather most walkers turn back at the col; the view from the shelter is enough.',
    'Dogs are welcome on the trail, on a lead near the sheep that graze below the hut.',
    'Check the forecast the night before, since the col gets wind the valley never feels.',
]
lines = [
    '<!doctype html>', '<html><head><title>Ridgeline</title><style>',
    'body{margin:0;background:white;color:#333;font:13px sans-serif}',
    'nav{display:flex;gap:16px;padding:10px 18px;border-bottom:1px solid #ddd;font-size:12px}',
    'h1{margin:16px 22px 12px;font-size:18px;color:#111}',
    'p{margin:0 22px 12px;line-height:1.7}',
    'aside{margin:12px 22px;padding:12px;border:1px solid #ddd}',
    '</style></head><body>', '<nav><b>Ridgeline</b><span>Huts</span><span>Weather</span></nav>',
    '<h1>Walking the col</h1>',
] + ['<p>' + text + '</p>' for text in paragraphs] + [
    '<aside>Carry a map. The waymarks are red and white paint on rock cairns.</aside>', '</body></html>',
]
lines[-1:-1] = [''] * (61 - len(lines))
text = '\n'.join(lines) + '\n'
padding = 1600 - len(text.encode())
assert padding >= 7
lines[-2] = '<!--' + ' Local HTML preview specimen. '.ljust(padding - 7) + '-->'
text = '\n'.join(lines) + '\n'
assert len(lines) == 61
assert 1550 <= len(text.encode()) < 1650, len(text.encode())
(folder / 'index.html').write_text(text)
