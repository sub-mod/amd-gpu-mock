#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/demo/spur/versions.env"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
case "$RUNTIME" in podman|docker) ;; *) echo "CONTAINER_RUNTIME must be podman or docker" >&2; exit 1 ;; esac
IMAGE="${SPUR_ARM64_IMAGE:-docker.io/submod/spur:0.14.0-arm64.1}"
BUILD="${SPUR_BUILD_DIR:-$ROOT/tmp/spur-arm64}"
PUSH=false
if [[ "${1:-}" == --push ]]; then PUSH=true; shift; fi
[[ $# == 0 ]] || { echo 'usage: build.sh [--push]' >&2; exit 1; }
mkdir -p "$BUILD/source"
curl -fsSL "https://api.github.com/repos/ROCm/spur/tarball/$SPUR_COMMIT" -o "$BUILD/source.tar.gz"
tar -xzf "$BUILD/source.tar.gz" --strip-components=1 -C "$BUILD/source"
patch -d "$BUILD/source" -p1 < "$ROOT/artifacts/spur-arm64/c-char-portability.patch"
# Keep the portability patch reviewable and preserve the upstream build recipe.
python3 - "$BUILD/source/Dockerfile" "$BUILD/Containerfile.arm64" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
needle='protoc-${PROTOC_VERSION}-linux-x86_64.zip'
assert text.count(needle)==1
text=text.replace(needle,'protoc-${PROTOC_VERSION}-linux-aarch_64.zip')
text=text.replace('RUN if [ "$BUILD_MPI_PLUGIN" = "1" ]; then', 'RUN cargo test --release --locked -p spurd --lib mpi_plugin::tests\n\nRUN if [ "$BUILD_MPI_PLUGIN" = "1" ]; then',1)
Path(sys.argv[2]).write_text(text)
PY
python3 - "$BUILD" "$SPUR_COMMIT" "$IMAGE" <<'PYMETA'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1])
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
record={'upstream':'https://github.com/ROCm/spur','revision':sys.argv[2],
        'image':sys.argv[3],'platform':'linux/arm64',
        'source_archive_sha256':sha(root/'source.tar.gz'),
        'cargo_lock_sha256':sha(root/'source/Cargo.lock'),
        'upstream_dockerfile_sha256':sha(root/'source/Dockerfile'),
        'build_recipe_sha256':sha(root/'Containerfile.arm64'),
        'source_changes':'artifacts/spur-arm64/c-char-portability.patch','recipe_change':'protoc download linux-x86_64 -> linux-aarch_64'}
(root/'provenance.json').write_text(json.dumps(record,indent=2)+'\n')
PYMETA
"$RUNTIME" build --platform linux/arm64 --target runtime \
 --build-arg "SPUR_GIT_SHA=$SPUR_COMMIT" --build-arg SPUR_GIT_DIRTY=true \
 --label "org.opencontainers.image.source=https://github.com/ROCm/spur" \
 --label "org.opencontainers.image.revision=$SPUR_COMMIT" \
 --label "org.opencontainers.image.version=$SPUR_VERSION-arm64.1" \
 --label "org.opencontainers.image.licenses=Apache-2.0" \
 -f "$BUILD/Containerfile.arm64" -t "$IMAGE" "$BUILD/source"
"$RUNTIME" image inspect "$IMAGE" --format '{{.Os}}/{{.Architecture}}'
"$RUNTIME" run --rm --platform linux/arm64 "$IMAGE" spur --version
if $PUSH; then
 if [[ "$RUNTIME" == podman ]]; then
  "$RUNTIME" push "$IMAGE" --digestfile "$BUILD/published-digest.txt"
 else
  "$RUNTIME" push "$IMAGE"
  "$RUNTIME" image inspect "$IMAGE" --format '{{index .RepoDigests 0}}' | sed 's/.*@//' > "$BUILD/published-digest.txt"
 fi
fi
