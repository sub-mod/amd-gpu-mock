#!/usr/bin/env bash
# Reject configurations that can double-allocate devices or discover real sysfs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHART="$REPO_ROOT/deployments/helm/amd-gpu-mock"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
render() { helm template amd-gpu-mock "$CHART" -n amd-mock "$@"; }
reject() {
    local expected="$1"; shift
    if render "$@" >"$WORK/output" 2>"$WORK/error"; then
        echo "FAIL: invalid configuration rendered successfully" >&2; exit 1
    fi
    grep -Fq "$expected" "$WORK/error" || { cat "$WORK/error" >&2; exit 1; }
    echo "PASS: rejects $expected"
}
render >"$WORK/device-plugin.yaml"
render --set dra.enabled=true --set devicePlugin.enabled=false >"$WORK/dra.yaml"
grep -Fq 'kind: DeviceClass' "$WORK/dra.yaml"
grep -Fq 'path: "/var/lib/amd-gpu-mock/sys"' "$WORK/dra.yaml"
reject 'set devicePlugin.enabled=false' --set dra.enabled=true
reject 'dra.mockSysPath must equal' --set dra.enabled=true --set devicePlugin.enabled=false --set dra.mockSysPath=/sys
reject 'dra.kubeletPlugin.nodeSelector must match' --set dra.enabled=true --set devicePlugin.enabled=false --set nodeSelector.mock=true
render --set dra.enabled=true --set devicePlugin.enabled=false \
    --set nodeSelector.mock=true --set dra.kubeletPlugin.nodeSelector.mock=true \
    --set mockRootDir=/custom/mock --set dra.mockSysPath=/custom/mock/sys >"$WORK/custom.yaml"
grep -Fq 'path: "/custom/mock/sys"' "$WORK/custom.yaml"
echo 'PASS: default, DRA, and custom-root configurations render correctly'
