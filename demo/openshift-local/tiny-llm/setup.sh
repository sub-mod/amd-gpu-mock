#!/usr/bin/env bash
# Run as the macOS user; never put pull-secret contents into logs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
# Local development default: sibling crc folder. CI should override this path
# to a protected file created from its secret store.
PULL_SECRET_FILE="${PULL_SECRET_FILE:-$REPO/../crc/pull-secret.txt}"
if [[ ! -r "$PULL_SECRET_FILE" ]]; then
 echo "Set PULL_SECRET_FILE to a readable Red Hat pull-secret file: $PULL_SECRET_FILE" >&2
 exit 1
fi
crc setup
crc start --pull-secret-file "$PULL_SECRET_FILE"
echo 'CRC started. Use crc oc-env, log in as admin, then run run.py install.'
