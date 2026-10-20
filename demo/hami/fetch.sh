#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/demo/hami/versions.env"
cd "$ROOT"
mkdir -p tmp/hami-main
for item in "amd-device-plugin:$HAMI_AMD_COMMIT" "HAMi:$HAMI_COMMIT"; do
 repo="${item%%:*}"; pin="${item#*:}"; dest="tmp/hami-main/$repo"
 if [[ ! -d "$dest/.git" ]]; then git clone --depth 1 "https://github.com/Project-HAMi/$repo.git" "$dest"; fi
 [[ -z "$(git -C "$dest" status --porcelain)" ]] || { echo "Modified upstream checkout: $dest" >&2; exit 1; }
 git -C "$dest" fetch --depth 1 origin "$pin"
 git -C "$dest" checkout --detach "$pin"
done
