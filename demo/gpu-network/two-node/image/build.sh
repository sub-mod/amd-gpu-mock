#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=docker.io/submod/amd-rdma-demo:0.1.0
[ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = --push ]; } || { echo "usage: $0 [--push]" >&2; exit 1; }
podman build --platform linux/arm64 -f "$HERE/Containerfile" -t "$IMAGE" "$HERE"
if [ "${1:-}" = --push ]; then podman push "$IMAGE"; fi
