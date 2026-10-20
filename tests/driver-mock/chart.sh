#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
chart=deployments/helm/amd-gpu-mock
out=$(helm template amd-gpu-mock "$chart" -n amd-mock)
if [[ "$out" == *--device-backend=cuse* ]]; then echo 'default unexpectedly requires CUSE' >&2; exit 1; fi
out=$(helm template amd-gpu-mock "$chart" -n amd-mock --set driverMock.enabled=true)
[[ "$out" == *--device-backend=cuse* ]]
echo 'PASS: CUSE is opt-in; ordinary quick start unchanged'
