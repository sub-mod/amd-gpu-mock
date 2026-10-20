#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime="${CONTAINER_RUNTIME:-podman}"
if [[ "$runtime" = podman ]]; then export KIND_EXPERIMENTAL_PROVIDER=podman; else export KIND_EXPERIMENTAL_PROVIDER=docker; fi
# Destroy our node before its CUSE endpoints. No unrelated cluster is touched.
kind delete cluster --name amd-hami-driver --kubeconfig "$ROOT/tmp/hami/kubeconfig"
if "$runtime" container inspect amd-driver-mock-provider >/dev/null 2>&1; then "$runtime" rm -f amd-driver-mock-provider; fi
if "$runtime" volume inspect amd-driver-mock-state >/dev/null 2>&1; then "$runtime" volume rm amd-driver-mock-state; fi
