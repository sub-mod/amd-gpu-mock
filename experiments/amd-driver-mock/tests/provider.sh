#!/bin/sh
set -eu
state=${AMD_DRIVER_MOCK_ROOT:-/state}
mkdir -p "$state/dev/dri" "$state/lib" "$state/vgpu"
cp /opt/amd-driver-mock/lib/* "$state/lib/"
pids=''
major=0
rm -f "$state/ready"
cleanup() { for pid in $pids; do kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true; rm -f "$state/ready"; }
trap cleanup EXIT
trap 'exit 0' TERM INT
for spec in '0 dev/dri/card0' '128 dev/dri/renderD128' '255 dev/kfd'; do
  set -- $spec
  # New main helper CLI: NAME MAJOR MINOR. Keep all three endpoints on
  # the same registered major so card and render handles resolve consistently.
  /opt/amd-driver-mock/bin/mock-device "amd-driver-mock-card$1" "$major" "$1" &
  pid=$!;pids="$pids $pid"
  for i in $(seq 1 50); do test -e "/sys/class/cuse/amd-driver-mock-card$1/dev" && break; kill -0 "$pid"; sleep .1; done
  IFS=: read -r major minor < "/sys/class/cuse/amd-driver-mock-card$1/dev"
  # Only replace nodes owned by this disposable experiment volume.
  rm -f "$state/$2"
  mknod "$state/$2" c "$major" "$minor"
  chmod 666 "$state/$2"
  if [ "$1" = 0 ]; then printf '%s\n' "$major" > "$state/device-major"; fi
done
/opt/amd-driver-mock/bin/probe "$state/dev/dri/card0"
touch "$state/ready"
wait
