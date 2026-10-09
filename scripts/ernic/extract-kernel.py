#!/usr/bin/env python3
"""Extract the unchanged ARM64 kernel from Ubuntu's unified EFI image."""
import pathlib
import struct
import subprocess
import sys

source, output = map(pathlib.Path, sys.argv[1:])
data = source.read_bytes()
pe = struct.unpack_from("<I", data, 0x3C)[0]
assert data[pe:pe + 4] == b"PE\0\0"
sections = struct.unpack_from("<H", data, pe + 6)[0]
optional_size = struct.unpack_from("<H", data, pe + 20)[0]
for index in range(sections):
    start = pe + 24 + optional_size + 40 * index
    if data[start:start + 8].rstrip(b"\0") != b".linux":
        continue
    size, offset = struct.unpack_from("<II", data, start + 16)
    kernel = data[offset:offset + size]
    if kernel[56:60] == b"ARMd":
        output.write_bytes(kernel)
    else:
        payload_offset, payload_size = struct.unpack_from("<II", kernel, 8)
        payload = kernel[payload_offset:payload_offset + payload_size]
        assert payload[:4] == b"\x28\xb5\x2f\xfd", "Expected pinned Ubuntu zstd zboot payload"
        subprocess.run(["zstd", "-d", "-q", "-f", "-o", str(output)], input=payload, check=True)
    assert output.read_bytes()[56:60] == b"ARMd", "Not an ARM64 Linux boot Image"
    break
else:
    raise RuntimeError("Unified EFI image has no .linux section")
