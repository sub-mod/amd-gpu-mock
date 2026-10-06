// Mock libamd_smi.so — implements the 15 amdsmi_* functions that amd-smi calls.
//
// Reads GPU configuration from MOCK_AMDSMI_CONFIG (YAML parsed at init).
// For this initial version, config is compiled in from the profile defaults.
// The mock answers the same function signatures as the real libamd_smi.so
// so that the real amd-smi Python CLI loads it without modification.
//
// Build: gcc -shared -fPIC -o libamd_smi.so mock_amdsmi.c -DMOCK_GPU_COUNT=8

#include "amdsmi_types.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

#ifndef MOCK_GPU_COUNT
#define MOCK_GPU_COUNT 8
#endif

// Internal GPU state — populated at init from environment or defaults.
typedef struct {
    int index;
    char name[64];
    uint32_t vendor_id;
    uint32_t device_id;
    uint16_t oam_id;
    uint16_t num_compute_units;
    uint64_t gfx_target_version;
    uint32_t domain;
    uint32_t bus;
    uint32_t device;
    uint32_t function;
    int64_t temperature_mc;      // millidegrees C
    uint32_t power_w;
    uint32_t power_limit_w;
    uint32_t gfx_activity;
    uint32_t umc_activity;
    uint32_t mm_activity;
    uint64_t vram_total;
    uint64_t vram_used;
    uint32_t ecc_correctable;
    uint32_t ecc_uncorrectable;
    uint32_t fan_speed_pct;
    char compute_partition[32];
    char memory_partition[32];
} mock_gpu_t;

static mock_gpu_t g_gpus[MOCK_GPU_COUNT];
static int g_gpu_count = MOCK_GPU_COUNT;
static int g_initialized = 0;

// Dummy handles — we use the GPU index offset from a base pointer value.
static uintptr_t g_socket_handle = 0xA000;

// BDF addresses for 8 GPUs (MI300X default layout)
static const uint32_t default_buses[] = {0x05, 0x26, 0x46, 0x65, 0x85, 0xa6, 0xc6, 0xe5};

static void init_defaults(void) {
    const char *name = getenv("MOCK_AMDSMI_GPU_NAME");
    if (!name) name = "AMD Instinct MI300X";

    const char *count_str = getenv("MOCK_AMDSMI_GPU_COUNT");
    if (count_str) {
        int c = atoi(count_str);
        if (c > 0 && c <= MOCK_GPU_COUNT) g_gpu_count = c;
    }

    for (int i = 0; i < g_gpu_count; i++) {
        mock_gpu_t *g = &g_gpus[i];
        g->index = i;
        strncpy(g->name, name, sizeof(g->name) - 1);
        g->vendor_id = 0x1002;
        g->device_id = 0x74a1;
        g->oam_id = i;
        g->num_compute_units = 304;
        g->gfx_target_version = 0x090400;  // gfx942
        g->domain = 0;
        g->bus = (i < 8) ? default_buses[i] : (0x05 + i * 0x20);
        g->device = 0;
        g->function = 0;
        g->temperature_mc = 49000;  // 49°C in millidegrees
        g->power_w = 183;
        g->power_limit_w = 750;
        g->gfx_activity = 0;
        g->umc_activity = 0;
        g->mm_activity = 0;
        g->vram_total = 206158430208ULL;  // ~192 GB
        g->vram_used = 314572800ULL;      // ~300 MB
        g->ecc_correctable = 0;
        g->ecc_uncorrectable = 0;
        g->fan_speed_pct = 0;
        strncpy(g->compute_partition, "SPX", sizeof(g->compute_partition));
        strncpy(g->memory_partition, "NPS1", sizeof(g->memory_partition));
    }
}

// === Public API — matches real libamd_smi.so signatures ===

amdsmi_status_t amdsmi_init(uint64_t init_flags) {
    if (g_initialized) return AMDSMI_STATUS_SUCCESS;
    init_defaults();
    g_initialized = 1;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_shut_down(void) {
    g_initialized = 0;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_socket_handles(uint32_t *socket_count,
                                           amdsmi_socket_handle *socket_handles) {
    if (!g_initialized) return AMDSMI_STATUS_API_FAILED;
    if (socket_count) *socket_count = 1;
    if (socket_handles) socket_handles[0] = (amdsmi_socket_handle)g_socket_handle;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_processor_handles(amdsmi_socket_handle socket,
                                              uint32_t *processor_count,
                                              amdsmi_processor_handle *processor_handles) {
    if (!g_initialized) return AMDSMI_STATUS_API_FAILED;
    if (processor_count) *processor_count = g_gpu_count;
    if (processor_handles) {
        for (int i = 0; i < g_gpu_count; i++) {
            processor_handles[i] = (amdsmi_processor_handle)(uintptr_t)(0x1000 + i);
        }
    }
    return AMDSMI_STATUS_SUCCESS;
}

static mock_gpu_t* resolve_gpu(amdsmi_processor_handle handle) {
    int idx = (int)((uintptr_t)handle - 0x1000);
    if (idx < 0 || idx >= g_gpu_count) return NULL;
    return &g_gpus[idx];
}

amdsmi_status_t amdsmi_get_gpu_device_bdf(amdsmi_processor_handle handle,
                                           amdsmi_bdf_t *bdf) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !bdf) return AMDSMI_STATUS_INVAL;
    bdf->domain_number = g->domain;
    bdf->bus_number = g->bus;
    bdf->device_number = g->device;
    bdf->function_number = g->function;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_asic_info(amdsmi_processor_handle handle,
                                          amdsmi_asic_info_t *info) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    strncpy(info->market_name, g->name, AMDSMI_MAX_STRING_LENGTH - 1);
    info->vendor_id = g->vendor_id;
    strncpy(info->vendor_name, "Advanced Micro Devices Inc. [AMD/ATI]",
            AMDSMI_MAX_STRING_LENGTH - 1);
    info->device_id = g->device_id;
    info->oam_id = g->oam_id;
    info->num_of_compute_units = g->num_compute_units;
    info->target_graphics_version = g->gfx_target_version;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_temp_metric(amdsmi_processor_handle handle,
                                        amdsmi_temperature_type_t type,
                                        amdsmi_temperature_metric_t metric,
                                        int64_t *value) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !value) return AMDSMI_STATUS_INVAL;
    if (metric == AMDSMI_TEMP_CURRENT) {
        *value = g->temperature_mc;
    } else if (metric == AMDSMI_TEMP_MAX) {
        *value = 110000;  // 110°C shutdown
    } else {
        *value = 0;
    }
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_power_info(amdsmi_processor_handle handle,
                                       amdsmi_power_info_t *info) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    info->current_socket_power = g->power_w;
    info->average_socket_power = g->power_w;
    info->power_limit = g->power_limit_w;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_activity(amdsmi_processor_handle handle,
                                         amdsmi_engine_usage_t *info) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !info) return AMDSMI_STATUS_INVAL;
    info->gfx_activity = g->gfx_activity;
    info->umc_activity = g->umc_activity;
    info->mm_activity = g->mm_activity;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_total_ecc_count(amdsmi_processor_handle handle,
                                                amdsmi_error_count_t *ec) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !ec) return AMDSMI_STATUS_INVAL;
    ec->correctable_count = g->ecc_correctable;
    ec->uncorrectable_count = g->ecc_uncorrectable;
    ec->deferred_count = 0;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_memory_total(amdsmi_processor_handle handle,
                                             amdsmi_memory_type_t type,
                                             uint64_t *total) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !total) return AMDSMI_STATUS_INVAL;
    *total = g->vram_total;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_memory_usage(amdsmi_processor_handle handle,
                                             amdsmi_memory_type_t type,
                                             uint64_t *used) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !used) return AMDSMI_STATUS_INVAL;
    *used = g->vram_used;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_fan_speed(amdsmi_processor_handle handle,
                                          uint32_t sensor_idx,
                                          int64_t *speed) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !speed) return AMDSMI_STATUS_INVAL;
    *speed = g->fan_speed_pct;
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_compute_partition(amdsmi_processor_handle handle,
                                                  char *partition,
                                                  uint32_t len) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !partition || len == 0) return AMDSMI_STATUS_INVAL;
    strncpy(partition, g->compute_partition, len - 1);
    partition[len - 1] = '\0';
    return AMDSMI_STATUS_SUCCESS;
}

amdsmi_status_t amdsmi_get_gpu_memory_partition(amdsmi_processor_handle handle,
                                                 char *partition,
                                                 uint32_t len) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !partition || len == 0) return AMDSMI_STATUS_INVAL;
    strncpy(partition, g->memory_partition, len - 1);
    partition[len - 1] = '\0';
    return AMDSMI_STATUS_SUCCESS;
}

// Additional functions amd-smi calls during startup.

// amdsmi_get_lib_version — returns the mock library version.
typedef struct {
    uint32_t year;
    uint32_t major;
    uint32_t minor;
    uint32_t release;
    char build[64];
} amdsmi_version_t;

amdsmi_status_t amdsmi_get_lib_version(amdsmi_version_t *version) {
    if (!version) return AMDSMI_STATUS_INVAL;
    version->year = 24;
    version->major = 27;
    version->minor = 0;
    version->release = 0;
    strncpy(version->build, "mock", sizeof(version->build));
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_processor_handles_by_type — returns handles filtered by type.
// Type 1 = AMD_GPU, Type 2 = AMD_CPU.
amdsmi_status_t amdsmi_get_processor_handles_by_type(
        amdsmi_socket_handle socket,
        uint32_t processor_type,
        amdsmi_processor_handle *handles,
        uint32_t *count) {
    if (!count) return AMDSMI_STATUS_INVAL;

    if (processor_type == 1) {
        // AMD_GPU
        *count = g_gpu_count;
        if (handles) {
            for (int i = 0; i < g_gpu_count; i++) {
                handles[i] = (amdsmi_processor_handle)(uintptr_t)(0x1000 + i);
            }
        }
        return AMDSMI_STATUS_SUCCESS;
    }

    // AMD_CPU or other — no mock CPUs
    *count = 0;
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_processor_type — returns the type of a processor handle.
amdsmi_status_t amdsmi_get_processor_type(amdsmi_processor_handle handle,
                                           uint32_t *type) {
    if (!type) return AMDSMI_STATUS_INVAL;
    *type = 1; // AMDSMI_PROCESSOR_TYPE_AMD_GPU
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_gpu_device_uuid — returns the UUID string.
amdsmi_status_t amdsmi_get_gpu_device_uuid(amdsmi_processor_handle handle,
                                            unsigned int *uuid_length,
                                            char *uuid) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g) return AMDSMI_STATUS_INVAL;
    if (uuid && uuid_length && *uuid_length > 0) {
        snprintf(uuid, *uuid_length, "GPU-amd-mock-%04d", g->index);
    }
    if (uuid_length) *uuid_length = 20;
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_gpu_vram_usage — returns used/total VRAM.
typedef struct {
    uint64_t vram_total;
    uint64_t vram_used;
} amdsmi_vram_usage_t;

amdsmi_status_t amdsmi_get_gpu_vram_usage(amdsmi_processor_handle handle,
                                           amdsmi_vram_usage_t *usage) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !usage) return AMDSMI_STATUS_INVAL;
    usage->vram_total = g->vram_total;
    usage->vram_used = g->vram_used;
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_energy_count — returns energy counter.
typedef struct {
    uint64_t power;
    float counter_resolution;
    uint64_t timestamp;
} amdsmi_energy_count_t;

amdsmi_status_t amdsmi_get_energy_count(amdsmi_processor_handle handle,
                                         amdsmi_energy_count_t *energy) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !energy) return AMDSMI_STATUS_INVAL;
    energy->power = g->power_w * 1000000ULL; // microwatts
    energy->counter_resolution = 15.3f;
    energy->timestamp = 0;
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_clock_info — returns clock frequencies.
typedef struct {
    uint32_t clk;
    uint32_t clk_deep_sleep;
    uint32_t min_clk;
    uint32_t max_clk;
} amdsmi_clk_info_t;

amdsmi_status_t amdsmi_get_clock_info(amdsmi_processor_handle handle,
                                       uint32_t clk_type,
                                       amdsmi_clk_info_t *info) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    if (clk_type == 0) { // GFX
        info->clk = 500;
        info->min_clk = 500;
        info->max_clk = 2100;
    } else if (clk_type == 3) { // MEM
        info->clk = 1300;
        info->min_clk = 900;
        info->max_clk = 1300;
    }
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_pcie_info — returns PCIe link info.
typedef struct {
    struct {
        uint32_t max_pcie_width;
        uint32_t max_pcie_speed;
        uint32_t pcie_interface_version;
        uint32_t slot_type;
    } pcie_static;
    struct {
        uint32_t pcie_width;
        uint32_t pcie_speed;
        uint32_t pcie_bandwidth;
    } pcie_metric;
} amdsmi_pcie_info_t;

amdsmi_status_t amdsmi_get_pcie_info(amdsmi_processor_handle handle,
                                      amdsmi_pcie_info_t *info) {
    if (!info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    info->pcie_static.max_pcie_width = 16;
    info->pcie_static.max_pcie_speed = 32000; // Gen5
    info->pcie_static.pcie_interface_version = 5;
    info->pcie_metric.pcie_width = 16;
    info->pcie_metric.pcie_speed = 32000;
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_gpu_driver_info — returns driver info.
typedef struct {
    char driver_name[64];
    char driver_version[64];
    char driver_date[64];
} amdsmi_driver_info_t;

amdsmi_status_t amdsmi_get_gpu_driver_info(amdsmi_processor_handle handle,
                                            amdsmi_driver_info_t *info) {
    if (!info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    strncpy(info->driver_name, "amdgpu", sizeof(info->driver_name));
    strncpy(info->driver_version, "6.19.4", sizeof(info->driver_version));
    strncpy(info->driver_date, "2026-01-01", sizeof(info->driver_date));
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_gpu_kfd_info — returns KFD node info.
typedef struct {
    uint64_t kfd_id;
    uint32_t node_id;
    uint32_t current_partition_id;
} amdsmi_kfd_info_t;

amdsmi_status_t amdsmi_get_gpu_kfd_info(amdsmi_processor_handle handle,
                                         amdsmi_kfd_info_t *info) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !info) return AMDSMI_STATUS_INVAL;
    info->kfd_id = g->index;
    info->node_id = g->index + 1;
    info->current_partition_id = 0;
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_socket_info — returns socket name.
typedef struct {
    char name[128];
} amdsmi_sock_info_t;

amdsmi_status_t amdsmi_get_socket_info(amdsmi_socket_handle socket,
                                        amdsmi_sock_info_t *info) {
    if (!info) return AMDSMI_STATUS_INVAL;
    strncpy(info->name, "Socket 0", sizeof(info->name));
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_gpu_vbios_info — returns VBIOS info.
typedef struct {
    char name[64];
    char build_date[64];
    char part_number[64];
    char version[64];
} amdsmi_vbios_info_t;

amdsmi_status_t amdsmi_get_gpu_vbios_info(amdsmi_processor_handle handle,
                                           amdsmi_vbios_info_t *info) {
    if (!info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    strncpy(info->name, "AMD Instinct MI300X D47100 VBIOS", sizeof(info->name));
    strncpy(info->version, "036.042.001.040.046740", sizeof(info->version));
    strncpy(info->build_date, "2025/01/01", sizeof(info->build_date));
    strncpy(info->part_number, "113-D4710100-041", sizeof(info->part_number));
    return AMDSMI_STATUS_SUCCESS;
}

// amdsmi_get_gpu_board_info — returns board info.
typedef struct {
    char model_number[128];
    char product_serial[64];
    char fru_id[64];
    char product_name[128];
    char manufacturer_name[64];
} amdsmi_board_info_t;

amdsmi_status_t amdsmi_get_gpu_board_info(amdsmi_processor_handle handle,
                                           amdsmi_board_info_t *info) {
    mock_gpu_t *g = resolve_gpu(handle);
    if (!g || !info) return AMDSMI_STATUS_INVAL;
    memset(info, 0, sizeof(*info));
    strncpy(info->product_name, g->name, sizeof(info->product_name));
    strncpy(info->manufacturer_name, "AMD", sizeof(info->manufacturer_name));
    strncpy(info->product_serial, "MOCK00000000", sizeof(info->product_serial));
    return AMDSMI_STATUS_SUCCESS;
}
