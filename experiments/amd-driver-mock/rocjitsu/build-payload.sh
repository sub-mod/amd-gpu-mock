#!/bin/sh
set -eu
src=${ROCJITSU_SOURCE:-/source/emulation/rocjitsu}
evaldir=${COMPUTE_SOURCE:-/evaluation}
core=${HAMI_CORE_SOURCE:-/hami/amd-hami-core}
out=${ROCJITSU_ARTIFACTS:-/results/artifacts}
export PATH=/opt/rocm/bin:/opt/rocm/llvm/bin:$PATH
mkdir -p "$out/bin" "$out/lib"
cc -shared -fPIC -D_GNU_SOURCE -O2 -fvisibility=hidden -I"$core/src/include" -I"$core/src/multiprocess" \
 "$core/src/hip/libamvgpu_audit.c" "$core/src/multiprocess/hip_multiprocess_memory_limit.c" -ldl -pthread -o "$out/lib/libamvgpu.so"
cc -shared -fPIC -O2 "$evaldir/mask-audit.c" -ldl -o "$out/lib/libmask-audit.so"
amdclang++ -D__HIP_PLATFORM_AMD__ -std=c++20 -I/opt/rocm/include "$evaldir/limits.cpp" \
 -L/opt/rocm/lib -lamdhip64 -lhsa-runtime64 -Wl,-rpath,/opt/rocm/lib -o "$out/bin/limits"
amdclang++ -x hip --offload-arch=gfx942 --rocm-path=/opt/rocm -std=c++20 -O2 \
 -isystem "$out/gtest-include" "$src/tests/hip_vector_add_test.cpp" -L"$out/lib" -lgtest -lpthread \
 -Wl,-rpath,/opt/rocm/lib -o "$out/bin/hip_vector_add_test"
