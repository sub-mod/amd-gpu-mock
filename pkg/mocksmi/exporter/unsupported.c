// Generated from the pinned GPU-only AMD SMI header.
#include "amdsmi.h"
amdsmi_status_t amdsmi_get_node_handle(amdsmi_processor_handle processor_handle,
                                       amdsmi_node_handle *node_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_processor_info(amdsmi_processor_handle processor_handle, size_t len,
                          char *name) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_processor_count_from_handles(
    amdsmi_processor_handle *processor_handles, uint32_t *processor_count,
    uint32_t *nr_cpusockets, uint32_t *nr_cpucores, uint32_t *nr_gpus) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_processor_handles_by_type(
    amdsmi_socket_handle socket_handle, amdsmi_processor_type_t processor_type,
    amdsmi_processor_handle *processor_handles, uint32_t *processor_count) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_processor_handle_from_bdf(
    amdsmi_bdf_t bdf, amdsmi_processor_handle *processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_device_cuid(amdsmi_processor_handle processor_handle,
                           unsigned int *cuid_length, char *cuid) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_cpu_affinity_with_scope(amdsmi_processor_handle processor_handle,
                                   uint32_t cpu_set_size, uint64_t *cpu_set,
                                   amdsmi_affinity_scope_t scope) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_virtualization_mode(amdsmi_processor_handle processor_handle,
                                   amdsmi_virtualization_mode_t *mode) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_processor_handles(amdsmi_socket_handle socket_handle,
                                 uint32_t *processor_count,
                                 amdsmi_processor_handle *processor_handles) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_device_bdf(amdsmi_processor_handle processor_handle,
                          amdsmi_bdf_t *bdf) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_id(amdsmi_processor_handle processor_handle,
                                  uint16_t *id) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_revision(amdsmi_processor_handle processor_handle,
                        uint16_t *revision) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_vendor_name(amdsmi_processor_handle processor_handle, char *name,
                           size_t len) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_vram_vendor(amdsmi_processor_handle processor_handle,
                           char *brand, uint32_t len) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_subsystem_id(amdsmi_processor_handle processor_handle,
                            uint16_t *id) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_subsystem_name(amdsmi_processor_handle processor_handle,
                              char *name, size_t len) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_pci_bandwidth(amdsmi_processor_handle processor_handle,
                             amdsmi_pcie_bandwidth_t *bandwidth) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_bdf_id(amdsmi_processor_handle processor_handle,
                                      uint64_t *bdfid) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_topo_numa_affinity(amdsmi_processor_handle processor_handle,
                                  int32_t *numa_node) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_pci_throughput(amdsmi_processor_handle processor_handle,
                              uint64_t *sent, uint64_t *received,
                              uint64_t *max_pkt_sz) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_pci_replay_counter(amdsmi_processor_handle processor_handle,
                                  uint64_t *counter) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_pci_bandwidth(amdsmi_processor_handle processor_handle,
                             uint64_t bw_bitmask) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_energy_count(amdsmi_processor_handle processor_handle,
                        uint64_t *energy_accumulator, float *counter_resolution,
                        uint64_t *timestamp) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_power_cap(amdsmi_processor_handle processor_handle,
                                     uint32_t sensor_ind, uint64_t cap) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_power_profile(amdsmi_processor_handle processor_handle,
                             uint32_t reserved,
                             amdsmi_power_profile_preset_masks_t profile) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_supported_power_cap(amdsmi_processor_handle processor_handle,
                               uint32_t *sensor_count, uint32_t *sensor_inds,
                               amdsmi_power_cap_type_t *sensor_types) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_cpu_socket_power(amdsmi_processor_handle processor_handle,
                            uint32_t *ppower) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_cpu_socket_power_cap(amdsmi_processor_handle processor_handle,
                                uint32_t *pcap) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_cpu_socket_power_cap_max(amdsmi_processor_handle processor_handle,
                                    uint32_t *pmax) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_cpu_pwr_svi_telemetry_all_rails(
    amdsmi_processor_handle processor_handle, uint32_t *power) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_cpu_socket_power_cap(amdsmi_processor_handle processor_handle,
                                uint32_t pcap) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_cpu_pwr_efficiency_mode(amdsmi_processor_handle processor_handle,
                                   uint8_t power_efficiency_mode,
                                   uint32_t *utilization, uint32_t *ppt_limit) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_cpu_pwr_efficiency_mode(amdsmi_processor_handle processor_handle,
                                   uint32_t *power_efficiency_mode,
                                   uint32_t *utilization, uint32_t *ppt_limit) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_cpu_core_ccd_power(amdsmi_processor_handle processor_handle,
                              uint32_t *power) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_bad_page_info(amdsmi_processor_handle processor_handle,
                             uint32_t *num_pages,
                             amdsmi_retired_page_record_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_bad_page_threshold(amdsmi_processor_handle processor_handle,
                                  uint32_t *threshold) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_gpu_validate_ras_eeprom(amdsmi_processor_handle processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_ras_block_features_enabled(
    amdsmi_processor_handle processor_handle, amdsmi_gpu_block_t block,
    amdsmi_ras_err_state_t *state) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_memory_reserved_pages(amdsmi_processor_handle processor_handle,
                                     uint32_t *num_pages,
                                     amdsmi_retired_page_record_t *records) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_fan_rpms(amdsmi_processor_handle processor_handle,
                        uint32_t sensor_ind, int64_t *speed) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_fan_speed(amdsmi_processor_handle processor_handle,
                         uint32_t sensor_ind, int64_t *speed) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_fan_speed_max(amdsmi_processor_handle processor_handle,
                             uint32_t sensor_ind, uint64_t *max_speed) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_cache_info(amdsmi_processor_handle processor_handle,
                          amdsmi_gpu_cache_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_volt_metric(amdsmi_processor_handle processor_handle,
                           amdsmi_voltage_type_t sensor_type,
                           amdsmi_voltage_metric_t metric, int64_t *voltage) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_reset_gpu_fan(amdsmi_processor_handle processor_handle,
                                     uint32_t sensor_ind) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_fan_speed(amdsmi_processor_handle processor_handle,
                         uint32_t sensor_ind, uint64_t speed) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_busy_percent(amdsmi_processor_handle processor_handle,
                            uint32_t *gpu_busy_percent) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_vcn_busy_percent(amdsmi_processor_handle processor_handle,
                            uint32_t *vcn_busy_percent) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_utilization_count(
    amdsmi_processor_handle processor_handle,
    amdsmi_utilization_counter_t utilization_counters[], uint32_t count,
    uint64_t *timestamp) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_perf_level(amdsmi_processor_handle processor_handle,
                          amdsmi_dev_perf_level_t *perf) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_perf_determinism_mode(amdsmi_processor_handle processor_handle,
                                     uint64_t clkvalue) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_overdrive_level(amdsmi_processor_handle processor_handle,
                               uint32_t *od) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_mem_overdrive_level(amdsmi_processor_handle processor_handle,
                                   uint32_t *od) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_clk_freq(amdsmi_processor_handle processor_handle,
                                    amdsmi_clk_type_t clk_type,
                                    amdsmi_frequencies_t *f) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_reset_gpu(amdsmi_processor_handle processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_od_volt_info(amdsmi_processor_handle processor_handle,
                            amdsmi_od_volt_freq_data_t *odv) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_metrics_header_info(amdsmi_processor_handle processor_handle,
                                   amd_metrics_table_header_t *header_value) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_partition_metrics_info(amdsmi_processor_handle processor_handle,
                                      amdsmi_gpu_metrics_t *pgpu_metrics) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_pm_metrics_info(amdsmi_processor_handle processor_handle,
                               amdsmi_name_value_t **pm_metrics,
                               uint32_t *num_of_metrics) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_reg_table_info(
    amdsmi_processor_handle processor_handle, amdsmi_reg_type_t reg_type,
    amdsmi_name_value_t **reg_metrics, uint32_t *num_of_metrics) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_gpu_clk_limit(
    amdsmi_processor_handle processor_handle, amdsmi_clk_type_t clk_type,
    amdsmi_clk_limit_type_t limit_type, uint64_t clk_value) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_od_clk_info(amdsmi_processor_handle processor_handle,
                           amdsmi_freq_ind_t level, uint64_t clkvalue,
                           amdsmi_clk_type_t clkType) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_od_volt_info(amdsmi_processor_handle processor_handle,
                            uint32_t vpoint, uint64_t clkvalue,
                            uint64_t voltvalue) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_od_volt_curve_regions(amdsmi_processor_handle processor_handle,
                                     uint32_t *num_regions,
                                     amdsmi_freq_volt_region_t *buffer) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_power_profile_presets(amdsmi_processor_handle processor_handle,
                                     uint32_t sensor_ind,
                                     amdsmi_power_profile_status_t *status) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_perf_level(amdsmi_processor_handle processor_handle,
                          amdsmi_dev_perf_level_t perf_lvl) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_overdrive_level(amdsmi_processor_handle processor_handle,
                               uint32_t od) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_clk_freq(amdsmi_processor_handle processor_handle,
                                    amdsmi_clk_type_t clk_type,
                                    uint64_t freq_bitmask) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_soc_pstate(amdsmi_processor_handle processor_handle,
                                      amdsmi_dpm_policy_t *policy) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_soc_pstate(amdsmi_processor_handle processor_handle,
                                      uint32_t policy_id) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_xgmi_plpd(amdsmi_processor_handle processor_handle,
                                     amdsmi_dpm_policy_t *xgmi_plpd) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_xgmi_plpd(amdsmi_processor_handle processor_handle,
                                     uint32_t policy_id) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_process_isolation(amdsmi_processor_handle processor_handle,
                                 uint32_t *pisolate) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_process_isolation(amdsmi_processor_handle processor_handle,
                                 uint32_t pisolate) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_clean_gpu_local_data(amdsmi_processor_handle processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_alloc_fabric_telemetry(amdsmi_processor_handle processor_handle,
                              uint32_t category_mask,
                              amdsmi_fabric_telemetry_t **telemetry) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_fabric_telemetry_data(amdsmi_processor_handle processor_handle,
                                 amdsmi_fabric_telemetry_t *telemetry) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_fabric_telem_id_to_string(uint64_t telem_id,
                                                 const char **telem_name) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_free_fabric_telemetry(amdsmi_processor_handle processor_handle,
                             amdsmi_fabric_telemetry_t *telemetry) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_fabric_info(amdsmi_processor_handle processor_handle,
                           amdsmi_fabric_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_lib_version(amdsmi_version_t *version) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_ecc_enabled(amdsmi_processor_handle processor_handle,
                           uint64_t *enabled_blocks) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_afids_from_cper(char *cper_buffer, uint32_t buf_size,
                                           uint64_t *afids,
                                           uint32_t *num_afids) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_ras_feature_info(amdsmi_processor_handle processor_handle,
                                amdsmi_ras_feature_t *ras_feature) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_cper_entries(amdsmi_processor_handle processor_handle,
                            uint32_t severity_mask, char *cper_data,
                            uint64_t *buf_size, amdsmi_cper_hdr_t **cper_hdrs,
                            uint64_t *entry_count, uint64_t *cursor) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_ecc_status(amdsmi_processor_handle processor_handle,
                          amdsmi_gpu_block_t block,
                          amdsmi_ras_err_state_t *state) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_status_code_to_string(amdsmi_status_t status,
                                             const char **status_string) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_gpu_counter_group_supported(amdsmi_processor_handle processor_handle,
                                   amdsmi_event_group_t group) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_gpu_create_counter(amdsmi_processor_handle processor_handle,
                          amdsmi_event_type_t type,
                          amdsmi_event_handle_t *evnt_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_gpu_destroy_counter(amdsmi_event_handle_t evnt_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_gpu_control_counter(amdsmi_event_handle_t evt_handle,
                                           amdsmi_counter_command_t cmd,
                                           void *cmd_args) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_gpu_read_counter(amdsmi_event_handle_t evt_handle,
                                        amdsmi_counter_value_t *value) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_available_counters(amdsmi_processor_handle processor_handle,
                                  amdsmi_event_group_t grp,
                                  uint32_t *available) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_compute_process_info(amdsmi_process_info_t *procs,
                                    uint32_t *num_items) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_compute_process_info_by_pid(uint32_t pid,
                                           amdsmi_process_info_t *proc) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_compute_process_gpus(uint32_t pid,
                                                    uint32_t *dv_indices,
                                                    uint32_t *num_devices) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_gpu_xgmi_error_status(amdsmi_processor_handle processor_handle,
                             amdsmi_xgmi_status_t *status) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_reset_gpu_xgmi_error(amdsmi_processor_handle processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_xgmi_info(amdsmi_processor_handle processor_handle,
                                     amdsmi_xgmi_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_xgmi_link_status(amdsmi_processor_handle processor_handle,
                                amdsmi_xgmi_link_status_t *link_status) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_link_metrics(amdsmi_processor_handle processor_handle,
                        amdsmi_link_metrics_t *link_metrics) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_topo_get_numa_node_number(amdsmi_processor_handle processor_handle,
                                 uint32_t *numa_node) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_topo_get_link_weight(amdsmi_processor_handle processor_handle_src,
                            amdsmi_processor_handle processor_handle_dst,
                            uint64_t *weight) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_minmax_bandwidth_between_processors(
    amdsmi_processor_handle processor_handle_src,
    amdsmi_processor_handle processor_handle_dst, uint64_t *min_bandwidth,
    uint64_t *max_bandwidth) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_topo_get_link_type(amdsmi_processor_handle processor_handle_src,
                          amdsmi_processor_handle processor_handle_dst,
                          uint64_t *hops, amdsmi_link_type_t *type) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_link_topology_nearest(
    amdsmi_processor_handle processor_handle, amdsmi_link_type_t link_type,
    amdsmi_topology_nearest_t *topology_nearest_info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_is_P2P_accessible(amdsmi_processor_handle processor_handle_src,
                         amdsmi_processor_handle processor_handle_dst,
                         _Bool *accessible) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_topo_get_p2p_status(amdsmi_processor_handle processor_handle_src,
                           amdsmi_processor_handle processor_handle_dst,
                           amdsmi_link_type_t *type,
                           amdsmi_p2p_capability_t *cap) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_compute_partition(amdsmi_processor_handle processor_handle,
                                 char *compute_partition, uint32_t len) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_gpu_compute_partition(
    amdsmi_processor_handle processor_handle,
    amdsmi_compute_partition_type_t compute_partition) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_compute_partition_mem_alloc_mode(
    amdsmi_processor_handle processor_handle,
    amdsmi_compute_partition_mem_alloc_mode_t *mode) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_accelerator_partition_mem_alloc_mode(
    amdsmi_processor_handle processor_handle,
    amdsmi_accelerator_partition_mem_alloc_mode_t *mode) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_gpu_compute_partition_mem_alloc_mode(
    amdsmi_processor_handle processor_handle,
    amdsmi_compute_partition_mem_alloc_mode_t mode) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_gpu_accelerator_partition_mem_alloc_mode(
    amdsmi_processor_handle processor_handle,
    amdsmi_accelerator_partition_mem_alloc_mode_t mode) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_memory_partition(amdsmi_processor_handle processor_handle,
                                char *memory_partition, uint32_t len) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_gpu_memory_partition(
    amdsmi_processor_handle processor_handle,
    amdsmi_memory_partition_type_t memory_partition) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_memory_partition_config(
    amdsmi_processor_handle processor_handle,
    amdsmi_memory_partition_config_t *config) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_memory_partition_mode(amdsmi_processor_handle processor_handle,
                                     amdsmi_memory_partition_type_t mode) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_accelerator_partition_profile_config(
    amdsmi_processor_handle processor_handle,
    amdsmi_accelerator_partition_profile_config_t *profile_config) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_accelerator_partition_profile(
    amdsmi_processor_handle processor_handle,
    amdsmi_accelerator_partition_profile_t *profile, uint32_t *partition_id) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_gpu_accelerator_partition_profile(
    amdsmi_processor_handle processor_handle, uint32_t profile_index) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_init_gpu_event_notification(amdsmi_processor_handle processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_event_notification_mask(amdsmi_processor_handle processor_handle,
                                       uint64_t mask) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_event_notification(int timeout_ms, uint32_t *num_elem,
                                  amdsmi_evt_notification_data_t *data) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_stop_gpu_event_notification(amdsmi_processor_handle processor_handle) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_xcd_counter(amdsmi_processor_handle processor_handle,
                           uint16_t *xcd_count) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_npm_info(amdsmi_node_handle node_handle,
                                    amdsmi_npm_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_fw_info(amdsmi_processor_handle processor_handle,
                                   amdsmi_fw_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_vbios_info(amdsmi_processor_handle processor_handle,
                          amdsmi_vbios_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_is_gpu_power_management_enabled(amdsmi_processor_handle processor_handle,
                                       _Bool *enabled) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_violation_status(amdsmi_processor_handle processor_handle,
                            amdsmi_violation_status_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_process_list(amdsmi_processor_handle processor_handle,
                            uint32_t *max_processes, amdsmi_proc_info_t *list) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_gpu_process_list_by_pid(
    amdsmi_processor_handle *processor_handles, uint32_t num_processors,
    amdsmi_proc_info_by_pid_t *procs, uint32_t *max_processes) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_ptl_state(amdsmi_processor_handle processor_handle,
                         _Bool *enabled) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_ptl_state(amdsmi_processor_handle processor_handle,
                         _Bool enable) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_ptl_formats(amdsmi_processor_handle processor_handle,
                           amdsmi_ptl_data_format_t *data_format1,
                           amdsmi_ptl_data_format_t *data_format2) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_ptl_formats(amdsmi_processor_handle processor_handle,
                           amdsmi_ptl_data_format_t data_format1,
                           amdsmi_ptl_data_format_t data_format2) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_driver_info(amdsmi_processor_handle processor_handle,
                           amdsmi_nic_driver_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_asic_info(amdsmi_processor_handle processor_handle,
                         amdsmi_nic_asic_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_bus_info(amdsmi_processor_handle processor_handle,
                        amdsmi_nic_bus_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_numa_info(amdsmi_processor_handle processor_handle,
                         amdsmi_nic_numa_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_port_info(amdsmi_processor_handle processor_handle,
                         amdsmi_nic_port_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_rdma_dev_info(amdsmi_processor_handle processor_handle,
                             amdsmi_nic_rdma_devices_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_nic_rdma_port_statistics(
    amdsmi_processor_handle processor_handle, uint32_t rdma_port_index,
    uint32_t *num_stats, amdsmi_nic_stat_t *stats) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_nic_fw_info(amdsmi_processor_handle processor_handle,
                                       amdsmi_nic_fw_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_port_statistics(amdsmi_processor_handle processor_handle,
                               uint32_t port_index, uint32_t *num_stats,
                               amdsmi_nic_stat_t *stats) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_nic_vendor_statistics(amdsmi_processor_handle processor_handle,
                                 uint32_t port_index, uint32_t *num_stats,
                                 amdsmi_nic_stat_t *stats) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_get_gpu_uma_carveout_info(amdsmi_processor_handle processor_handle,
                                 amdsmi_uma_carveout_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t
amdsmi_set_gpu_uma_carveout(amdsmi_processor_handle processor_handle,
                            uint32_t option_index) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_get_ttm_info(amdsmi_ttm_info_t *info) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_set_ttm_pages_limit(uint64_t pages) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
amdsmi_status_t amdsmi_reset_ttm_pages_limit(void) {
  return AMDSMI_STATUS_NOT_SUPPORTED;
}
