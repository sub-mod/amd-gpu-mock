#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime="${CONTAINER_RUNTIME:-}"
if [[ -z "$runtime" ]]; then
 if command -v docker >/dev/null && docker info >/dev/null 2>&1; then runtime=docker; else runtime=podman; fi
fi
export KIND_EXPERIMENTAL_PROVIDER="$runtime"
# Uninstall stops the provider and restores protected DRM overlays first.
if [[ -f "$ROOT/tmp/hami-main/kubeconfig" ]]; then
 helm --kubeconfig "$ROOT/tmp/hami-main/kubeconfig" uninstall amd-gpu-mock -n amd-mock --wait --timeout 120s || true
fi
kind delete cluster --name amd-hami-main --kubeconfig "$ROOT/tmp/hami-main/kubeconfig"
