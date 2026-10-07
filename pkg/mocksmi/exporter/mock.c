// AMD SMI ABI 27 backend for the unmodified AMD GPU Agent and exporter.
#include "amdsmi.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int gpu_count;
typedef struct {
  int temp, power, cap, util, used, total, ecc, gfx, mem;
  char name[128], uuid[128], bdf[64];
} state_t;
static _Thread_local state_t state;
static const char *root(void) {
  const char *p = getenv("MOCK_AMDSMI_STATE_DIR");
  return p ? p : "/var/lib/amd-gpu-mock/smi";
}
static int load(int i) {
  char path[512];
  snprintf(path, sizeof(path), "%s/gpu%d", root(), i);
  FILE *f = fopen(path, "r");
  if (!f)
    return 0;
  int n =
      fscanf(f, "%d %d %d %d %d %d %d %d %d\n%127[^\n]\n%127[^\n]\n%63[^\n]",
             &state.temp, &state.power, &state.cap, &state.util, &state.used,
             &state.total, &state.ecc, &state.gfx, &state.mem, state.name,
             state.uuid, state.bdf);
  fclose(f);
  return n == 12;
}

static int initialized;
static int index_of(amdsmi_processor_handle h) {
  uintptr_t i = (uintptr_t)h;
  return initialized && i >= 0x1000 && i < (uintptr_t)(0x1000 + gpu_count)
             ? (int)(i - 0x1000)
             : -1;
}
#define VALID(h, p)                                                            \
  if (index_of(h) < 0 || !(p))                                                 \
    return AMDSMI_STATUS_INVAL;                                                \
  if (!load(index_of(h)))                                                      \
  return AMDSMI_STATUS_NOT_FOUND
amdsmi_status_t amdsmi_init(uint64_t flags) {
  (void)flags;
  char path[512];
  snprintf(path, sizeof(path), "%s/count", root());
  FILE *f = fopen(path, "r");
  if (!f)
    return AMDSMI_STATUS_NOT_FOUND;
  int n = fscanf(f, "%d", &gpu_count);
  fclose(f);
  if (n != 1 || gpu_count < 1 || gpu_count > 64)
    return AMDSMI_STATUS_INVAL;
  initialized = 1;
  fprintf(stderr, "amd-gpu-mock: AMD SMI ABI 27 backend initialized\n");
  return 0;
}
amdsmi_status_t amdsmi_shut_down(void) {
  initialized = 0;
  return 0;
}
amdsmi_status_t amdsmi_get_socket_handles(uint32_t *n,
                                          amdsmi_socket_handle *h) {
  if (!n)
    return AMDSMI_STATUS_INVAL;
  if (h) {
    if (*n < 1)
      return AMDSMI_STATUS_OUT_OF_RESOURCES;
    h[0] = (void *)0xA000;
  }
  *n = 1;
  return 0;
}
amdsmi_status_t amdsmi_get_processor_handles(amdsmi_socket_handle s,
                                             uint32_t *n,
                                             amdsmi_processor_handle *h) {
  if (s != (void *)0xA000 || !n)
    return AMDSMI_STATUS_INVAL;
  if (h) {
    if (*n < (unsigned)gpu_count)
      return AMDSMI_STATUS_OUT_OF_RESOURCES;
    for (int i = 0; i < gpu_count; i++)
      h[i] = (void *)(uintptr_t)(0x1000 + i);
  }
  *n = gpu_count;
  return 0;
}
amdsmi_status_t amdsmi_get_processor_type(amdsmi_processor_handle h,
                                          processor_type_t *t) {
  VALID(h, t);
  *t = AMDSMI_PROCESSOR_TYPE_AMD_GPU;
  return 0;
}
amdsmi_status_t amdsmi_get_socket_info(amdsmi_socket_handle h, size_t n,
                                       char *name) {
  if (h != (void *)0xA000 || !name || !n)
    return AMDSMI_STATUS_INVAL;
  snprintf(name, n, "AMD mock socket");
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_device_bdf(amdsmi_processor_handle h,
                                          amdsmi_bdf_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  unsigned domain, bus, device, function;
  if (sscanf(state.bdf, "%x:%x:%x.%x", &domain, &bus, &device, &function) != 4)
    return AMDSMI_STATUS_INVAL;
  p->domain_number = domain;
  p->bus_number = bus;
  p->device_number = device;
  p->function_number = function;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_device_uuid(amdsmi_processor_handle h,
                                           unsigned int *n, char *p) {
  VALID(h, n);
  unsigned len = strlen(state.uuid) + 1;
  if (!p) {
    *n = len;
    return 0;
  }
  if (*n < len) {
    *n = len;
    return AMDSMI_STATUS_OUT_OF_RESOURCES;
  }
  snprintf(p, *n, "%s", state.uuid);
  *n = len;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_asic_info(amdsmi_processor_handle h,
                                         amdsmi_asic_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  snprintf(p->market_name, sizeof(p->market_name), "%s", state.name);
  snprintf(p->vendor_name, sizeof(p->vendor_name), "AMD");
  p->vendor_id = 0x1002;
  p->device_id = 0x74a1;
  p->oam_id = index_of(h);
  p->num_of_compute_units = 304;
  p->target_graphics_version = 90402;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_metrics_info(amdsmi_processor_handle h,
                                            amdsmi_gpu_metrics_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->common_header.structure_size = sizeof(*p);
  p->common_header.format_revision = 1;
  p->common_header.content_revision = 4;
  p->temperature_edge = state.temp;
  p->temperature_hotspot = state.temp + 6;
  p->temperature_mem = state.temp - 4;
  p->average_gfx_activity = state.util;
  p->average_socket_power = state.power;
  p->current_socket_power = state.power;
  p->current_gfxclk = state.gfx;
  for (unsigned i = 0; i < AMDSMI_MAX_NUM_GFX_CLKS; i++)
    p->current_gfxclks[i] = state.gfx;
  p->current_uclk = state.mem;
  p->pcie_link_width = 16;
  p->pcie_link_speed = 320;
  return 0;
}
amdsmi_status_t amdsmi_get_power_info(amdsmi_processor_handle h,
                                      amdsmi_power_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->socket_power = state.power;
  p->current_socket_power = state.power;
  p->average_socket_power = state.power;
  p->power_limit = state.cap;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_memory_total(amdsmi_processor_handle h,
                                            amdsmi_memory_type_t t,
                                            uint64_t *p) {
  VALID(h, p);
  if (t != AMDSMI_MEM_TYPE_VRAM)
    return AMDSMI_STATUS_NOT_SUPPORTED;
  *p = (uint64_t)state.total << 20;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_memory_usage(amdsmi_processor_handle h,
                                            amdsmi_memory_type_t t,
                                            uint64_t *p) {
  VALID(h, p);
  if (t != AMDSMI_MEM_TYPE_VRAM)
    return AMDSMI_STATUS_NOT_SUPPORTED;
  *p = (uint64_t)state.used << 20;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_vram_usage(amdsmi_processor_handle h,
                                          amdsmi_vram_usage_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->vram_total = state.total;
  p->vram_used = state.used;
  return 0;
}
amdsmi_status_t amdsmi_get_clock_info(amdsmi_processor_handle h,
                                      amdsmi_clk_type_t t,
                                      amdsmi_clk_info_t *p) {
  VALID(h, p);
  if (t != AMDSMI_CLK_TYPE_GFX && t != AMDSMI_CLK_TYPE_MEM)
    return AMDSMI_STATUS_NOT_SUPPORTED;
  memset(p, 0, sizeof(*p));
  p->clk = t == AMDSMI_CLK_TYPE_MEM ? state.mem : state.gfx;
  p->min_clk = p->clk;
  p->max_clk = t == AMDSMI_CLK_TYPE_MEM ? 1300 : 2100;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_kfd_info(amdsmi_processor_handle h,
                                        amdsmi_kfd_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->kfd_id = index_of(h);
  p->node_id = index_of(h) + 1;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_driver_info(amdsmi_processor_handle h,
                                           amdsmi_driver_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  snprintf(p->driver_name, sizeof(p->driver_name), "amdgpu");
  snprintf(p->driver_version, sizeof(p->driver_version), "mock");
  return 0;
}
amdsmi_status_t amdsmi_get_temp_metric(amdsmi_processor_handle h,
                                       amdsmi_temperature_type_t t,
                                       amdsmi_temperature_metric_t m,
                                       int64_t *p) {
  VALID(h, p);
  (void)t;
  if (m != AMDSMI_TEMP_CURRENT)
    return AMDSMI_STATUS_NOT_SUPPORTED;
  *p = (int64_t)state.temp * 1000;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_total_ecc_count(amdsmi_processor_handle h,
                                               amdsmi_error_count_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->uncorrectable_count = state.ecc;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_activity(amdsmi_processor_handle h,
                                        amdsmi_engine_usage_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->gfx_activity = state.util;
  return 0;
}

amdsmi_status_t amdsmi_get_gpu_board_info(amdsmi_processor_handle h,
                                          amdsmi_board_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  snprintf(p->model_number, sizeof(p->model_number), "%s", state.name);
  snprintf(p->product_name, sizeof(p->product_name), "%s", state.name);
  snprintf(p->product_serial, sizeof(p->product_serial), "MOCK-%04d",
           index_of(h));
  snprintf(p->manufacturer_name, sizeof(p->manufacturer_name), "AMD");
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_vram_info(amdsmi_processor_handle h,
                                         amdsmi_vram_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->vram_type = AMDSMI_VRAM_TYPE_HBM;
  p->vram_size = state.total;
  snprintf(p->vram_vendor, sizeof(p->vram_vendor), "AMD mock");
  return 0;
}
amdsmi_status_t amdsmi_get_power_cap_info(amdsmi_processor_handle h,
                                          uint32_t sensor,
                                          amdsmi_power_cap_info_t *p) {
  VALID(h, p);
  (void)sensor;
  memset(p, 0, sizeof(*p));
  p->power_cap = (uint64_t)state.cap * 1000000;
  p->default_power_cap = p->power_cap;
  p->max_power_cap = p->power_cap;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_ecc_count(amdsmi_processor_handle h,
                                         amdsmi_gpu_block_t block,
                                         amdsmi_error_count_t *p) {
  VALID(h, p);
  if (block != AMDSMI_GPU_BLOCK_UMC)
    return AMDSMI_STATUS_NOT_SUPPORTED;
  memset(p, 0, sizeof(*p));
  p->uncorrectable_count = state.ecc;
  return 0;
}
amdsmi_status_t amdsmi_get_gpu_enumeration_info(amdsmi_processor_handle h,
                                                amdsmi_enumeration_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->drm_render = 128 + index_of(h);
  p->drm_card = index_of(h);
  p->hsa_id = index_of(h);
  p->hip_id = index_of(h);
  snprintf(p->hip_uuid, sizeof(p->hip_uuid), "%s", state.uuid);
  return 0;
}
amdsmi_status_t amdsmi_get_pcie_info(amdsmi_processor_handle h,
                                     amdsmi_pcie_info_t *p) {
  VALID(h, p);
  memset(p, 0, sizeof(*p));
  p->pcie_static.max_pcie_width = 16;
  p->pcie_static.max_pcie_speed = 32;
  p->pcie_static.pcie_interface_version = 5;
  p->pcie_metric.pcie_width = 16;
  p->pcie_metric.pcie_speed = 32000;
  return 0;
}
