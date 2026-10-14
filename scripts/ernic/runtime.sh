#!/usr/bin/env bash
# Shared container runtime selection for local and Linux CI ERNIC workers.
if [ -z "${CONTAINER_RUNTIME:-}" ]; then
 if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  CONTAINER_RUNTIME=docker
 elif command -v podman >/dev/null && podman info >/dev/null 2>&1; then
  CONTAINER_RUNTIME=podman
 else
  echo 'No running Docker or Podman runtime; set CONTAINER_RUNTIME explicitly.' >&2
  return 1
 fi
fi
case "$CONTAINER_RUNTIME" in
 docker) arch="$(docker info --format '{{.Architecture}}')" ;;
 podman) arch="$(podman info --format '{{.Host.Arch}}')" ;;
 *) echo 'CONTAINER_RUNTIME must be docker or podman' >&2; return 1 ;;
esac
case "$arch" in
 arm64|aarch64) ERNIC_RUNTIME_ARCH=arm64 ;;
 amd64|x86_64) ERNIC_RUNTIME_ARCH=amd64 ;;
 *) echo "Unsupported runtime architecture: $arch" >&2; return 1 ;;
esac
export CONTAINER_RUNTIME ERNIC_RUNTIME_ARCH KIND_EXPERIMENTAL_PROVIDER="$CONTAINER_RUNTIME"
ernic_container_exists() { "$CONTAINER_RUNTIME" container inspect "$1" >/dev/null 2>&1; }
