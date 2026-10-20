#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
chart=deployments/helm/amd-gpu-mock
for profile in mi210 mi250x mi300a mi300x mi325x mi350x mi355x; do
 out=$(helm template amd-gpu-mock "$chart" -n amd-mock --show-only templates/configmap.yaml --set gpu.profile="$profile" --set gpu.count=1)
 [[ $(printf '%s\n' "$out" | grep -c 'unique_id:') == 1 ]]
 [[ $(printf '%s\n' "$out" | grep -c 'pci_bdf:') == 1 ]]
done
out=$(helm template amd-gpu-mock "$chart" -n amd-mock --show-only templates/configmap.yaml)
[[ $(printf '%s\n' "$out" | grep -c 'unique_id:') == 8 ]]
for count in 0 -1 9 1.5 xyz; do
 if helm template amd-gpu-mock "$chart" -n amd-mock --set-string gpu.count="$count" >/dev/null 2>&1; then echo "Accepted invalid count $count" >&2; exit 1; fi
done
echo 'PASS single-GPU profiles, unchanged eight-GPU default, invalid inventory limits rejected'
