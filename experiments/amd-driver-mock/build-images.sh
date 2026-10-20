#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP="$ROOT/experiments/amd-driver-mock"
source "$EXP/versions.env"
runtime="${CONTAINER_RUNTIME:-podman}"
backend_only=false
push=false
for arg in "$@"; do
 case "$arg" in --backend-only) backend_only=true;; --push) push=true;; *) echo "usage: $0 [--backend-only] [--push]" >&2; exit 2;; esac
done
cd "$ROOT"
mkdir -p tmp/hami
if ! $backend_only; then
for item in "amd-device-plugin:$HAMI_AMD_COMMIT" "HAMi:$HAMI_COMMIT"; do
  repo="${item%%:*}"; pin="${item#*:}"; dest="tmp/hami/$repo"
  if [[ ! -d "$dest/.git" ]]; then git clone --depth 1 "https://github.com/Project-HAMi/$repo.git" "$dest"; fi
  if [[ -n "$(git -C "$dest" status --porcelain)" ]]; then echo "Refusing modified upstream checkout: $dest" >&2; exit 1; fi
  git -C "$dest" fetch --depth 1 origin "$pin"
  git -C "$dest" checkout --detach "$pin"
done
git -C tmp/hami/amd-device-plugin submodule update --init --depth 1
[[ "$(git -C tmp/hami/amd-device-plugin/amd-hami-core rev-parse HEAD)" = "$HAMI_CORE_COMMIT" ]] || { echo "Unexpected core source pin" >&2; exit 1; }
fi
items=('backend:Containerfile:amd-driver-mock')
if ! $backend_only; then items+=('plugin:Hami.Containerfile:amd-driver-mock-hami' 'scheduler:Scheduler.Containerfile:amd-driver-mock-scheduler'); fi
for item in "${items[@]}"; do
  IFS=: read -r kind file name <<< "$item"
  build_args=(build -t "localhost/$name:experiment" -f "$EXP/$file")
  if [[ -n "${DRIVER_MOCK_PLATFORM:-}" ]]; then build_args+=(--platform "$DRIVER_MOCK_PLATFORM"); fi
  if [[ "$runtime" = podman ]]; then build_args+=(--ignorefile "$EXP/containerignore"); fi
  "$runtime" "${build_args[@]}" .
  arch="$("$runtime" image inspect "localhost/$name:experiment" --format '{{.Architecture}}')"
  [[ "$arch" = arm64 || "$arch" = amd64 ]] || { echo "Unsupported architecture: $arch" >&2; exit 1; }
  if $push; then
    image="docker.io/submod/$name:${DRIVER_MOCK_IMAGE_TAG:-0.1.0-experiment.3-$arch}"
    if "$runtime" manifest inspect "$image" >/dev/null 2>&1; then echo "Refusing to overwrite published $image; choose a new DRIVER_MOCK_IMAGE_TAG" >&2; exit 1; fi
    [[ "$image" = *"-$arch" ]] || { echo "Tag must end in -$arch" >&2; exit 1; }
    "$runtime" tag "localhost/$name:experiment" "$image"
    "$runtime" push "$image"
  fi
done
