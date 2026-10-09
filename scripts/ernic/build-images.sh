#!/usr/bin/env bash
# Maintainer only. Users pull versioned images in setup.sh.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$HERE/versions.env"
PUSH=false
[ "${1:-}" != --push ] || { PUSH=true; shift; }
[ "$#" -eq 0 ] || { echo "usage: $0 [--push]" >&2; exit 1; }
BUILD="${BUILD_DIR:-$ROOT/tmp/ernic-images}"
mkdir -p "$BUILD"
fetch() {
 local name="$1" repo="$2" commit="$3"
 if [ ! -d "$BUILD/$name/.git" ]; then
  git init -q "$BUILD/$name"
  git -C "$BUILD/$name" remote add origin "$repo"
  git -C "$BUILD/$name" fetch -q --depth=1 origin "$commit"
  git -C "$BUILD/$name" checkout -q --detach FETCH_HEAD
 fi
 [ "$(git -C "$BUILD/$name" rev-parse HEAD)" = "$commit" ]
 [ -z "$(git -C "$BUILD/$name" status --porcelain)" ]
}
fetch operator https://github.com/ROCm/network-operator.git "$NETWORK_OPERATOR_COMMIT"
fetch plugin https://github.com/ROCm/k8s-network-device-plugin.git "$NETWORK_PLUGIN_COMMIT"
for arch in arm64 amd64; do
 for component in operator plugin; do mkdir -p "$BUILD/$arch/$component"; done
 (cd "$BUILD/operator" && GOOS=linux GOARCH="$arch" CGO_ENABLED=0 go build -mod=vendor -o "$BUILD/$arch/operator/manager" ./cmd)
 (cd "$BUILD/plugin" && GOOS=linux GOARCH="$arch" CGO_ENABLED=0 go build -mod=vendor -o "$BUILD/$arch/plugin/sriovdp" ./cmd/sriovdp)
 cp "$BUILD/operator/LICENSE" "$BUILD/$arch/operator/"
 cp "$BUILD/plugin/LICENSE" "$BUILD/$arch/plugin/"
 curl -fsSL "https://dl.k8s.io/release/v1.37.0/bin/linux/$arch/kubectl" -o "$BUILD/$arch/operator/kubectl"
 chmod +x "$BUILD/$arch/operator/kubectl"
 mkdir -p "$BUILD/$arch/operator/crds"
 cp "$BUILD/operator/helm-charts-k8s/crds/networkconfig-crd.yaml" "$BUILD/$arch/operator/crds/"
 cp "$BUILD/operator/helm-charts-k8s/charts/kmm/crds/"*.yaml "$BUILD/$arch/operator/crds/"
 tar -xOf "$BUILD/operator/helm-charts-k8s/charts/node-feature-discovery-chart-0.16.1.tgz" node-feature-discovery/crds/nfd-api-crds.yaml > "$BUILD/$arch/operator/crds/nfd-api-crds.yaml"
 podman build --platform "linux/$arch" --build-arg "UPSTREAM_COMMIT=$NETWORK_OPERATOR_COMMIT" -f "$HERE/images/Containerfile.operator" -t "$NETWORK_OPERATOR_IMAGE-$arch" "$BUILD/$arch/operator"
 podman build --platform "linux/$arch" --build-arg "UPSTREAM_COMMIT=$NETWORK_PLUGIN_COMMIT" -f "$HERE/images/Containerfile.plugin" -t "$NETWORK_PLUGIN_IMAGE-$arch" "$BUILD/$arch/plugin"
done
for image in "$NETWORK_OPERATOR_IMAGE" "$NETWORK_PLUGIN_IMAGE"; do
 podman manifest rm "$image" >/dev/null 2>&1 || true
 podman manifest create "$image"
 for arch in arm64 amd64; do podman manifest add "$image" "$image-$arch"; done
 if $PUSH; then podman manifest push --all "$image" "docker://$image"; fi
done
# Mac worker path is ARM64 only. Do not advertise an untested AMD64 lab image.
podman build --platform linux/arm64 --build-arg "ERNIC_COMMIT=$ERNIC_COMMIT" \
 --build-arg "VFIO_COMMIT=$VFIO_COMMIT" --build-arg "QEMU_COMMIT=$QEMU_COMMIT" \
 -f "$HERE/images/Containerfile.lab" -t "$ERNIC_LAB_IMAGE" "$HERE/images"
if $PUSH; then podman push "$ERNIC_LAB_IMAGE"; fi
