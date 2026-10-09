#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
NS="${DEMO_NAMESPACE:-amd-demo-gpu-network}"
NODE="${ERNIC_NODE:-amd-ernic-worker-1}"
k=(kubectl --context "$CONTEXT")
case "${1:-}" in
 --cleanup) "${k[@]}" delete namespace "$NS" --ignore-not-found; exit ;;
 "") ;;
 *) echo "usage: $0 [--cleanup]" >&2; exit 1 ;;
esac
"${k[@]}" create namespace "$NS" --dry-run=client -o yaml | "${k[@]}" apply -f -
"${k[@]}" -n "$NS" create configmap tiny-llm-app --from-file=app.py="$HERE/app.py" --dry-run=client -o yaml | "${k[@]}" apply -f -
NS="$NS" NODE="$NODE" python3 - "$HERE/workload.yaml" <<'PYCODE' | "${k[@]}" apply -f -
import os,pathlib,re,sys
for value in (os.environ["NS"],os.environ["NODE"]):
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]*", value), "Invalid Kubernetes name"
print(pathlib.Path(sys.argv[1]).read_text().replace("amd-demo-gpu-network",os.environ["NS"]).replace("amd-ernic-worker-1",os.environ["NODE"]))
PYCODE
"${k[@]}" -n "$NS" wait --for=condition=Ready pod/tiny-llm-gpu-network --timeout=300s
"${k[@]}" -n "$NS" logs tiny-llm-gpu-network
DEMO_NAMESPACE="$NS" python3 "$HERE/verify.py"
"${k[@]}" -n "$NS" logs tiny-llm-gpu-network
printf '\nDemo stays running. Clean up with: %s --cleanup\n' "$0"
