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
    if(ok!=1 || !expected_major || !S_ISCHR(st.st_mode) || major(st.st_rdev) != expected_major || (minor(st.st_rdev) >= 64 && (minor(st.st_rdev) < 128 || minor(st.st_rdev) >= 192))) return -ENODEV;
    int card = (int)minor(st.st_rdev);
    if (card >= 128) card -= 128;
    if (!available(card)) return -ENODEV;
    *out = (amdgpu_device_handle)&handles[card];
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
    info->asic_id = device;
    // Family identification is deliberately not modeled by this capacity subset.
    info->family_id = 0;
    return 0;
}
int amdgpu_query_info(amdgpu_device_handle dev, unsigned id, unsigned size, void *out) {
    int card = card_of(dev); uint64_t bytes;
    if (card < 0 || !out) return -EINVAL;
    if (!available(card)) return -ENODEV;
    if (id != AMDGPU_INFO_MEMORY && id != AMDGPU_INFO_VRAM_GTT) return -EOPNOTSUPP;
    if(property(card,"local_mem_size",&bytes)) return -ENODATA;
    if (id == AMDGPU_INFO_VRAM_GTT) {
        struct drm_amdgpu_info_vram_gtt mem = {0};
        if (!size || size > sizeof(mem)) return -EINVAL;
        mem.vram_size = bytes; mem.vram_cpu_accessible_size = bytes;
        memcpy(out, &mem, size); return 0;
    }
    // MEMORY and VRAM_GTT have different UAPI structures. A short MEMORY
    // request is a prefix of memory_info, not a reinterpreted vram_gtt reply.
    struct drm_amdgpu_memory_info mem = {0};
    if (!size || size > sizeof(mem)) return -EINVAL;
    char path[1024], line[512]; unsigned long long used_mb;
    snprintf(path,sizeof(path),"%s/smi/gpu%d",root(),card);
    FILE *f = fopen(path,"r");
    if (!f) return -ENODATA;
    int ok = fgets(line,sizeof(line),f) && sscanf(line,"%*u %*u %*u %*u %llu",&used_mb)==1;
    fclose(f); if (!ok || used_mb > bytes / (1024*1024)) return -ENODATA;
    mem.vram.total_heap_size = bytes;
    mem.vram.usable_heap_size = bytes;
    mem.vram.heap_usage = used_mb * 1024 * 1024;
    mem.vram.max_allocation = bytes - mem.vram.heap_usage;
    // The optional backend models all profile VRAM as CPU-accessible and
    // does not model GTT. Neither field describes physical host allocation.
    mem.cpu_accessible_vram = mem.vram;
    memcpy(out, &mem, size); return 0;
}
int amdgpu_query_firmware_version(amdgpu_device_handle dev, unsigned type, unsigned ip, unsigned index, uint32_t *version, uint32_t *feature) {
    (void)dev; (void)type; (void)ip; (void)index; (void)version; (void)feature;
    return -EOPNOTSUPP;
}
const char *amdgpu_get_marketing_name(amdgpu_device_handle dev) {
    static _Thread_local char name[256];
    int card = card_of(dev);
    if (card < 0 || !available(card)) return NULL;
    char path[1024];
    snprintf(path, sizeof(path), "%s/smi/gpu%d", root(), card);
    FILE *f = fopen(path, "r");
    if (!f) return NULL;
    // Original renderer SMI format: version line followed by marketing name.
    if (!fgets(name, sizeof(name), f) || !fgets(name, sizeof(name), f)) {
        fclose(f); return NULL;
    }
    fclose(f); name[strcspn(name, "\r\n")] = 0; return name;
}
