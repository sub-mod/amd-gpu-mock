#!/bin/sh
set -eu
run() {
 if [ "$(uname -m)" = aarch64 ]; then
  /usr/bin/qemu-x86_64-static -L /opt/amd64 -E LD_LIBRARY_PATH=/mock "$@"
 else
  LD_LIBRARY_PATH=/mock "$@"
 fi
}
run /home/amd/bin/gpuagent -s /var/run/gpuagent.sock &
agent=$!
trap 'kill "$agent" "${server:-}" 2>/dev/null || true' EXIT INT TERM
sleep 3
run /home/amd/bin/server "$@" &
server=$!
# Fail the container if either half of AMD's collection pipeline stops.
while kill -0 "$agent" 2>/dev/null && kill -0 "$server" 2>/dev/null; do sleep 2; done
exit 1
