#!/usr/bin/env bash
# Maintainer mock-image build; leaves published DRA, node and exporter tags intact.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/release.env"
PUSH=false
if [ "${1:-}" = --push ]; then PUSH=true; shift; fi
[ "$#" -eq 0 ] || { echo "usage: $0 [--push]" >&2; exit 1; }
cd "$ROOT"
BUILD="$ROOT/tmp/mock-$MOCK_IMAGE_VERSION"
mkdir -p "$BUILD"
cat > "$BUILD/Dockerfile.compiler" <<'DOCKERFILE'
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends gcc-x86-64-linux-gnu gcc-aarch64-linux-gnu libc6-dev-amd64-cross libc6-dev-arm64-cross && rm -rf /var/lib/apt/lists/*
DOCKERFILE
podman build -f "$BUILD/Dockerfile.compiler" -t localhost/amd-mock-cross-compiler "$BUILD"
go test ./...
for arch in amd64 arm64; do
 context="$BUILD/$arch"
 mkdir -p "$context/bin" "$context/pkg/mocksmi"
 cp -R profiles "$context/"
 CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "$context/bin/node-agent" ./cmd/node-agent
 CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "$context/bin/nri-plugin" ./cmd/nri-plugin
 compiler=x86_64-linux-gnu-gcc
 [ "$arch" = amd64 ] || compiler=aarch64-linux-gnu-gcc
 podman run --rm -v "$ROOT/pkg/mocksmi:/src:ro" -v "$context/pkg/mocksmi:/out" localhost/amd-mock-cross-compiler "$compiler" -shared -fPIC -O2 -Wl,-soname,libamd_smi.so.27 -o /out/libamd_smi.so /src/mock_amdsmi.c /src/stubs.c
 podman build --platform "linux/$arch" -f Dockerfile.prebuilt -t "$IMAGE_REGISTRY/amd-gpu-mock:v$MOCK_IMAGE_VERSION-$arch" "$context"
done
for image in "amd-gpu-mock:v$MOCK_IMAGE_VERSION"; do
 manifest="$IMAGE_REGISTRY/$image"
 podman manifest rm "$manifest" >/dev/null 2>&1 || true
 podman manifest create "$manifest"
 for arch in amd64 arm64; do podman manifest add "$manifest" "$manifest-$arch"; done
 if $PUSH; then
   if [ -n "${REGISTRY_AUTHFILE:-}" ]; then
     podman manifest push --authfile "$REGISTRY_AUTHFILE" --all "$manifest" "docker://$manifest"
   else
     podman manifest push --all "$manifest" "docker://$manifest"
   fi
 fi
done
helm lint deployments/helm/amd-gpu-mock --namespace amd-mock
helm package deployments/helm/amd-gpu-mock -d "$BUILD"
if $PUSH; then helm push "$BUILD/amd-gpu-mock-$CHART_VERSION.tgz" "oci://$IMAGE_REGISTRY"; fi
