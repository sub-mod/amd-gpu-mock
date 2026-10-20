#!/bin/sh
# Run in the disposable AMD64 SDK container, after staging cross-built artifacts.
set -eu
src=${ROCJITSU_SOURCE:-/source/emulation/rocjitsu}
artifacts=${ROCJITSU_ARTIFACTS:-/results/artifacts}
logs=${ROCJITSU_RESULTS:-/results}
export LD_LIBRARY_PATH=/opt/rocm/lib
# Prohibit accidental validation against real devices.
[ ! -e /dev/kfd ] && [ ! -d /dev/dri ] || { echo 'Use a container without GPU devices' >&2; exit 1; }
/opt/rocm/llvm/bin/amdclang++ -x hip --offload-arch=gfx942 \
  --rocm-path=/opt/rocm -std=c++20 -O2 \
  -isystem "$artifacts/gtest-include" \
  -o "$artifacts/bin/hip_vector_add_test" "$src/tests/hip_vector_add_test.cpp" \
  -L"$artifacts/lib" -lgtest -lpthread -Wl,-rpath,/opt/rocm/lib
set +e
timeout 30 "$artifacts/bin/hip_vector_add_test" \
  --gtest_filter=HipVectorAddTest.CorrectResult > "$logs/hip-without-simulator.log" 2>&1
control=$?
set -e
[ "$control" -eq 1 ] && grep -q 'no ROCm-capable device' "$logs/hip-without-simulator.log" || {
  cat "$logs/hip-without-simulator.log"; echo "Unexpected control result: $control" >&2; exit 1;
}
printf 'Control: expected failure without simulator (exit %s)\n' "$control"
set +e
timeout 120 "$artifacts/bin/rocjitsu" \
  --config "$src/configs/gfx942_cdna3_kmd.json" -- \
  "$artifacts/bin/hip_vector_add_test" --gtest_filter=HipVectorAddTest.CorrectResult \
  > "$logs/hip-with-simulator.log" 2>&1
simulator=$?
set -e
cat "$logs/hip-with-simulator.log"
[ "$simulator" -eq 0 ] || exit "$simulator"
grep -q '^\[  PASSED  \] 1 test\.' "$logs/hip-with-simulator.log"
! grep -q '\[  SKIPPED \]' "$logs/hip-with-simulator.log"
