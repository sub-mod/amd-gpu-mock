#!/usr/bin/env python3
"""Check the pinned upstream Spur image against the selected OpenShift node."""
from pathlib import Path
import json
import os
import sys
import urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard

if __name__ == '__main__':
    node = guard()
    pin=dict(line.split('=',1) for line in (Path(__file__).parent/'versions.env').read_text().splitlines() if line and not line.startswith('#'))
    reference=os.environ.get('SPUR_ARM64_IMAGE',pin['SPUR_ARM64_IMAGE']).removeprefix('docker.io/')
    repo,image=reference.split('@',1) if '@' in reference else reference.rsplit(':',1)
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
        print('BLOCKED: configured Spur image does not match CRC architecture.')
        sys.exit(2)
    print('PASS: published native Spur image architecture matches the OpenShift node.')
