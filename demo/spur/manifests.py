#!/usr/bin/env python3
"""Demo deployment configuration for the unchanged Spur 0.14.0 image."""
import json
import os

NS = 'amd-demo-spur'
IMAGE = os.environ['SPUR_IMAGE']
objects = [
    {'apiVersion': 'v1', 'kind': 'ServiceAccount', 'metadata': {'name': 'spur-operator', 'namespace': NS}},
    {'apiVersion': 'rbac.authorization.k8s.io/v1', 'kind': 'ClusterRole',
     'metadata': {'name': 'amd-mock-spur-operator'}, 'rules': [
         {'apiGroups': [''], 'resources': ['nodes'], 'verbs': ['get', 'list', 'watch']},
         {'apiGroups': ['spur.amd.com'], 'resources': ['spurjobs', 'spurjobs/status', 'spurjobs/finalizers'],
          'verbs': ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']},
         {'apiGroups': [''], 'resources': ['pods', 'pods/status', 'pods/log', 'services', 'configmaps'],
          'verbs': ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']},
         {'apiGroups': [''], 'resources': ['events'], 'verbs': ['create', 'patch']},
         {'apiGroups': ['policy'], 'resources': ['poddisruptionbudgets'],
          'verbs': ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']}]},
    {'apiVersion': 'rbac.authorization.k8s.io/v1', 'kind': 'ClusterRoleBinding',
     'metadata': {'name': 'amd-mock-spur-operator'},
     'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': 'amd-mock-spur-operator'},
     'subjects': [{'kind': 'ServiceAccount', 'name': 'spur-operator', 'namespace': NS}]},
]
for name, ports in [('spurctld', [6817]), ('spur-k8s-operator', [6818, 8080])]:
    objects.append({'apiVersion': 'v1', 'kind': 'Service', 'metadata': {'name': name, 'namespace': NS},
                    'spec': {'selector': {'app': name}, 'ports': [
                        {'name': 'p' + str(port), 'port': port, 'targetPort': port} for port in ports]}})
    controller = name == 'spurctld'
    container = {'name': name, 'image': IMAGE, 'command': [name],
                 'args': ['-D', '--config=/etc/spur/spur.conf', '--state-dir=/var/spool/spur', '--listen=0.0.0.0:6817'] if controller else [
                     '--controller-addr=http://spurctld:6817', '--listen=0.0.0.0:6818',
                     '--health-addr=0.0.0.0:8080', '--address=spur-k8s-operator.' + NS + '.svc.cluster.local',
                     '--node-selector=spur.amd.com/managed=true', '--auth-mode=required'],
                 'resources': {'requests': {'cpu': '100m', 'memory': '128Mi'}, 'limits': {'memory': '512Mi'}},
                 'readinessProbe': {'tcpSocket': {'port': ports[0]}, 'initialDelaySeconds': 3, 'periodSeconds': 5}}
    spec = {'containers': [container], 'securityContext': {'fsGroup': 1001},
            'tolerations': [{'operator': 'Exists'}]}
    if controller:
        container['volumeMounts'] = [{'name': 'config', 'mountPath': '/etc/spur', 'readOnly': True},
                                    {'name': 'spool', 'mountPath': '/var/spool/spur'},
                                    {'name': 'auth', 'mountPath': '/etc/spur-auth', 'readOnly': True}]
        spec['volumes'] = [{'name': 'config', 'configMap': {'name': 'spur-config'}},
                           {'name': 'spool', 'emptyDir': {}},
                           {'name': 'auth', 'secret': {'secretName': 'spur-auth'}}]
    else:
        spec['serviceAccountName'] = 'spur-operator'
        container['env'] = [{'name': 'SPUR_JWT_KEY', 'valueFrom': {
            'secretKeyRef': {'name': 'spur-auth', 'key': 'jwt-key'}}}]
    objects.append({'apiVersion': 'apps/v1', 'kind': 'Deployment',
                    'metadata': {'name': name, 'namespace': NS},
                    'spec': {'replicas': 1, 'selector': {'matchLabels': {'app': name}},
                             'template': {'metadata': {'labels': {'app': name}}, 'spec': spec}}})
print(json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': objects}))
