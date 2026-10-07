# Recorded demo runs

These are actual captured outputs from the 2026-10-06 session on the default
ARM64 Podman VM, Kubernetes v1.37.0 and published chart 0.2.9. They are retained
presentation evidence, not expected-output fixtures or live cluster readings.
Some captures precede the newer explanatory runner output; no explanatory
`PASS` lines were inserted into those older logs. Dynamic readings and names
vary on subsequent runs.

All eight demos already had successful captures, so this update reused them
without changing the live workloads or injecting new faults.

- [Complete DRA presenter suite](dra-suite.log)
- [Complete device-plugin presenter suite](device-plugin-suite.log)

The suites clean demo pods at the end; individual demo commands leave them
running. The complete logs include the cleanup operations. Fault and partition
logs below are contiguous command sections extracted from successful captures;
the partition log combines the CPX section with the recorded DPX/QPX/SPX run.

| Demo log | Original local capture in `.dra-test/` | SHA-256 of retained log |
| --- | --- | --- |
| [llm](../llm/captured.log) | `demo-explanatory-llm.log` | `44272a73c6ed3bb440aca75b2a3c18c3a2f17030d463c34d11772aa21ae230cc` |
| [dra](../dra/captured.log) | `demo-explanatory-dra.log` | `6a68df135a57598bc4c77ea23be5f5fa3b7be03af0d02057e402d2223e0855dd` |
| [multi-gpu](../multi-gpu/captured.log) | `demos-visible-multi.log` | `bd7a178a79907cc7b748401ea40cfa3d63966d583b5ac79ca1cb45130eb97577` |
| [allocation](../allocation/captured.log) | `demos-visible-allocation.log` | `9f6249d11c8e560a93b23a50d6ae0c5b4d20df3f1cfd9f7b4ac6746a4b6adb36` |
| [profiles](../profiles/captured.log) | `demo-explanatory-profiles.log` | `05c86e9507070bab872b83680185749ee52b35439dd7d0ffea0598f1b68d3bcf` |
| [telemetry](../telemetry/captured.log) | `demo-explanatory-telemetry.log` | `e0e63e221d84ed775787e97cd3e868e27621925ba8fe964c4b3031da8dca4daa` |
| [faults](../faults/captured.log) | `demos-current-dra.log (fault sequence)` | `9e62938ccd84d1cf1d324e4ec090886955b1decb9c2e1307bb60bc3cad5da56a` |
| [partitioning](../partitioning/captured.log) | `demos-current-dra.log (CPX) + demos-current-extra.log (DPX/QPX/SPX)` | `58147bf0183e08aafbafc0a7c72ed0a79cde69b1403df2f2e72154d36863bf38` |

A separate supplemental crash check used the wrong metric name and timed out;
it is not represented as a successful check here. The recorded main suites
cover overheat, ECC and recovery. Busy/idle/crash action descriptions do not
imply that every action has a retained end-to-end passing transcript in this
folder. Independently schedulable same-GPU partitions remain unimplemented.

To print a retained log through the demo script, use
`python3 demo/run.py <demo> --show-captured`. This is explicitly recorded output
and does not contact the cluster.

For a new capture, run a command and retain its output:

```bash
set -o pipefail
python3 demo/run.py telemetry 2>&1 | tee /tmp/amd-telemetry-demo.log
# Workload logs can also be retained directly:
kubectl -n amd-demo-multi-gpu logs consumer-0 | tee /tmp/amd-multi-gpu-pod.log
```

Use the recorded outputs in each demo's README to narrate an actual run, then
use [EVIDENCE.md](../EVIDENCE.md) for fresh layer-by-layer inspection. A historical
capture does not certify the current state of another cluster.
