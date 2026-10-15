#!/usr/bin/env python3
"""Check the pinned upstream Spur image against the selected OpenShift node."""
from pathlib import Path
import json
import sys
import urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard

if __name__ == '__main__':
    node = guard()
    repo = 'rocm/spur'
    image = 'sha256:f42a234b6b93650a9ca0e76ae2ff124585a07bccb5b7ee2f4706a42aedd2846b'
    token = json.load(urllib.request.urlopen('https://auth.docker.io/token?service=registry.docker.io&scope=repository:'+repo+':pull'))['token']
    def fetch(path):
        request = urllib.request.Request('https://registry-1.docker.io/v2/'+repo+'/'+path,
            headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.oci.image.manifest.v1+json'})
        return json.load(urllib.request.urlopen(request))
    manifest = fetch('manifests/'+image)
    config = fetch('blobs/'+manifest['config']['digest'])
    arch = node['status']['nodeInfo']['architecture']
    print(json.dumps({'image':repo+'@'+image,'image_architecture':config['architecture'], 'node_architecture':arch},indent=2))
    if arch != config['architecture']:
        print('BLOCKED: pinned upstream Spur image does not match CRC architecture. Need an upstream ARM64 image or separately published and validated ARM64 build.')
        sys.exit(2)
    print('Architecture preflight passed; Spur installation on OpenShift is not yet validated.')
