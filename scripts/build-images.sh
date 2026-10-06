#!/usr/bin/env bash
# Maintainer build: cross-compile pinned sources, assemble both architectures,
# and optionally publish the manifests and OCI Helm chart. End users use Helm.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/release.env
source "$REPO_ROOT/scripts/release.env"
PUSH=false
if [ "${1:-}" = --push ]; then PUSH=true; shift; fi
[ "$#" -eq 0 ] || { echo "usage: $0 [--push]" >&2; exit 1; }
RUNTIME="${CONTAINER_RUNTIME:-podman}"
[ "$RUNTIME" = podman ] || { echo "Multiarch release builds currently require Podman" >&2; exit 1; }
for bin in "$RUNTIME" go git helm; do command -v "$bin" >/dev/null; done
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/tmp/release-$RELEASE_VERSION}"
mkdir -p "$BUILD_DIR"
fetch() {
    local url="$1" ref="$2" commit="$3" dest="$4"
    if [ ! -d "$dest/.git" ]; then git clone --quiet --depth 1 --branch "$ref" "$url" "$dest"; fi
    [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] || { echo "Unexpected upstream commit in $dest" >&2; exit 1; }
    [ -z "$(git -C "$dest" status --porcelain)" ] || { echo "Upstream source has modifications: $dest" >&2; exit 1; }
}
fetch https://github.com/ROCm/k8s-gpu-dra-driver.git "$DRA_REF" "$DRA_COMMIT" "$BUILD_DIR/dra"
fetch https://github.com/ROCm/container-toolkit.git "$TOOLKIT_REF" "$TOOLKIT_COMMIT" "$BUILD_DIR/toolkit"
cat > "$BUILD_DIR/Dockerfile.compiler" <<'DOCKERFILE'
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends gcc-x86-64-linux-gnu gcc-aarch64-linux-gnu libc6-dev-amd64-cross libc6-dev-arm64-cross && rm -rf /var/lib/apt/lists/*
DOCKERFILE
"$RUNTIME" build -f "$BUILD_DIR/Dockerfile.compiler" -t localhost/amd-mock-cross-compiler "$BUILD_DIR"
(cd "$REPO_ROOT" && go test ./...)
for arch in amd64 arm64; do
    context="$BUILD_DIR/$arch"
    mkdir -p "$context/mock/bin" "$context/mock/pkg/mocksmi" "$context/driver" "$context/node/bin"
    cp -R "$REPO_ROOT/profiles" "$context/mock/"
    (cd "$REPO_ROOT" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "$context/mock/bin/node-agent" ./cmd/node-agent)
    (cd "$REPO_ROOT" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "$context/mock/bin/nri-plugin" ./cmd/nri-plugin)
    compiler=x86_64-linux-gnu-gcc
    [ "$arch" = amd64 ] || compiler=aarch64-linux-gnu-gcc
    "$RUNTIME" run --rm -v "$REPO_ROOT/pkg/mocksmi:/src:ro" -v "$context/mock/pkg/mocksmi:/out" \
        localhost/amd-mock-cross-compiler "$compiler" -shared -fPIC -O2 \
        -Wl,-soname,libamd_smi.so.27 -o /out/libamd_smi.so /src/mock_amdsmi.c /src/stubs.c
    (cd "$BUILD_DIR/dra" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -mod=vendor \
        -ldflags "-s -w -X main.version=$DRA_REF" -o "$context/driver/gpu-kubeletplugin" ./cmd/gpu-kubeletplugin)
    (cd "$BUILD_DIR/dra" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -mod=vendor \
        -ldflags "-s -w -X main.version=$DRA_REF" -o "$context/driver/webhook" ./cmd/webhook)
    cp "$BUILD_DIR/dra/LICENSE" "$context/driver/"
    (cd "$BUILD_DIR/toolkit" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "$context/node/bin/amd-container-runtime" ./cmd/container-runtime)
    (cd "$BUILD_DIR/toolkit" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "$context/node/bin/amd-ctk" ./cmd/amd-ctk)
    cp "$REPO_ROOT"/deployments/kind-node/*.toml "$context/node/"
    cp "$BUILD_DIR/toolkit/LICENSE" "$context/node/TOOLKIT-LICENSE"
    "$RUNTIME" build --platform "linux/$arch" -f "$REPO_ROOT/Dockerfile.prebuilt" \
        -t "$IMAGE_REGISTRY/amd-gpu-mock:v$RELEASE_VERSION-$arch" "$context/mock"
    "$RUNTIME" build --platform "linux/$arch" --build-arg "UPSTREAM_COMMIT=$DRA_COMMIT" \
        -f "$REPO_ROOT/deployments/dra/image/Dockerfile" \
        -t "$IMAGE_REGISTRY/amd-gpu-dra-driver:$DRA_IMAGE_TAG-$arch" "$context/driver"
    "$RUNTIME" build --platform "linux/$arch" --build-arg "BASE_IMAGE=$KIND_BASE_IMAGE" \
        -f "$REPO_ROOT/deployments/kind-node/Dockerfile" \
        -t "$IMAGE_REGISTRY/amd-mock-kind-node:$RELEASE_VERSION-$arch" "$context/node"
done
for artifact in amd-gpu-mock amd-gpu-dra-driver amd-mock-kind-node; do
    tag="$RELEASE_VERSION"
    [ "$artifact" != amd-gpu-dra-driver ] || tag="$DRA_IMAGE_TAG"
    [ "$artifact" != amd-gpu-mock ] || tag="v$RELEASE_VERSION"
    manifest="$IMAGE_REGISTRY/$artifact:$tag"
    "$RUNTIME" manifest rm "$manifest" >/dev/null 2>&1 || true
    "$RUNTIME" manifest create "$manifest"
    for arch in amd64 arm64; do "$RUNTIME" manifest add "$manifest" "$manifest-$arch"; done
    if $PUSH; then "$RUNTIME" manifest push --all "$manifest" "docker://$manifest"; fi
done
helm lint "$REPO_ROOT/deployments/helm/amd-gpu-mock"
helm package "$REPO_ROOT/deployments/helm/amd-gpu-mock" -d "$BUILD_DIR"
if $PUSH; then
    helm push "$BUILD_DIR/amd-gpu-mock-${CHART_VERSION:-$RELEASE_VERSION}.tgz" "oci://$IMAGE_REGISTRY"
fi
echo "Built AMD64/ARM64 release $RELEASE_VERSION (published=$PUSH)."
