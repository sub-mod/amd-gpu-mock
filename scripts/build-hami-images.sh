#!/usr/bin/env bash
# Native per-architecture build; setup users pull published images instead.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="${CONTAINER_RUNTIME:-docker}"
cd "$ROOT"
source demo/hami/versions.env
[[ $# == 0 || ( $# == 1 && "$1" == --push ) ]] || { echo 'usage: scripts/build-hami-images.sh [--push]' >&2; exit 2; }
demo/hami/fetch.sh
git -C tmp/hami-main/amd-device-plugin submodule update --init --depth 1
[[ "$(git -C tmp/hami-main/amd-device-plugin/amd-hami-core rev-parse HEAD)" == "$HAMI_CORE_COMMIT" ]]
for item in Plugin:amd-gpu-mock-hami Scheduler:amd-gpu-mock-hami-scheduler; do
 file="${item%%:*}"; name="${item#*:}"
 args=(build -f "deployments/hami/$file.Dockerfile" -t "local/$name:test")
 if [[ "$runtime" == podman ]]; then args+=(--ignorefile "deployments/hami/$file.Dockerfile.dockerignore"); fi
 "$runtime" "${args[@]}" .
 if [[ "${1:-}" == --push ]]; then
  arch="$("$runtime" image inspect "local/$name:test" --format '{{.Architecture}}')"
  ref="docker.io/submod/$name:${HAMI_IMAGE_TAG:-v0.1.0}-$arch"
  if "$runtime" manifest inspect "$ref" >/dev/null 2>&1; then echo "Refusing to overwrite $ref" >&2; exit 1; fi
  "$runtime" tag "local/$name:test" "$ref"
  "$runtime" push "$ref"
 fi
done
