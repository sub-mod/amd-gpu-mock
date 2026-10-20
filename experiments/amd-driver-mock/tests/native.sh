#!/bin/sh
set -eu
/opt/amd-driver-mock/bin/mock-device 0 /tmp/mock-card0 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
for i in $(seq 1 30); do
  test -e /sys/class/cuse/amd-driver-mock-card0/dev && break
  kill -0 "$pid"
  sleep .1
done
IFS=: read -r major minor < /sys/class/cuse/amd-driver-mock-card0/dev
printf '%s\n' "$major" > "$AMD_DRIVER_MOCK_ROOT/device-major"
mknod /tmp/mock-card0 c "$major" "$minor"
/opt/amd-driver-mock/bin/probe /tmp/mock-card0
