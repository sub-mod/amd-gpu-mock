#!/usr/bin/env bash
# Run the GPU discovery code from AMD's DRA driver, unmodified, against the
# sysfs tree amd-gpu-mock renders for each profile. No cluster needed.
#
#   tests/dra/discovery-check.sh              # every profile
#   tests/dra/discovery-check.sh mi300x       # one profile
#   DRA_REF=develop tests/dra/discovery-check.sh
#
# Needs: git, Go 1.24, and either unprivileged user namespaces or sudo
# (AMD's code reads hardcoded /sys paths, so the rendered tree is bind-mounted
# over /sys inside a private mount namespace; the host is never touched).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRA_REPO="${DRA_REPO:-https://github.com/ROCm/k8s-gpu-dra-driver.git}"
# Keep in step with DRA_REF in tests/dra/validate_dra.sh and the image tag in
# deployments/dra/values-mock.yaml.
DRA_REF="${DRA_REF:-v1.0.0}"
GO="${GO:-go}"

# macOS has no Linux mount namespaces. Run the same check in the container
# runtime's Linux VM; keep the host checkout read-only.
if [ "$(uname -s)" = Darwin ]; then
    runtime="${CONTAINER_RUNTIME:-podman}"
    command -v "$runtime" >/dev/null || { echo "$runtime not found" >&2; exit 1; }
    exec "$runtime" run --rm --privileged \
        -v "$REPO_ROOT:/src:ro" -w /src \
        -e "DRA_REPO=$DRA_REPO" -e "DRA_REF=$DRA_REF" -e "PARTITION_MODE=${PARTITION_MODE:-}" \
        docker.io/library/golang:1.24-bookworm \
        bash tests/dra/discovery-check.sh "$@"
fi
command -v unshare >/dev/null || { echo "Linux unshare is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The Helm chart ships its own copy of the profiles; they must not drift.
if ! diff -r "$REPO_ROOT/profiles" "$REPO_ROOT/deployments/helm/amd-gpu-mock/profiles" >/dev/null; then
    echo "profiles/ and deployments/helm/amd-gpu-mock/profiles/ differ:" >&2
    diff -r "$REPO_ROOT/profiles" "$REPO_ROOT/deployments/helm/amd-gpu-mock/profiles" >&2 || true
    exit 1
fi

echo "==> Fetching AMD DRA driver $DRA_REF"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$DRA_REF" "$DRA_REPO" "$WORK/dra"
echo "    commit $(git -C "$WORK/dra" rev-parse HEAD)"

echo "==> Building probe (GOPATH mode)"
GP="$WORK/gopath/src"
mkdir -p "$GP/github.com/ROCm/k8s-gpu-dra-driver/pkg" "$GP/github.com/golang" "$GP/gopkg.in" "$GP/amdgpumock" "$GP/probe"
cp -r "$WORK/dra/pkg/amdgpu" "$GP/github.com/ROCm/k8s-gpu-dra-driver/pkg/"
[ -d "$WORK/dra/pkg/consts" ] && cp -r "$WORK/dra/pkg/consts" "$GP/github.com/ROCm/k8s-gpu-dra-driver/pkg/"
cp -r "$WORK/dra/vendor/github.com/golang/glog" "$GP/github.com/golang/"
cp -r "$WORK/dra/vendor/gopkg.in/yaml.v3" "$GP/gopkg.in/"
cp -r "$REPO_ROOT/pkg/gpu/kfd" "$GP/amdgpumock/"
cp "$REPO_ROOT/tests/dra/probe/main.go" "$GP/probe/"
find "$GP" -name '*_test.go' -delete
(cd "$GP/probe" && GO111MODULE=off GOPATH="$WORK/gopath" GOFLAGS='' GOTOOLCHAIN=local \
    "$GO" build -tags dradiscovery -o "$WORK/probe" .)

# Run a command with $1 bind-mounted over /sys in a private mount namespace.
in_mock_sys() {
    local sys="$1"; shift
    # shellcheck disable=SC2016  # expanded by the inner sh, not here
    local script='mount --bind "$0" /sys && exec "$@"'
    if unshare --mount --map-root-user true 2>/dev/null; then
        unshare --mount --map-root-user sh -c "$script" "$sys" "$@"
    else
        sudo -n unshare --mount --propagation private sh -c "$script" "$sys" "$@"
    fi
}

if [ $# -gt 0 ]; then
    profiles=("$@")
else
    profiles=()
    for f in "$REPO_ROOT"/profiles/*.yaml; do profiles+=("$(basename "$f" .yaml)"); done
fi

failed=()
for name in "${profiles[@]}"; do
    profile="$REPO_ROOT/profiles/$name.yaml"
    root="$WORK/root-$name"
    echo "==> $name"
    "$WORK/probe" render "$profile" "$root"
    if ! in_mock_sys "$root/sys" "$WORK/probe" check "$profile" 2>"$WORK/$name.log"; then
        failed+=("$name")
        echo "    (AMD driver log: $(grep -c . "$WORK/$name.log") lines)"
        sed 's/^/    | /' "$WORK/$name.log" | grep -E 'W[0-9]|E[0-9]|F[0-9]' | head -20 || true
    fi
done

echo
if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "All ${#profiles[@]} profile(s) pass AMD DRA driver $DRA_REF discovery."
