"""Publish a same-path PNG and hold its test transport until the pending capture."""
import os
from pathlib import Path
import select
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

WAIT_SECONDS = 5
folder = Path(sys.argv[1])
assert folder.is_absolute() and (folder / '.flea-test-sandbox').is_file()
folder = folder.resolve(strict=True)
target = folder / 'reload.png'
blue = folder / 'reload-blue.png'
assert target.is_file() and not target.is_symlink()
assert blue.is_file() and not blue.is_symlink()
data = blue.read_bytes()
os.replace(blue, target)


# Sample input: b'publish\n' releases the image; b'wrong\n' is rejected.
def wait_for_publish():
    deadline = time.monotonic() + WAIT_SECONDS
    for expected in b'publish\n':
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([sys.stdin], [], [], remaining)[0]:
            raise TimeoutError('publish wait expired')
        if os.read(sys.stdin.fileno(), 1) != bytes([expected]):
            raise ValueError('bad or missing publish handshake')


class Picture(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.failure = 'request handler failed'
        print('reader', flush=True)
        try:
            wait_for_publish()
        except (TimeoutError, ValueError) as error:
            self.server.failure = str(error)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'image/png')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self.server.failure = ''

    def log_message(self, *args):
        pass


with HTTPServer(('127.0.0.1', 0), Picture) as server:
    server.timeout = WAIT_SECONDS
    server.failure = 'accept wait expired'
    print('armed ' + str(server.server_address[1]), flush=True)
    server.handle_request()
    if server.failure:
        print('HTML_RELOAD_WRITER FAIL ' + server.failure, flush=True)
        sys.exit(1)
