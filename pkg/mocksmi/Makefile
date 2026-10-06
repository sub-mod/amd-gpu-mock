# Build the mock libamd_smi.so
# This produces a shared library with the same symbol names as the real
# libamd_smi.so from ROCm. The real amd-smi Python CLI loads it via ctypes.

CC ?= gcc
CFLAGS = -shared -fPIC -Wall -Wextra -O2
TARGET = libamd_smi.so

# For cross-compilation to linux/amd64 from macOS:
#   make CC=x86_64-linux-gnu-gcc
# Or build inside a Linux container.

.PHONY: all clean

all: $(TARGET)

$(TARGET): mock_amdsmi.c stubs.c amdsmi_types.h
	$(CC) $(CFLAGS) -Wl,-soname,libamd_smi.so.27 -o $@ mock_amdsmi.c stubs.c

clean:
	rm -f $(TARGET)
