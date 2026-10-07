#include "amdsmi.h"
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
static void *reader(void *arg) {
  amdsmi_processor_handle h = arg;
  for (int i = 0; i < 500; i++) {
    amdsmi_power_info_t power;
    assert(amdsmi_get_power_info(h, &power) == AMDSMI_STATUS_SUCCESS);
    assert(power.socket_power == 230);
    assert(power.current_socket_power == 230);
    amdsmi_vram_usage_t memory;
    assert(amdsmi_get_gpu_vram_usage(h, &memory) == 0);
    assert(memory.vram_total == 196608 && memory.vram_used == 300);
  }
  return NULL;
}
int main(void) {
  assert(amdsmi_init(AMDSMI_INIT_AMD_GPUS) == 0);
  uint32_t n = 0;
  assert(amdsmi_get_socket_handles(&n, NULL) == 0 && n == 1);
  amdsmi_socket_handle socket;
  assert(amdsmi_get_socket_handles(&n, &socket) == 0);
  n = 0;
  assert(amdsmi_get_processor_handles(socket, &n, NULL) == 0 && n == 8);
  amdsmi_processor_handle handles[8];
  n = 1;
  assert(amdsmi_get_processor_handles(socket, &n, handles) ==
         AMDSMI_STATUS_OUT_OF_RESOURCES);
  n = 8;
  assert(amdsmi_get_processor_handles(socket, &n, handles) == 0);
  amdsmi_asic_info_t asic;
  assert(amdsmi_get_gpu_asic_info(handles[0], &asic) == 0 &&
         asic.device_id == 0x74a1);
  amdsmi_error_count_t ecc;
  assert(amdsmi_get_gpu_total_ecc_count(handles[0], &ecc) == 0 &&
         ecc.uncorrectable_count == 7);
  amdsmi_gpu_metrics_t bulk;
  assert(amdsmi_get_gpu_metrics_info(handles[0], &bulk) == 0);
  assert(bulk.current_gfxclks[0] == 500 && bulk.average_gfx_activity == 50);
  int64_t temp;
  assert(amdsmi_get_temp_metric(handles[0], AMDSMI_TEMPERATURE_TYPE_EDGE,
                                AMDSMI_TEMP_CURRENT, &temp) == 0 &&
         temp == 72000);
  unsigned len = 1;
  char guard[2] = {'x', 'y'};
  assert(amdsmi_get_gpu_device_uuid(handles[0], &len, guard) ==
             AMDSMI_STATUS_OUT_OF_RESOURCES &&
         guard[1] == 'y');
  assert(amdsmi_get_power_info((void *)0x123, NULL) == AMDSMI_STATUS_INVAL);
  assert(amdsmi_reset_gpu(handles[0]) == AMDSMI_STATUS_NOT_SUPPORTED);
  pthread_t threads[8];
  for (int i = 0; i < 8; i++)
    assert(pthread_create(&threads[i], NULL, reader, handles[i]) == 0);
  for (int i = 0; i < 8; i++)
    pthread_join(threads[i], NULL);
  assert(amdsmi_shut_down() == 0);
  puts("AMD SMI ABI: enumeration, units, structures, ECC, buffers, unsupported "
       "capabilities, concurrent calls PASS");
}
