#!/usr/bin/env bash
# Build and optionally publish the optional driver image; no RocJITsu/HAMi.
set -euo pipefail
cd "$(dirname "$0")/.."
runtime=${CONTAINER_RUNTIME:-podman}
repository=${DRIVER_IMAGE_REPOSITORY:-docker.io/submod/amd-gpu-mock-driver}
version=${DRIVER_IMAGE_VERSION:-v0.1.1}
push=false
if [ "${1:-}" = --push ]; then push=true; shift; fi
[ "$#" = 0 ] || { echo "usage: $0 [--push]" >&2; exit 2; }
if [ "$runtime" = docker ]; then
  args=(--platform linux/amd64,linux/arm64 -f deployments/driver-mock/Dockerfile -t "$repository:$version")
  $push && args+=(--push)
  # Without --push, retain both platforms in the build cache.
  docker buildx build "${args[@]}" .
else
  [ "$runtime" = podman ] || { echo "runtime must be docker or podman" >&2; exit 2; }
  for arch in amd64 arm64; do
    podman build --platform "linux/$arch" -f deployments/driver-mock/Dockerfile -t "$repository:$version-$arch" .
  done
  podman manifest rm "$repository:$version" >/dev/null 2>&1 || true
  podman manifest create "$repository:$version"
  for arch in amd64 arm64; do podman manifest add "$repository:$version" "$repository:$version-$arch"; done
  if $push; then podman manifest push --all "$repository:$version" "docker://$repository:$version"; fi
fi
