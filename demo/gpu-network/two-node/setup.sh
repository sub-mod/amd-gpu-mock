#!/usr/bin/env bash
# Two dedicated ERNIC workers; remove other ERNIC workers first.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
source "$ROOT/scripts/ernic/versions.env"
memory="$(podman machine inspect --format '{{.Resources.Memory}}')"
[ "$memory" -ge 16384 ] || { echo 'Two-worker demo requires a Podman machine with at least 16 GiB RAM.' >&2; exit 1; }
others="$(podman ps --filter "ancestor=$ERNIC_LAB_IMAGE" --format '{{.Names}}' | awk '$0 != "amd-ernic-rdma-a" && $0 != "amd-ernic-rdma-b"')"
[ -z "$others" ] || { printf 'Remove other ERNIC workers before the two-node demo:\n%s\nFor the standard single-node demo, run ./scripts/ernic/cleanup.sh first.\n' "$others" >&2; exit 1; }
other_nodes="$(kubectl --context "$CONTEXT" get nodes -l amd-gpu-mock.amd.com/network-demo=true -o json | python3 -c '
import json,sys
print("\n".join(n["metadata"]["name"] for n in json.load(sys.stdin)["items"] if n["metadata"]["name"] not in {"amd-ernic-rdma-a","amd-ernic-rdma-b"}))
')"
[ -z "$other_nodes" ] || { printf 'Remove other GPU/network demo workers before proceeding:\n%s\nUse their cleanup script, rather than only stopping their VM container.\n' "$other_nodes" >&2; exit 1; }
for side in a b; do
 node="amd-ernic-rdma-$side"
 lab="amd-ernic-rdma-$side"
 port=2232
 backend=tcp:manager:self:6320
 if [ "$side" = b ]; then
  port=2233
  manager="$(podman inspect amd-ernic-rdma-a --format '{{(index .NetworkSettings.Networks "podman").IPAddress}}')"
  [ -n "$manager" ]
  backend="tcp:worker:$manager:6320"
 fi
 KUBE_CONTEXT="$CONTEXT" ERNIC_NODE="$node" ERNIC_CONTAINER="$lab" \
 ERNIC_STATE_DIR="$ROOT/tmp/ernic-rdma-$side" ERNIC_SSH_PORT="$port" \
 ERNIC_BACKEND="$backend" "$ROOT/scripts/ernic/setup.sh"
done
printf '\nTwo RDMA workers ready. Run ./demo/gpu-network/two-node/run.sh\n'
