#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP="$ROOT/experiments/amd-driver-mock"
source "$EXP/versions.env"
runtime="${CONTAINER_RUNTIME:-podman}"
cd "$ROOT"
mkdir -p tmp/hami
for item in "amd-device-plugin:$HAMI_AMD_COMMIT" "HAMi:$HAMI_COMMIT"; do
  repo="${item%%:*}"; pin="${item#*:}"; dest="tmp/hami/$repo"
  if [[ ! -d "$dest/.git" ]]; then git clone --depth 1 "https://github.com/Project-HAMi/$repo.git" "$dest"; fi
  if [[ -n "$(git -C "$dest" status --porcelain)" ]]; then echo "Refusing modified upstream checkout: $dest" >&2; exit 1; fi
  git -C "$dest" fetch --depth 1 origin "$pin"
  git -C "$dest" checkout --detach "$pin"
done
git -C tmp/hami/amd-device-plugin submodule update --init --depth 1
[[ "$(git -C tmp/hami/amd-device-plugin/amd-hami-core rev-parse HEAD)" = "$HAMI_CORE_COMMIT" ]] || { echo "Unexpected core source pin" >&2; exit 1; }
for item in 'backend:Containerfile:amd-driver-mock' 'plugin:Hami.Containerfile:amd-driver-mock-hami' 'scheduler:Scheduler.Containerfile:amd-driver-mock-scheduler'; do
  IFS=: read -r kind file name <<< "$item"
  platform_args=()
  if [[ -n "${DRIVER_MOCK_PLATFORM:-}" ]]; then platform_args=(--platform "$DRIVER_MOCK_PLATFORM"); fi
  "$runtime" build "${platform_args[@]}" --ignorefile "$EXP/containerignore" -t "localhost/$name:experiment" -f "$EXP/$file" .
  arch="$("$runtime" image inspect "localhost/$name:experiment" --format '{{.Architecture}}')"
  [[ "$arch" = arm64 || "$arch" = amd64 ]] || { echo "Unsupported architecture: $arch" >&2; exit 1; }
  if [[ "${1:-}" = --push ]]; then
    image="docker.io/submod/$name:${DRIVER_MOCK_IMAGE_TAG:-0.1.0-experiment.2-$arch}"
    if "$runtime" manifest inspect "$image" >/dev/null 2>&1; then echo "Refusing to overwrite published $image; choose a new DRIVER_MOCK_IMAGE_TAG" >&2; exit 1; fi
    [[ "$image" = *"-$arch" ]] || { echo "Tag must end in -$arch" >&2; exit 1; }
    "$runtime" tag "localhost/$name:experiment" "$image"
    "$runtime" push "$image"
  fi
done
