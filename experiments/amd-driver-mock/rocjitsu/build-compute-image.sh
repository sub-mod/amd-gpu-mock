#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)";cd "$ROOT"
runtime="${CONTAINER_RUNTIME:-podman}"
image="${COMPUTE_IMAGE:-docker.io/submod/amd-driver-mock-compute:0.1.0-experiment.1-amd64}"
for path in bin/rocjitsu bin/hip_vector_add_test bin/limits lib/librocjitsu.so lib/libamvgpu.so lib/libmask-audit.so; do
 test -f "tmp/rocjitsu-results/artifacts/$path" || { echo "Missing artifact: $path" >&2;exit 1; }
done
if [[ ${1:-} = --push ]] && "$runtime" manifest inspect "$image" >/dev/null 2>&1;then echo "Published tag already exists: $image" >&2;exit 1;fi
"$runtime" build --platform linux/amd64 -t "$image" -f experiments/amd-driver-mock/rocjitsu/Compute.Containerfile .
[[ "$("$runtime" image inspect "$image" --format '{{.Architecture}}')" = amd64 ]]
if [[ ${1:-} = --push ]];then "$runtime" push "$image";fi
