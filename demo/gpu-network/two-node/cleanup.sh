#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
k=(kubectl --context "$CONTEXT")
# Release both applications while both emulator peers are still connected.
"${k[@]}" delete namespace amd-demo-rdma amd-demo-rdma-a amd-demo-rdma-b --ignore-not-found --wait=true --timeout=120s
for side in b a; do
 node="amd-ernic-rdma-$side"
 if "${k[@]}" get node "$node" >/dev/null 2>&1; then
  "${k[@]}" drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=120s
  "${k[@]}" delete node "$node"
 fi
done
for side in b a; do
 port=2232; [ "$side" != b ] || port=2233
 ERNIC_NODE="amd-ernic-rdma-$side" ERNIC_CONTAINER="amd-ernic-rdma-$side" \
 ERNIC_STATE_DIR="$ROOT/tmp/ernic-rdma-$side" ERNIC_SSH_PORT="$port" \
 DEMO_NAMESPACE="amd-demo-rdma-$side" "$ROOT/scripts/ernic/cleanup.sh"
done
