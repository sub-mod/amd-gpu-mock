"""Scripted Tiny LLM response with real Kubernetes GPU-allocation evidence."""
import glob
import json
import os
import stat
from http.server import BaseHTTPRequestHandler, HTTPServer


def evidence():
    renders = glob.glob('/dev/dri/renderD*')
    assert len(renders) == 1, f'Expected exactly one allocated render device: {renders}'
    devices = {}
    for path in ['/dev/kfd'] + renders:
        info = os.stat(path)
        assert stat.S_ISCHR(info.st_mode), f'Not a character device: {path}'
        devices[path] = {'major': os.major(info.st_rdev), 'minor': os.minor(info.st_rdev)}
    return {'node': os.environ['NODE_NAME'], 'devices': devices, 'simulation': True}


class Handler(BaseHTTPRequestHandler):
    def reply(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(evidence())

    def do_POST(self):
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 < size <= 4096:
            self.send_error(400)
            return
        try:
            prompt = json.loads(self.rfile.read(size))['prompt']
            assert isinstance(prompt, str)
        except (ValueError, KeyError, AssertionError):
            self.send_error(400)
            return
        body = {'text': prompt + ' bright and full of possibilities', 'allocation': evidence()}
        print('SIMULATED_RESPONSE ' + json.dumps(body), flush=True)
        self.reply(body)


if __name__ == '__main__':
    print('DEVICE_EVIDENCE ' + json.dumps(evidence()), flush=True)
    print('AMD device plugin -> kubelet/CRI-O -> allocated mock character devices.', flush=True)
    print('Scripted response; no model weights or ROCm computation.', flush=True)
    HTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
