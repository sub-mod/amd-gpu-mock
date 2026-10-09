#!/usr/bin/env bash
# Reboot only the two dedicated guests, then repeat allocation and payload checks.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
k=(kubectl --context "$CONTEXT")
[ "$#" -eq 0 ] || { echo "usage: $0" >&2; exit 1; }
LOGS="${RDMA_LOG_DIR:-$ROOT/tmp/rdma-demo/reboot-run}"
mkdir -p "$LOGS"
for side in a b; do
 node="amd-ernic-rdma-$side"
 "${k[@]}" get node "$node" -o jsonpath='{.status.nodeInfo.bootID}' > "$LOGS/$side-boot-before.txt"
 [ -s "$LOGS/$side-boot-before.txt" ]
 printf "Rebooting %s through its separate management interface...\n" "$node"
 rc=0
 # The virtio management NIC remains separate from the emulated data NIC.
 podman exec "$node" timeout 30 ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=5 -o UserKnownHostsFile=/opt/lab/known_hosts \
  -o HostKeyAlias="[127.0.0.1]:$([ "$side" = a ] && echo 2232 || echo 2233)" \
  -i /opt/lab/id_ed25519 -p 2228 demo@127.0.0.1 \
  'sudo systemctl reboot --no-block' || rc=$?
 [ "$rc" -eq 0 ] || [ "$rc" -eq 255 ] || exit "$rc"
done
for side in a b; do
 node="amd-ernic-rdma-$side"
 ready=false
 for attempt in $(seq 1 120); do
  if "${k[@]}" get node "$node" -o json | python3 -c '
import json,pathlib,sys
n=json.load(sys.stdin); old=pathlib.Path(sys.argv[1]).read_text()
boot=n["status"]["nodeInfo"]["bootID"]
ready=boot != old and any(c["type"]=="Ready" and c["status"]=="True" for c in n["status"]["conditions"])
if ready: print(n["metadata"]["name"]+": new boot ID "+boot+", Ready")
sys.exit(0 if ready else 1)
' "$LOGS/$side-boot-before.txt"; then ready=true; break; fi
  sleep 5
 done
 $ready || { echo "$node did not recover with a new boot ID within 10 minutes" >&2; exit 1; }
done
RDMA_LOG_DIR="$LOGS" "$HERE/run.sh"
