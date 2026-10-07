#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ "${1:-}" = --show-captured ]; then
    cat "$ROOT/demo/partition-allocation/captured.log"
    exit 0
fi
[ "$#" -eq 0 ] || { echo "usage: $0 [--show-captured]" >&2; exit 1; }
exec python3 -u "$ROOT/tests/dra/partition-allocation.py"
