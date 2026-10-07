#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
printf '8\n' > "$FIXTURE/count"
for i in {0..7}; do printf '72 230 750 50 300 196608 7 500 1300\nAMD Instinct MI300X\n00000000-0000-0000-0000-%012d\n0000:05:00.0\n' "$i" > "$FIXTURE/gpu$i"; done
"${CONTAINER_RUNTIME:-podman}" run --rm --platform linux/amd64 -v "$ROOT:/src:ro" -v "$FIXTURE:/state:ro" -e MOCK_AMDSMI_STATE_DIR=/state docker.io/library/gcc:14 \
 sh -c 'gcc -I/src/pkg/mocksmi/exporter -pthread /src/tests/telemetry/abi.c /src/pkg/mocksmi/exporter/mock.c /src/pkg/mocksmi/exporter/unsupported.c -o /tmp/abi && /tmp/abi'
