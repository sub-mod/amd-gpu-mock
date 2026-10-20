#!/bin/sh
# Inside a disposable Ubuntu container only; never changes a workstation SDK.
set -eu
src=${ROCJITSU_SOURCE:-/source/emulation/rocjitsu}
build=${ROCJITSU_BUILD:-/build}
export PATH=/opt/rocm/bin:/opt/rocm/llvm/bin:$PATH
case $(uname -m) in
  aarch64)
    # Native compiler producing AMD64 binaries. binfmt_misc must run AMD64 ELF
    # for FlatBuffers' generated schema compiler. No GPU devices are required.
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      cmake ninja-build g++-x86-64-linux-gnu
    mkdir -p /lib64
    ln -sf /usr/x86_64-linux-gnu/lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2
    export LD_LIBRARY_PATH=/usr/x86_64-linux-gnu/lib:/usr/lib/gcc-cross/x86_64-linux-gnu/13
    cmake -S "$src" -B "$build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
      -DCMAKE_C_COMPILER=x86_64-linux-gnu-gcc \
      -DCMAKE_CXX_COMPILER=x86_64-linux-gnu-g++ \
      -DFETCHCONTENT_BASE_DIR="$build/dependencies" \
      -DROCJITSU_HOST_CPU_BASELINE=x86-64 -DROCJITSU_ENABLE_VFIO=OFF -DROCM_PATH=
    ;;
  x86_64)
    cmake -S "$src" -B "$build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DFETCHCONTENT_BASE_DIR="$build/dependencies" \
      -DROCJITSU_HOST_CPU_BASELINE=x86-64 -DROCJITSU_ENABLE_VFIO=OFF \
      -DROCM_PATH=/opt/rocm \
      -DHSA_RUNTIME64=/opt/rocm/lib/libhsa-runtime64.so \
      -DHIP_RUNTIME64=/opt/rocm/lib/libamdhip64.so
    ;;
  *) echo 'Only Linux ARM64 cross-build or AMD64 builds are supported here' >&2; exit 1 ;;
esac
cmake --build "$build" --target rocjitsu_bin rocjitsu_shared gtest -j"${BUILD_JOBS:-4}"
