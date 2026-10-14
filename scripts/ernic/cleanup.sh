#!/usr/bin/env bash
# Remove only the named lab worker/container; preserve the container runtime.
set -euo pipefail
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
NODE="${ERNIC_NODE:-amd-ernic-worker-1}"
LAB="${ERNIC_CONTAINER:-amd-ernic-lab}"
NS="${DEMO_NAMESPACE:-amd-demo-gpu-network}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/runtime.sh"
STATE="${ERNIC_STATE_DIR:-$HERE/../../tmp/ernic}"
SSH_PORT="${ERNIC_SSH_PORT:-2228}"
k=(kubectl --context "$CONTEXT")
"${k[@]}" delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s
if "${k[@]}" get node "$NODE" >/dev/null 2>&1; then
 "${k[@]}" drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=120s
 "${k[@]}" delete node "$NODE"
fi
if ernic_container_exists "$LAB"; then
 if [ -f "$STATE/id_ed25519" ] && [ -f "$STATE/known_hosts" ]; then
  ERNIC_GUEST_COMMAND_TIMEOUT=15 ernic_guest_ssh 'sudo systemctl poweroff' || true
  for attempt in $(seq 1 30); do
   [ ! -f "$STATE/boot.exit" ] || break
   sleep 2
  done
 fi
 "$CONTAINER_RUNTIME" stop --time 30 "$LAB"
 "$CONTAINER_RUNTIME" rm "$LAB"
fi
echo 'Worker removed. Cached downloads, VM disk and SSH key remain under ERNIC_STATE_DIR (default tmp/ernic).'
