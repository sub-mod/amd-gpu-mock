// SPDX-License-Identifier: Apache-2.0
#include <amdgpu.h>
#include <amdgpu_drm.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
int main(int argc, char **argv) {
    assert(argc == 5);
    int fd = open(argv[1], O_RDWR); assert(fd >= 0);
    uint32_t major, minor; amdgpu_device_handle dev = NULL;
    int expected_unavailable = !strcmp(argv[2], "unavailable");
    if (expected_unavailable) {
        assert(amdgpu_device_initialize(fd, &major, &minor, &dev) == -ENODEV);
        close(fd); puts("PASS: unhealthy GPU rejected"); return 0;
    }
    assert(amdgpu_device_initialize(fd, &major, &minor, &dev) == 0);
    struct amdgpu_gpu_info info; struct drm_amdgpu_info_vram_gtt mem;
    assert(amdgpu_query_gpu_info(dev, &info) == 0);
    assert(amdgpu_query_info(dev, AMDGPU_INFO_MEMORY, sizeof(mem), &mem) == 0);
    assert(info.cu_active_number == strtoul(argv[2], NULL, 10));
    assert(mem.vram_size == strtoull(argv[3], NULL, 10));
    assert(amdgpu_get_marketing_name(dev));
    assert(!strcmp(amdgpu_get_marketing_name(dev), argv[4]));
    assert(amdgpu_query_info(dev, 0xffffffff, sizeof(mem), &mem) == -EOPNOTSUPP);
    assert(amdgpu_query_info(dev, AMDGPU_INFO_MEMORY, 1, &mem) == -EINVAL);
    assert(amdgpu_query_gpu_info(NULL, &info) == -EINVAL);
    assert(amdgpu_device_initialize(fd, NULL, &minor, &dev) == -EINVAL);
    errno = 0; assert(ioctl(fd, _IO('d', 0xff), NULL) == -1 && errno == ENOTTY);
    char byte; errno = 0; assert(read(fd, &byte, 1) == -1 && errno == EOPNOTSUPP);
    assert(amdgpu_device_deinitialize(dev) == 0); close(fd);
    fd = open("/dev/null", O_RDONLY); assert(fd >= 0);
    assert(amdgpu_device_initialize(fd, &major, &minor, &dev) == -ENODEV); close(fd);
    puts("PASS: native open, profile capacity/name, invalid handles, unsupported ioctl/read and /dev/null rejection");
    return 0;
}
