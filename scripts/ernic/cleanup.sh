#!/usr/bin/env bash
# Remove only the named lab worker/container; preserve the default Podman VM.
set -euo pipefail
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
NODE="${ERNIC_NODE:-amd-ernic-worker-1}"
LAB="${ERNIC_CONTAINER:-amd-ernic-lab}"
NS="${DEMO_NAMESPACE:-amd-demo-gpu-network}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${ERNIC_STATE_DIR:-$HERE/../../tmp/ernic}"
SSH_PORT="${ERNIC_SSH_PORT:-2228}"
k=(kubectl --context "$CONTEXT")
"${k[@]}" delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s
if "${k[@]}" get node "$NODE" >/dev/null 2>&1; then
 "${k[@]}" drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=120s
 "${k[@]}" delete node "$NODE"
fi
if podman container exists "$LAB"; then
 if [ -f "$STATE/id_ed25519" ] && [ -f "$STATE/known_hosts" ]; then
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o "UserKnownHostsFile=$STATE/known_hosts" -i "$STATE/id_ed25519" -p "$SSH_PORT" demo@127.0.0.1 'sudo systemctl poweroff' || true
  for attempt in $(seq 1 30); do
   [ ! -f "$STATE/boot.exit" ] || break
   sleep 2
  done
 fi
 podman stop --time 30 "$LAB"
 podman rm "$LAB"
fi
echo 'Worker removed. Cached downloads, VM disk and SSH key remain under ERNIC_STATE_DIR (default tmp/ernic).'
