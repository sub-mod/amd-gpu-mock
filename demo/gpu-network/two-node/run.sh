#!/usr/bin/env bash
# Allocate one mock GPU/NIC per worker, then verify cross-worker verbs payloads.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
IMAGE=docker.io/submod/amd-rdma-demo:0.1.0
k=(kubectl --context "$CONTEXT")
if [ "${1:-}" = --cleanup ]; then
 "${k[@]}" delete namespace amd-demo-rdma amd-demo-rdma-a amd-demo-rdma-b --ignore-not-found
 exit
fi
[ "$#" -eq 0 ] || { echo "usage: $0 [--cleanup]" >&2; exit 1; }
LOGS="${RDMA_LOG_DIR:-$ROOT/tmp/rdma-demo/run}"
mkdir -p "$LOGS"
printf '\n=== Worker and allocator readiness ===\n'
for node in amd-ernic-rdma-a amd-ernic-rdma-b; do
 "${k[@]}" wait --for=condition=Ready "node/$node" --timeout=180s
done
"${k[@]}" -n amd-mock rollout status ds/amd-gpu-mock --timeout=300s
"${k[@]}" -n amd-mock rollout status ds/amd-gpu-mock-dra-kubeletplugin --timeout=300s
"${k[@]}" -n kube-amd-network rollout status ds/ernic-device-plugin --timeout=300s
for node in amd-ernic-rdma-a amd-ernic-rdma-b; do
 ready=false
 for attempt in $(seq 1 36); do
  if "${k[@]}" get node "$node" -o json | python3 -c '
import json,sys
n=json.load(sys.stdin)
ready=int(n["status"].get("allocatable",{}).get("amd.com/nic","0")) == 1
if ready: print(n["metadata"]["name"] + ": Ready, one NIC advertised")
sys.exit(0 if ready else 1)
'; then ready=true; break; fi
  sleep 5
 done
 $ready || { echo "$node did not advertise one allocatable NIC within 3 minutes" >&2; exit 1; }
done
# Remove the previous two-namespace layout before requesting the same NICs.
"${k[@]}" delete namespace amd-demo-rdma-a amd-demo-rdma-b --ignore-not-found --wait=true --timeout=120s
ns=amd-demo-rdma
for side in a b; do
 pod="tiny-llm-rdma-$side"
 node="amd-ernic-rdma-$side"
 "${k[@]}" get node "$node" >/dev/null
 "${k[@]}" create namespace "$ns" --dry-run=client -o yaml | "${k[@]}" apply -f -
 phase="$("${k[@]}" -n "$ns" get pod "$pod" -o jsonpath='{.status.phase}' --ignore-not-found)"
 if [ "$phase" = Failed ] || [ "$phase" = Succeeded ]; then
  "${k[@]}" -n "$ns" delete pod "$pod" --wait=true
 fi
 "${k[@]}" -n "$ns" create configmap tiny-llm-app --from-file=app.py="$HERE/../single-node/app.py" --dry-run=client -o yaml | "${k[@]}" apply -f -
 python3 - "$HERE/../single-node/workload.yaml" "$ns" "$node" "$IMAGE" "$pod" <<'PY' | "${k[@]}" apply -f -
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text().replace('amd-demo-gpu-network',sys.argv[2]).replace('amd-ernic-worker-1',sys.argv[3]).replace('docker.io/library/python:3.11-slim',sys.argv[4])
s=s.replace('tiny-llm-gpu-network',sys.argv[5]).replace('  name: tiny-llm\n', '  name: '+sys.argv[5]+'\n')
print(s)
PY
 "${k[@]}" -n "$ns" wait --for=condition=Ready "pod/$pod" --timeout=300s
 printf '\n=== Allocation/HTTP preflight for %s (transfer follows after both Pods are Ready) ===\n' "$node"
 KUBE_CONTEXT="$CONTEXT" ERNIC_NODE="$node" DEMO_NAMESPACE="$ns" DEMO_POD="$pod" python3 "$HERE/../single-node/verify.py"
done
receiver_ip="$("${k[@]}" -n "$ns" get pod tiny-llm-rdma-a -o jsonpath='{.status.podIP}')"
[ -n "$receiver_ip" ]
transfer() {
 local label="$1" corrupt="$2" server_rc=0 client_rc=0
 printf '\n=== %s: CPU-buffer transfer via verbs ===\n' "$label"
 if [ "$corrupt" = true ]; then
  "${k[@]}" -n "$ns" exec tiny-llm-rdma-a -- env RDMA_CORRUPT=1 timeout 240 rdma-transfer server > "$LOGS/$label-receiver.log" 2>&1 &
 else
  "${k[@]}" -n "$ns" exec tiny-llm-rdma-a -- timeout 240 rdma-transfer server > "$LOGS/$label-receiver.log" 2>&1 &
 fi
 local receiver_pid=$!
 "${k[@]}" -n "$ns" exec tiny-llm-rdma-b -- timeout 240 rdma-transfer client "$receiver_ip" > "$LOGS/$label-sender.log" 2>&1 || client_rc=$?
 wait "$receiver_pid" || server_rc=$?
 cat "$LOGS/$label-sender.log" "$LOGS/$label-receiver.log"
 if [ "$corrupt" = true ]; then
  [ "$client_rc" -ne 0 ] && [ "$server_rc" -ne 0 ]
  grep -q RECEIVED_SHA256 "$LOGS/$label-receiver.log"
  grep -q 'operation=match' "$LOGS/$label-receiver.log"
  printf 'PASS: intentional receiver corruption rejected by checksum\n'
 else
  [ "$client_rc" -eq 0 ] && [ "$server_rc" -eq 0 ]
  grep -q 'PAYLOAD_PASS operation=SEND_RECV' "$LOGS/$label-receiver.log"
  grep -q 'PAYLOAD_PASS operation=RDMA_WRITE_WITH_IMM' "$LOGS/$label-receiver.log"
  printf 'PASS: randomized SEND/RECV and RDMA WRITE payloads match SHA-256 across workers\n'
 fi
}
for side in a b; do
 podman exec "amd-ernic-rdma-$side" cat /opt/lab/ernic.stats > "$LOGS/$side-stats-before.log"
done
transfer positive false
transfer corruption true
for side in a b; do
 podman exec "amd-ernic-rdma-$side" cat /opt/lab/ernic.stats > "$LOGS/$side-stats-after.log"
 printf '\n=== ERNIC %s statistics after transfer ===\n' "$side"
 head -n 29 "$LOGS/$side-stats-after.log"
done
printf '\nDemo Pods remain running. Logs: %s\nNo GPU computation or GPU-direct DMA is performed.\n' "$LOGS"
