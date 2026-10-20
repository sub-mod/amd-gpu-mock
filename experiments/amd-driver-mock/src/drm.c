// SPDX-License-Identifier: Apache-2.0
// Deliberate user-space ABI simulator. No DRM ioctl or compute implementation.
#include <amdgpu.h>
#include <amdgpu_drm.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

struct mock_handle { int card; };
static struct mock_handle handles[64];
static const char *root(void) {
    const char *p = getenv("AMD_DRIVER_MOCK_ROOT");
    return p ? p : "/var/lib/amd-gpu-mock";
}
static int property(int card, const char *key, uint64_t *out) {
    char path[1024], name[128], line[512], value[128];
    snprintf(path, sizeof(path), "%s/sys/class/kfd/kfd/topology/nodes/%d/properties", root(), card + 1);
    FILE *f = fopen(path, "r");
    if (!f) return -ENODEV;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%127s %127s", name, value) == 2 && !strcmp(name, key)) {
            char *end; errno=0; unsigned long long parsed=strtoull(value,&end,0);
            fclose(f); if(errno || *end) return -ENODATA; *out=parsed; return 0;
        }
    }
    fclose(f); return -ENODATA;
}
static int card_of(amdgpu_device_handle dev) {
    for (int i = 0; i < 64; i++) if ((void *)dev == &handles[i]) return i;
    return -1;
}
static int available(int card) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/sys/class/kfd/kfd/topology/nodes/%d/ras/fatal_error", root(), card+1);
    FILE *f = fopen(path, "r");
    if (f) { int fatal = 0; int ok = fscanf(f, "%d", &fatal); fclose(f); if(ok != 1 || fatal) return 0; }
    uint64_t simds; return property(card, "simd_count", &simds) == 0 && simds > 0;
}
int amdgpu_device_initialize(int fd, uint32_t *maj, uint32_t *min, amdgpu_device_handle *out) {
    struct stat st;
    if (!maj || !min || !out) return -EINVAL;
    *out = NULL;
    if (fstat(fd, &st)) return -errno;
    // Match the dynamic major assigned by the actual CUSE provider. Never
    // accept /dev/null, a regular fixture, or an unrelated real device.
    char path[1024]; unsigned expected_major;
    snprintf(path,sizeof(path),"%s/device-major",root());
    FILE *provider=fopen(path,"r");
    if(!provider) return -ENODEV;
    int ok=fscanf(provider,"%u",&expected_major); fclose(provider);
    if(ok!=1 || !expected_major || !S_ISCHR(st.st_mode) || major(st.st_rdev) != expected_major || minor(st.st_rdev) >= 64) return -ENODEV;
    int card = (int)minor(st.st_rdev);
    if (!available(card)) return -ENODEV;
    handles[card].card = card; *out = (amdgpu_device_handle)&handles[card];
    *maj = 3; *min = 0;
    fprintf(stderr, "amd-driver-mock: libdrm initialize card%d (CUSE provider, library backend)\n", card);
    return 0;
}
int amdgpu_device_deinitialize(amdgpu_device_handle dev) { return card_of(dev) < 0 ? -EINVAL : 0; }
int amdgpu_query_gpu_info(amdgpu_device_handle dev, struct amdgpu_gpu_info *info) {
    int card = card_of(dev); uint64_t simds, percu, device;
    if (card < 0 || !info) return -EINVAL;
    if (!available(card)) return -ENODEV;
    if(property(card,"simd_count",&simds) || property(card,"simd_per_cu",&percu) || !percu || simds % percu || property(card,"device_id",&device)) return -ENODATA;
    memset(info, 0, sizeof(*info)); info->cu_active_number = simds / percu;
    info->asic_id = device; info->family_id = AMDGPU_FAMILY_AI;
    return 0;
}
int amdgpu_query_info(amdgpu_device_handle dev, unsigned id, unsigned size, void *out) {
    int card = card_of(dev); uint64_t bytes;
    if (card < 0 || !out) return -EINVAL;
    if (!available(card)) return -ENODEV;
    if (id != AMDGPU_INFO_MEMORY) return -EOPNOTSUPP;
    if (size != sizeof(struct drm_amdgpu_info_vram_gtt)) return -EINVAL;
    if(property(card,"local_mem_size",&bytes)) return -ENODATA;
    struct drm_amdgpu_info_vram_gtt *mem = out; memset(mem, 0, size);
    mem->vram_size = bytes; mem->vram_cpu_accessible_size = bytes;
    return 0;
}
int amdgpu_query_firmware_version(amdgpu_device_handle dev, unsigned type, unsigned ip, unsigned index, uint32_t *version, uint32_t *feature) {
    (void)dev; (void)type; (void)ip; (void)index; (void)version; (void)feature;
    return -EOPNOTSUPP;
}
const char *amdgpu_get_marketing_name(amdgpu_device_handle dev) { return card_of(dev) < 0 ? NULL : "AMD Instinct MI300X (mock)"; }
