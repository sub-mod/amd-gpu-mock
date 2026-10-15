#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, namespace, pod, ready, evidence

if __name__ == '__main__':
    guard()
    ns = 'amd-crc-multi-gpu'
    namespace(ns)
    selected = []
    for name, count in [('two-gpus', 2), ('single-a', 1), ('single-b', 1)]:
        pod(ns, name, count)
        ready(ns, name)
        selected.append(evidence(ns, name, count))
    assert not any(a & b for i, a in enumerate(selected) for b in selected[i+1:])
    print('PASS: one Pod receives two GPUs; concurrent Pods receive distinct GPUs under restricted-v2')
