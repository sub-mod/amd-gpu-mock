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

[Native AMD64/ARM64 CI](https://github.com/sub-mod/amd-gpu-mock/actions/runs/39371568059)
passed both jobs. The [fresh public-image run](https://github.com/sub-mod/amd-gpu-mock/actions/runs/39372296888)
also passed both architectures, without builds. The logs below are actual
artifacts from that public-image run on `hami`.

| Check | AMD64 | ARM64 |
| --- | --- | --- |
| Sharing, native opens, library provenance, exhaustion/reuse | [Actual log](logs/amd64-allocation.log) | [Actual log](logs/arm64-allocation.log) |
| Plugin restart and dashboard crash/recovery | [Actual log](logs/amd64-lifecycle.log) | [Actual log](logs/arm64-lifecycle.log) |
| Real agent restart | [Actual log](logs/amd64-agent-restart.log) | [Actual log](logs/arm64-agent-restart.log) |
| Grafana and real exporter | [Actual log](logs/amd64-grafana.log) | [Actual log](logs/arm64-grafana.log) |

Excerpt from the captured lifecycle output:

```text
PASS: plugin restart restores four share slots
PASS: both existing consumer Pod identities survive plugin replacement
PASS: simulated fatal state -> libdrm initialization failure -> real HAMi ListAndWatch -> kubelet allocatable=0
PASS: recovery restores kubelet share-slot advertisement
```

[Published image provenance](../../deployments/hami/published-images.json) records
source pins and anonymously verified image digests. Public-only setup passed
both architectures; the live scripts always print their own logs.

## Cleanup

```bash
./demo/hami/cleanup.sh
```

This removes only `amd-hami-main`. To repeat verification without rebuilding,
delete `amd-hami-demo` first. It never changes your default kubectl context.
