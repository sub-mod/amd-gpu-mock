"""Shared OpenShift-only demo helpers; operate only on the selected CRC cluster."""
import json
import subprocess
import time

MOCK_NS = 'amd-mock-crc-llm'
GPU = 'amd.com/gpu'


def oc(*args, capture=True, **kw):
    result = subprocess.run(['oc', *args], text=True, capture_output=capture, **kw)
    if result.returncode:
        raise RuntimeError(result.stderr or 'oc command failed')
    return result.stdout


def get(kind, name=None, namespace=None):
    return json.loads(oc('get', kind, *([name] if name else []),
                         *(['-n', namespace] if namespace else []), '-o', 'json'))


def guard():
    server = oc('config', 'view', '--minify', '-o', 'jsonpath={.clusters[0].cluster.server}')
    if 'api.crc.testing' not in server:
        raise RuntimeError('Select the CRC admin context; refusing another cluster')
    nodes = get('nodes')['items']
    if len(nodes) != 1 or not nodes[0]['status']['nodeInfo']['containerRuntimeVersion'].startswith('cri-o://'):
        raise RuntimeError('Requires a dedicated one-node OpenShift Local cluster')
    return nodes[0]


def apply(obj):
    print(oc('apply', '-f', '-', input=json.dumps(obj)).strip(), flush=True)


def namespace(name):
    apply({'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': name,
           'labels': {'amd-gpu-mock/openshift-demo': 'true'}}})


def wait(test, message, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if test():
            print('PASS: ' + message, flush=True)
            return
        time.sleep(2)
    raise RuntimeError(message)


def pod(ns, name, count=1, claim=None):
    resources = {'requests': {'cpu': '50m', 'memory': '32Mi'}, 'limits': {'memory': '128Mi'}}
    if claim:
        resources['claims'] = [{'name': 'gpu'}]
    else:
        resources['requests'][GPU] = count
        resources['limits'][GPU] = count
    code = "import glob,json,os,stat,time; paths=['/dev/kfd']+sorted(glob.glob('/dev/dri/renderD*')); "
    code += f"assert len(paths)=={count + 1}, paths; "
    code += "assert all(stat.S_ISCHR(os.stat(p).st_mode) for p in paths); "
    code += "print(json.dumps({'devices':paths,'uid':os.getuid()}),flush=True); time.sleep(86400)"
    spec = {'terminationGracePeriodSeconds': 1, 'restartPolicy': 'Never',
            'securityContext': {'runAsNonRoot': True, 'seccompProfile': {'type': 'RuntimeDefault'}},
            'containers': [{'name': 'consumer', 'image': 'docker.io/library/python:3.11-slim',
              'securityContext': {'allowPrivilegeEscalation': False, 'capabilities': {'drop': ['ALL']}},
              'command': ['python3', '-u', '-c', code], 'resources': resources}]}
    if claim:
        spec['resourceClaims'] = [{'name': 'gpu', 'resourceClaimName': claim}]
    apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name, 'namespace': ns,
           'annotations': {'openshift.io/required-scc': 'restricted-v2'}}, 'spec': spec})


def ready(ns, name):
    oc('-n', ns, 'wait', 'pod/' + name, '--for=condition=Ready', '--timeout=180s')


def evidence(ns, name, count):
    p = get('pod', name, ns)
    assert p['metadata']['annotations']['openshift.io/scc'] == 'restricted-v2'
    code = "import glob,json,os,stat; paths=['/dev/kfd']+sorted(glob.glob('/dev/dri/renderD*')); assert all(stat.S_ISCHR(os.stat(p).st_mode) for p in paths); print(json.dumps({'devices':paths,'uid':os.getuid()}))"
    result = json.loads(oc('-n', ns, 'exec', name, '--', 'python3', '-c', code))
    assert len(result['devices']) == count + 1
    assert result['uid'] != 0
    print(json.dumps({'pod': ns + '/' + name, 'node': p['spec']['nodeName'], 'scc': 'restricted-v2', **result}), flush=True)
    return set(result['devices']) - {'/dev/kfd'}


def delete(ns, name):
    oc('-n', ns, 'delete', 'pod', name, '--ignore-not-found', '--wait=true', '--timeout=120s')


def api(path, post=False):
    args = ['wget', '-qO-', *(['--post-data='] if post else []), 'http://127.0.0.1:8080' + path]
    return json.loads(oc('-n', MOCK_NS, 'exec', 'ds/amd-gpu-mock', '--', *args))
