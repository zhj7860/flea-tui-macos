"""Drive the page request through the real backend and inspect the PNG pixels."""
import json
import pathlib
import os
import re
import shutil
import select
import subprocess
import sys
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading
import urllib.request

binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
process = subprocess.Popen([binary, '--backend'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
failures = []

class Listener(BaseHTTPRequestHandler):
    requests = 0
    def do_GET(self):
        Listener.requests += 1
        data = (root / 'remote.png').read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', 'image/png')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

# Sample input: LISTENER_PORT = 0, the fixture placeholder and ephemeral listener bind.
LISTENER_PORT = int(re.search(r'^LISTENER_PORT = (\d+)$', (pathlib.Path(__file__).with_name('html-fixture.py')).read_text(), re.M).group(1))

listener = HTTPServer(('127.0.0.1', LISTENER_PORT), Listener)
port = listener.server_address[1]
fixture_index = root / 'fixture/index.html'
placeholder = 'http://127.0.0.1:%d/remote.png' % LISTENER_PORT
assert placeholder in fixture_index.read_text(), 'html-fixture remote URL must use LISTENER_PORT'
fixture_index.write_text(fixture_index.read_text().replace(placeholder, 'http://127.0.0.1:%d/remote.png' % port))
threading.Thread(target=listener.serve_forever, daemon=True).start()

def check(name, got, want=True):
    good = got == want
    print(('PASS' if good else 'FAIL') + ' html-engine: ' + name, flush=True)
    if not good:
        failures.append((name, got, want))

class ReplyLines:
    def __init__(self, pipe):
        self.fd = pipe.fileno()
        os.set_blocking(self.fd, False)
        self.pending = b''
        self.eof = False

    def readline(self, timeout=0):
        end = time.monotonic() + timeout
        while True:
            if b'\n' in self.pending:
                line, self.pending = self.pending.split(b'\n', 1)
                return line
            if self.eof:
                line, self.pending = self.pending, b''
                return line or None
            if not select.select([self.fd], [], [], max(0, end - time.monotonic()))[0]:
                return None
            try:
                chunk = os.read(self.fd, 65536)
            except BlockingIOError:
                continue
            if not chunk:
                self.eof = True
            self.pending += chunk
            if b'\n' not in self.pending and time.monotonic() >= end:
                return None

replies = ReplyLines(process.stdout)

def ask(token, width, path=None, height=None):
    # A line already waiting belongs to an earlier request, so it is never credited to this one.
    while replies.readline() is not None:
        pass
    payload = {'c': 'html', 'slot': 'test', 'token': token, 'path': str(path or root / 'fixture/index.html'), 'width': width}
    if height is not None:
        payload['height'] = height
    process.stdin.write((json.dumps(payload) + '\n').encode())
    process.stdin.flush()
    end = time.monotonic() + 25
    while time.monotonic() < end:
        line = replies.readline(min(1, max(0, end - time.monotonic())))
        if line is None:
            if replies.eof:
                break
            continue
        # Sample input: {"t":"html","slot":"test","token":1,"state":"ready","file":"/cache/x.png","total":61,"width":984,"title":"Static HTML"}.
        reply = json.loads(line)
        # Generic errors carry no token (proto::error_line); discard them and require this request's HTML reply.
        if reply.get('t') == 'error':
            continue
        if reply.get('t') == 'html' and reply.get('token') == token:
            return reply
    return {'state': 'timeout'}

try:
    check('listener requests a kernel-assigned port', LISTENER_PORT, 0)
    real_process, real_replies = process, replies
    for mode in ['chunk', 'error-only', 'partial', 'buffered-stale']:
        stub = r"""import json,os,sys
mode=sys.argv[1]
if mode == 'partial':
    os.write(1,b'{"t":"error"')
    print('partial ready', file=sys.stderr, flush=True)
request=json.loads(sys.stdin.buffer.readline())
stale=b',"message":"partial"}\n' if mode == 'partial' else b'{"t":"error","message":"stale"}\n'
reply=json.dumps({"t":"html","token":request["token"],"state":"ready"}).encode()+b'\n'
extra=json.dumps({'t':'html','token':402,'state':'failed'}).encode()+b'\n' if mode == 'buffered-stale' else b''
os.write(1,stale+(reply if mode != 'error-only' else b'')+extra)
if mode != 'error-only':
    request=sys.stdin.buffer.readline()
    if mode == 'buffered-stale':
        request=json.loads(request)
        os.write(1,json.dumps({'t':'html','token':request['token'],'state':'ready'}).encode()+b'\n')
        sys.stdin.buffer.readline()
"""
        probe = subprocess.Popen([sys.executable, '-u', '-c', stub, mode],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        try:
            if mode == 'partial':
                assert probe.stderr.readline() == b'partial ready\n'
            process, replies = probe, ReplyLines(probe.stdout)
            reply = ask(401, 300)
            check('unbuffered reply drain (%s)' % mode, reply.get('state'), 'timeout' if mode == 'error-only' else 'ready')
            if mode == 'buffered-stale':
                check('buffered stale reply is drained before the next request', ask(402, 300).get('state'), 'ready')
        finally:
            probe.stdin.close()
            probe.wait(timeout=5)
            process, replies = real_process, real_replies
    control = urllib.request.urlopen('http://127.0.0.1:%d/remote.png' % port, timeout=2).read()
    check('remote marker listener is reachable outside the jail', control.startswith(b'\x89PNG\r\n\x1a\n'))
    control_requests = Listener.requests
    previous = None
    for token, width in [(1, 984), (2, 300), (3, 984)]:
        reply = ask(token, width)
        check('page rendered at %d pixels' % width, reply.get('state'), 'ready')
        if reply.get('state') != 'ready':
            print('FAIL html-engine: reply ' + json.dumps(reply), flush=True)
            break
        check('whole-file count is 61', reply.get('total'), 61)
        if token != 3:
            check('script marker never set', reply.get('title'), 'Static HTML')
        image = pathlib.Path(reply['file'])
        evidence = os.environ.get('FLEA_CI_SUITE_LOGS')
        if evidence:
            shutil.copyfile(image, pathlib.Path(evidence) / ('html-engine-%d.png' % width))
        # Sample input: magick identify -format '%w %h' answers "984 2134".
        dimensions = subprocess.check_output(['magick', 'identify', '-format', '%w %h', str(image)], text=True).split()
        check('PNG width matches request', int(dimensions[0]), width)
        check('PNG contains the tall page', 1800 <= int(dimensions[1]) <= 8000)
        pixels = subprocess.check_output(['magick', str(image), '-alpha', 'off', '-depth', '8', 'rgb:-'])
        colors = Counter(zip(pixels[::3], pixels[1::3], pixels[2::3]))
        check('sibling image loaded with all 1024 pixels', colors[(0x12, 0xab, 0x34)] >= 1024)
        check('outside file and symlink not loaded', colors[(0x34, 0x12, 0xab)], 0)
        check('remote/script image color absent', colors[(0xab, 0x12, 0x34)], 0)
        if token == 1:
            dependencies = json.loads(image.with_suffix('.deps').read_text())
            check('P1 real helper resources are non-null', isinstance(dependencies, dict))
            print('EVIDENCE P1 dependencies=' + json.dumps(dependencies), flush=True)
            previous = (str(image), image.stat().st_mtime_ns)
        if token == 3:
            check('revisit reused PNG without rewriting it', (str(image), image.stat().st_mtime_ns), previous)
            print('EVIDENCE P1 second same-width request cache_hit=' + str((str(image), image.stat().st_mtime_ns) == previous), flush=True)
    def rendered_colors(token, page):
        reply = ask(token, 300, page)
        check(page.name + ' rendered', reply.get('state'), 'ready')
        if reply.get('state') != 'ready':
            return Counter(), None
        image = pathlib.Path(reply['file'])
        pixels = subprocess.check_output(['magick', str(image), '-alpha', 'off', '-depth', '8', 'rgb:-'])
        return Counter(zip(pixels[::3], pixels[1::3], pixels[2::3])), image

    fixture = root / 'fixture'
    standards_body = '<style>body{margin:0}table{border-collapse:collapse}td{padding:0;background:#23bc45;font:16px sans-serif;line-height:20px}</style><table><tr><td><img src="local.png"></td></tr></table>'
    quirks = fixture / 'quirks.html'
    quirks.write_text(standards_body)
    colors, _ = rendered_colors(10, quirks)
    check('quirks control loads the inline image', colors[(0x12, 0xab, 0x34)], 1024)
    check('quirks control omits the inline image baseline gap', colors[(0x23, 0xbc, 0x45)], 0)
    for token, prefix in [(11, '<!-- leading comment -->'), (12, '\ufeff \n<!-- one --><!-- two -->\n')]:
        page = fixture / ('standards-%d.html' % token)
        page.write_text(prefix + '<!doctype html>' + standards_body)
        colors, _ = rendered_colors(token, page)
        check('standards fixture loads the inline image %d' % token, colors[(0x12, 0xab, 0x34)], 1024)
        check('F1 comment/BOM preserves standards inline image gap %d' % token, colors[(0x23, 0xbc, 0x45)] > 0)

    sub = fixture / 'sub'
    sub.mkdir()
    (sub / 'style.css').write_text('body{margin:0;background:#45bc23}')
    page = fixture / 'own base #?.html'
    page.write_text('<!doctype html><base href="sub/"><link rel="stylesheet" href="style.css"><div>base</div>')
    colors, _ = rendered_colors(13, page)
    check('F3 document base loads sub/style.css', colors[(0x45, 0xbc, 0x23)] > 10000)

    style = fixture / 'edit.css'
    style.write_text('body{margin:0;background:#45bc23}')
    page = fixture / 'resources.html'
    page.write_text('<!doctype html><link rel="stylesheet" href="edit.css"><div>resource</div>')
    colors, first_image = rendered_colors(14, page)
    check('F4 initial stylesheet loaded', colors[(0x45, 0xbc, 0x23)] > 10000)
    style.write_text('body{margin:0;background:#bc4523}')
    colors, second_image = rendered_colors(15, page)
    check('F4 edited stylesheet changes the next render', colors[(0xbc, 0x45, 0x23)] > 10000)
    check('F4 old stylesheet pixels are absent', colors[(0x45, 0xbc, 0x23)], 0)
    if first_image is not None and second_image is not None:
        check('P2 the re-render reuses the cache path', str(second_image), str(first_image))
        print('EVIDENCE P2 same_path=' + str(second_image == first_image) + ' path=' + str(second_image), flush=True)
    if second_image:
        record = json.loads(second_image.with_suffix('.deps').read_text()) if second_image.with_suffix('.deps').exists() else None
        check('F4 engine-recorded stylesheet dependency', isinstance(record, dict) and any(row[0] == 'edit.css' for row in record.get('dependencies', [])))
    imported = fixture / 'imported.css'
    imported.write_text('body{margin:0}img{display:block}')
    (fixture / 'parent.css').write_text('@import "imported.css";')
    picture = fixture / 'edited.png'
    subprocess.check_call(['magick', '-size', '32x32', 'xc:#23bc45', str(picture)])
    page = fixture / 'nested-resources.html'
    page.write_text('<!doctype html><link rel="stylesheet" href="parent.css"><img src="edited.png">')
    colors, image = rendered_colors(16, page)
    check('F4 image initially loaded', colors[(0x23, 0xbc, 0x45)], 1024)
    if image:
        record = json.loads(image.with_suffix('.deps').read_text()) if image.with_suffix('.deps').exists() else None
        paths = {row[0] for row in record.get('dependencies', [])} if isinstance(record, dict) else set()
        check('F4 engine records imported CSS and image', {'parent.css', 'imported.css', 'edited.png'} <= paths)
    subprocess.check_call(['magick', '-size', '32x32', 'xc:#bc4523', str(picture)])
    colors, image = rendered_colors(17, page)
    check('F4 edited image changes the next render', colors[(0xbc, 0x45, 0x23)], 1024)
    if image and image.with_suffix('.deps').exists():
        previous_stamp = image.stat().st_mtime_ns
        image.with_suffix('.deps').write_text('invalid')
        colors, refreshed = rendered_colors(18, page)
        check('F4 malformed dependency record forces rerender', refreshed is not None and refreshed.stat().st_mtime_ns != previous_stamp)
    late_style = fixture / 'late.css'
    page = fixture / 'late-style.html'
    page.write_text('<!doctype html><link rel="stylesheet" href="late.css"><div>late</div>')
    colors, first_late = rendered_colors(30, page)
    check('F9 unstyled page renders without its missing sheet', first_late is not None, True)
    first_stamp = first_late.stat().st_mtime_ns if first_late else None
    if first_late:
        record = json.loads(first_late.with_suffix('.deps').read_text())
        check('F9 engine records the missing sheet as absent', isinstance(record, dict) and ['late.css', 'absent'] in record.get('dependencies', []))
    _, still_missing = rendered_colors(32, page)
    check('F9 unchanged missing sheet hits the cached PNG', still_missing is not None and still_missing.stat().st_mtime_ns == first_stamp)
    late_style.write_text('body{margin:0;background:#45bc23}')
    colors, second_late = rendered_colors(31, page)
    check('F9 created sheet changes the next render', colors[(0x45, 0xbc, 0x23)] > 10000)
    if second_late is not None:
        check('F9 created sheet misses the cached PNG', second_late.stat().st_mtime_ns != first_stamp, True)
    try:
        font_source = next(path for path in pathlib.Path('/usr/share/fonts').rglob('*') if path.suffix.lower() in {'.ttf', '.otf'} and path.is_file())
    except StopIteration:
        font_source = None
    if font_source is None:
        check('a local .ttf/.otf font exists under /usr/share/fonts', 'none found', 'a font file')
    else:
        font = fixture / ('cached-font' + font_source.suffix)
        shutil.copyfile(font_source, font)
        page = fixture / 'font.html'
        page.write_text('<!doctype html><style>@font-face{font-family:fixture;src:url("' + font.name + '")}body{font-family:fixture}</style><div>Local font resource</div>')
        _, image = rendered_colors(19, page)
        if image:
            record = json.loads(image.with_suffix('.deps').read_text()) if image.with_suffix('.deps').exists() else None
            check('F4 engine records the loaded local font', isinstance(record, dict) and any(row[0] == font.name for row in record.get('dependencies', [])))
            previous_stamp = image.stat().st_mtime_ns
            font_stamp = font.stat()
            os.utime(font, ns=(font_stamp.st_atime_ns, font_stamp.st_mtime_ns + 1))
            _, refreshed = rendered_colors(20, page)
            check('F4 font nanosecond edit forces rerender', refreshed is not None and refreshed.stat().st_mtime_ns != previous_stamp)
    short = fixture / 'short.html'
    short.write_text('<!doctype html><style>body{margin:0;background:white}</style><p>Short page</p>')
    short_images = []
    for token, height in [(21, 625), (22, 900)]:
        reply = ask(token, 300, short, height)
        check('F9 short page renders for viewport %d' % height, reply.get('state'), 'ready')
        if reply.get('state') == 'ready':
            image = pathlib.Path(reply['file'])
            # Sample input: magick identify -format '%h' answers "625".
            actual_height = int(subprocess.check_output(['magick', 'identify', '-format', '%h', str(image)], text=True))
            check('F9 page fills requested viewport %d' % height, actual_height >= height)
            short_images.append(reply['file'])
    check('F9 cache key includes viewport height', len(short_images) == 2 and short_images[0] != short_images[1])
    failed = ask(4, 300, root / 'fixture/missing.html')
    check('unreadable page answers failed', failed.get('state'), 'failed')
    check('preview never connects to the reachable remote marker', Listener.requests, control_requests)
finally:
    listener.shutdown()
    listener.server_close()
    process.stdin.close()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
if failures:
    for failure in failures:
        print('FAIL detail: %r' % (failure,), flush=True)
    sys.exit(1)
