# HAMi: two Pods sharing one simulated MI300X

This integration lives on the `hami` branch. Check out that branch before
running these commands; it has not been merged into `main`.


Use this separate demo to show HAMi allocation on main's CUSE/libdrm mock.
The [guide](../../docs/guides/hami.md) contains the numbered architecture,
requirements, layer boundaries and limitations.

```bash
./demo/hami/setup.sh
python3 -u demo/hami/verify.py
python3 -u tests/hami/lifecycle.py
```

Setup starts the mock dashboard at `http://localhost:8081` and Grafana at
`http://localhost:3001` (`admin` / `amdmock`). `HAMI_DASHBOARD_PORT` and
`HAMI_GRAFANA_PORT` change these ports before cluster creation.
Published images are used; users do not build a backend. Requires Kind,
kubectl, Helm, Git, Python 3, Docker/Podman, and CUSE in the runtime Linux kernel.

The scripts print actual evidence: HAMi node inventory; each Pod's UID, assigned
GPU UUID, CU mask, configured memory limit and native device-open result;
third-Pod exhaustion and subsequent budget reuse; plugin restart and dashboard
fault/recovery propagation. They fail if their assertions do not hold. Two
consumers remain Running so you can inspect them:

```bash
kubectl --kubeconfig tmp/hami-main/kubeconfig -n amd-hami-demo get pods
kubectl --kubeconfig tmp/hami-main/kubeconfig -n amd-hami-demo logs right
```

Both remaining Pods share one physical GPU; they are not hardware partitions.
CU masks and configured limits do not prove real compute or memory isolation.
Neither DRA nor the ordinary AMD device plugin runs in this dedicated cluster.

## Captured validation

Validation logs and immutable image/source provenance are recorded here after
native AMD64/ARM64 CI and published-image setup complete. The test scripts print
their own live logs; no illustrative success output is substituted for results.

## Cleanup

```bash
./demo/hami/cleanup.sh
```

This removes only `amd-hami-main`. To repeat verification without rebuilding,
delete `amd-hami-demo` first. It never changes your default kubectl context.
