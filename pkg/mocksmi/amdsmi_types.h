// Mock AMD SMI types — matches the real amdsmi.h type definitions.
// Only the types needed for the 15 functions amd-smi calls.
// Source: ROCm/amdsmi amdsmi.h

#ifndef MOCK_AMDSMI_TYPES_H
#define MOCK_AMDSMI_TYPES_H

#include <stdint.h>
#include <stddef.h>

// Status codes — same values as real AMD SMI
typedef enum {
    AMDSMI_STATUS_SUCCESS = 0,
    AMDSMI_STATUS_INVAL = 1,
    AMDSMI_STATUS_NOT_SUPPORTED = 2,
    AMDSMI_STATUS_NOT_FOUND = 8,
    AMDSMI_STATUS_NO_PERM = 5,
    AMDSMI_STATUS_API_FAILED = 15,
} amdsmi_status_t;

// Init flags
typedef enum {
    AMDSMI_INIT_ALL_PROCESSORS = 0x0,
    AMDSMI_INIT_AMD_GPUS = 0x1,
    AMDSMI_INIT_AMD_CPUS = 0x2,
    AMDSMI_INIT_NON_AMD_GPUS = 0x4,
    AMDSMI_INIT_NON_AMD_CPUS = 0x8,
} amdsmi_init_flags_t;

// Processor handle — opaque pointer
typedef void* amdsmi_processor_handle;
typedef void* amdsmi_socket_handle;

// Temperature types
typedef enum {
    TEMPERATURE_TYPE_EDGE = 0,
    TEMPERATURE_TYPE_HOTSPOT = 1,
    TEMPERATURE_TYPE_JUNCTION = TEMPERATURE_TYPE_HOTSPOT,
    TEMPERATURE_TYPE_VRAM = 2,
    TEMPERATURE_TYPE_HBM_0 = 3,
    TEMPERATURE_TYPE_HBM_1 = 4,
    TEMPERATURE_TYPE_HBM_2 = 5,
    TEMPERATURE_TYPE_HBM_3 = 6,
    TEMPERATURE_TYPE_PLX = 7,
} amdsmi_temperature_type_t;

// Temperature metrics
typedef enum {
    AMDSMI_TEMP_CURRENT = 0,
    AMDSMI_TEMP_MAX = 1,
    AMDSMI_TEMP_MIN = 2,
    AMDSMI_TEMP_MAX_HYST = 3,
    AMDSMI_TEMP_MIN_HYST = 4,
    AMDSMI_TEMP_CRITICAL = 5,
    AMDSMI_TEMP_CRITICAL_HYST = 6,
    AMDSMI_TEMP_EMERGENCY = 7,
    AMDSMI_TEMP_EMERGENCY_HYST = 8,
    AMDSMI_TEMP_CRIT_MIN = 9,
    AMDSMI_TEMP_CRIT_MIN_HYST = 10,
    AMDSMI_TEMP_OFFSET = 11,
    AMDSMI_TEMP_LOWEST = 12,
    AMDSMI_TEMP_HIGHEST = 13,
} amdsmi_temperature_metric_t;

// Memory types
typedef enum {
    AMDSMI_MEM_TYPE_VRAM = 0,
    AMDSMI_MEM_TYPE_VIS_VRAM = 1,
    AMDSMI_MEM_TYPE_GTT = 2,
} amdsmi_memory_type_t;

// BDF info
typedef struct {
    uint64_t function_number;
    uint64_t device_number;
    uint64_t bus_number;
    uint64_t domain_number;
} amdsmi_bdf_t;

// ASIC info
#define AMDSMI_MAX_STRING_LENGTH 64
typedef struct {
    char market_name[AMDSMI_MAX_STRING_LENGTH];
    uint32_t vendor_id;
    char vendor_name[AMDSMI_MAX_STRING_LENGTH];
    uint32_t subvendor_id;
    uint32_t device_id;
    uint32_t rev_id;
    char asic_serial[AMDSMI_MAX_STRING_LENGTH];
    uint16_t oam_id;
    uint16_t num_of_compute_units;
    uint64_t target_graphics_version;
} amdsmi_asic_info_t;

// Power info
typedef struct {
    uint32_t current_socket_power;
    uint32_t average_socket_power;
    uint32_t gfx_voltage;
    uint32_t soc_voltage;
    uint32_t mem_voltage;
    uint32_t power_limit;
} amdsmi_power_info_t;

// GPU activity
typedef struct {
    uint32_t gfx_activity;
    uint32_t umc_activity;
    uint32_t mm_activity;
} amdsmi_engine_usage_t;

// ECC count
typedef struct {
    uint32_t correctable_count;
    uint32_t uncorrectable_count;
    uint32_t deferred_count;
} amdsmi_error_count_t;

#endif // MOCK_AMDSMI_TYPES_H
