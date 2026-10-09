#!/usr/bin/env bash
set -euo pipefail
# This demo uses its own cluster; deletion leaves the amd-mock/ERNIC cluster alone.
kind delete cluster --name "${SPUR_CLUSTER:-amd-spur}"
