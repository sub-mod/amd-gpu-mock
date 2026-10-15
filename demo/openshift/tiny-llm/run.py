#!/usr/bin/env python3
"""Install and verify the isolated CRC Tiny LLM demo using published images."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import yaml

HERE = Path(__file__).resolve().parent
NS = 'amd-mock-crc-llm'
RELEASE = 'amd-gpu-mock'


def run(args, **kw):
    return subprocess.run(args, check=True, text=True, **kw)


def oc(*args, **kw):
    return run(['oc', *args], **kw)


def apply(docs):
    oc('apply', '-f', '-', input=yaml.safe_dump_all(docs))


def render():
    chart = run(['helm', 'template', RELEASE, 'oci://docker.io/submod/amd-gpu-mock',
                 '--version', '0.2.13', '-n', NS, '-f', str(HERE / 'values.yaml')],
                capture_output=True).stdout
    docs = [d for d in yaml.safe_load_all(chart) if d]
    for d in docs:
        d['metadata']['namespace'] = NS
        if d['kind'] == 'DaemonSet':
            d['spec']['template']['spec']['serviceAccountName'] = 'mock-node'
            d['spec']['template']['spec'].pop('priorityClassName', None)
            if d['metadata']['name'].endswith('-device-plugin'):
                # CRI-O needs normal /dev entries; GPU files are already staged
                # in host /dev by the mock agent. Only sysfs discovery is synthetic.
                for volume in d['spec']['template']['spec']['volumes']:
                    if volume['name'] == 'dev':
                        volume['hostPath']['path'] = '/dev'
    names = {d['metadata']['name'] for d in docs if d['kind'] == 'DaemonSet'}
    if names != {RELEASE, RELEASE + '-device-plugin'}:
        raise RuntimeError(f'Unexpected daemonsets: {names}')
    docs.extend([
        {'apiVersion': 'v1', 'kind': 'ServiceAccount', 'metadata': {'name': 'mock-node', 'namespace': NS}},
        {'apiVersion': 'rbac.authorization.k8s.io/v1', 'kind': 'Role',
         'metadata': {'name': 'mock-privileged-scc', 'namespace': NS},
         'rules': [{'apiGroups': ['security.openshift.io'], 'resources': ['securitycontextconstraints'],
                    'resourceNames': ['privileged'], 'verbs': ['use']}]},
        {'apiVersion': 'rbac.authorization.k8s.io/v1', 'kind': 'RoleBinding',
         'metadata': {'name': 'mock-privileged-scc', 'namespace': NS},
         'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Role', 'name': 'mock-privileged-scc'},
         'subjects': [{'kind': 'ServiceAccount', 'name': 'mock-node', 'namespace': NS}]},
    ])
    return docs


def node():
    nodes = json.loads(oc('get', 'nodes', '-o', 'json', capture_output=True).stdout)['items']
    if len(nodes) != 1:
        raise RuntimeError('Requires a dedicated single-node CRC cluster')
    n = nodes[0]
    if not n['status']['nodeInfo']['containerRuntimeVersion'].startswith('cri-o://'):
        raise RuntimeError('Requires OpenShift CRI-O')
    return n


def install():
    # Require CRC's endpoint explicitly to avoid altering a different cluster.
    server = oc('config', 'view', '--minify', '-o', 'jsonpath={.clusters[0].cluster.server}',
                capture_output=True).stdout
    if 'api.crc.testing' not in server:
        raise RuntimeError('Select the CRC admin context before running this demo')
    if oc('-n', NS, 'get', 'ds', RELEASE + '-dra-kubeletplugin', '--ignore-not-found', '-o', 'name', capture_output=True).stdout.strip():
        raise RuntimeError('DRA is active; run demo/openshift/restore-device-plugin.py before device-plugin installation')
    oc('get', 'clusterversion', 'version')
    n = node()
    if int(n['status'].get('capacity', {}).get('amd.com/gpu', 0)):
        existing = oc('-n', NS, 'get', 'ds', RELEASE, '--ignore-not-found', '-o', 'name', capture_output=True).stdout
        if not existing.strip():
            raise RuntimeError('Existing GPU capacity belongs to another installation')
    if not any(c['type'] == 'Ready' and c['status'] == 'True' for c in n['status']['conditions']):
        raise RuntimeError('CRC node is not Ready')
    apply([{'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': NS,
            'labels': {'pod-security.kubernetes.io/enforce': 'privileged'}}}])
    docs = render()
    plugin = next(d for d in docs if d['kind'] == 'DaemonSet' and d['metadata']['name'].endswith('-device-plugin'))
    apply([d for d in docs if d['kind'] != 'DaemonSet'])
    apply([d for d in docs if d['kind'] == 'DaemonSet' and d is not plugin])
    oc('-n', NS, 'rollout', 'status', 'ds/' + RELEASE, '--timeout=600s')
    apply([plugin])
    oc('-n', NS, 'rollout', 'status', 'ds/' + RELEASE + '-device-plugin', '--timeout=600s')
    deadline = time.monotonic() + 180
    while int(node()['status'].get('allocatable', {}).get('amd.com/gpu', 0)) != 8:
        if time.monotonic() > deadline:
            raise RuntimeError('Expected eight mock GPUs in allocatable')
        time.sleep(3)
    pod = {'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': 'tiny-llm', 'namespace': NS,
                     'annotations': {'openshift.io/required-scc': 'restricted-v2'}},
           'spec': {'securityContext': {'runAsNonRoot': True, 'seccompProfile': {'type': 'RuntimeDefault'}},
                    'containers': [{'securityContext': {'allowPrivilegeEscalation': False,
                                                       'capabilities': {'drop': ['ALL']}}, 'name': 'app', 'image': 'docker.io/library/python:3.11-slim',
              'command': ['python3', '-u', '-c', (HERE / 'app.py').read_text()],
              'env': [{'name': 'NODE_NAME', 'valueFrom': {'fieldRef': {'fieldPath': 'spec.nodeName'}}}],
              'resources': {'limits': {'amd.com/gpu': 1, 'memory': '256Mi'},
                            'requests': {'amd.com/gpu': 1, 'cpu': '100m', 'memory': '64Mi'}},
              'ports': [{'containerPort': 8000}],
              'readinessProbe': {'httpGet': {'path': '/healthz', 'port': 8000}}}]}}
    apply([pod])
    oc('-n', NS, 'wait', '--for=condition=Ready', 'pod/tiny-llm', '--timeout=600s')
    verify()


def verify():
    pod = json.loads(oc('-n', NS, 'get', 'pod', 'tiny-llm', '-o', 'json', capture_output=True).stdout)
    assert pod['spec']['containers'][0]['resources']['limits']['amd.com/gpu'] == '1'
    assert pod['spec']['nodeName'] == node()['metadata']['name']
    assert pod['metadata']['annotations']['openshift.io/scc'] == 'restricted-v2'
    print('APPLICATION_SCC restricted-v2')
    script = "import urllib.request; print(urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8000/generate', data=b'{\"prompt\":\"The future of AI is\"}', headers={'Content-Type':'application/json'})).read().decode())"
    body = json.loads(oc('-n', NS, 'exec', 'tiny-llm', '--', 'python3', '-c', script,
                         capture_output=True).stdout)
    assert body['allocation']['simulation'] is True
    assert body['text'] == 'The future of AI is bright and full of possibilities'
    print(json.dumps(body, indent=2))
    oc('-n', NS, 'logs', 'tiny-llm')
    print('PASS: OpenShift scheduler -> AMD device plugin -> CRI-O device injection -> scripted Tiny LLM response')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['render', 'install', 'verify', 'cleanup'])
    action = parser.parse_args().action
    if action == 'render':
        print(yaml.safe_dump_all(render()))
    elif action == 'install':
        install()
    elif action == 'verify':
        verify()
    else:
        oc('delete', 'namespace', NS, '--ignore-not-found')
        print('Namespace removed. Mock host device files remain; use crc delete for a complete VM reset.')
