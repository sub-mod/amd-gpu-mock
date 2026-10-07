package kfd

// Profile is the top-level configuration for an AMD GPU mock.
type Profile struct {
	Version string `yaml:"version"`

	System        SystemConfig        `yaml:"system"`
	DeviceDefault DeviceDefaultConfig `yaml:"device_defaults"`
	XGMI          XGMIConfig          `yaml:"xgmi"`
	PCIETopology  PCIETopologyConfig  `yaml:"pcie_topology"`
	Devices       []DeviceConfig      `yaml:"devices"`
}

type SystemConfig struct {
	AMDGPUVersion string `yaml:"amdgpu_version"`
	ROCmVersion   string `yaml:"rocm_version"`
	AMDSMIVersion string `yaml:"amdsmi_version"`
}

type DeviceDefaultConfig struct {
	Name string `yaml:"name"`
	// ProductName is the raw string the amdgpu driver exposes in
	// /sys/class/drm/cardN/device/product_name (for example
	// "AMD Instinct MI300X OAM"). AMD's DRA driver publishes it as the
	// productName device attribute. Defaults to Name when empty.
	ProductName       string `yaml:"product_name,omitempty"`
	VendorID          uint32 `yaml:"vendor_id"`
	DeviceID          uint32 `yaml:"device_id"`
	SubsystemVendorID uint32 `yaml:"subsystem_vendor_id"`
	SubsystemDeviceID uint32 `yaml:"subsystem_device_id"`
	GFXTargetVersion  uint32 `yaml:"gfx_target_version"`
	Architecture      string `yaml:"architecture"`

	Compute     ComputeConfig     `yaml:"compute"`
	Memory      MemoryConfig      `yaml:"memory"`
	Power       PowerConfig       `yaml:"power"`
	Thermal     ThermalConfig     `yaml:"thermal"`
	Clocks      ClocksConfig      `yaml:"clocks"`
	PCIe        PCIeConfig        `yaml:"pcie"`
	ECC         ECCConfig         `yaml:"ecc"`
	Firmware    FirmwareConfig    `yaml:"firmware"`
	Utilization UtilizationConfig `yaml:"utilization"`
	Partition   PartitionConfig   `yaml:"partition"`
}

type ComputeConfig struct {
	CUCount            uint32 `yaml:"cu_count"`
	SIMDPerCU          uint32 `yaml:"simd_per_cu"`
	SIMDCount          uint32 `yaml:"simd_count"`
	StreamProcessors   uint32 `yaml:"stream_processors"`
	WaveFrontSize      uint32 `yaml:"wave_front_size"`
	ArrayCount         uint32 `yaml:"array_count"`
	SIMDArraysPerEng   uint32 `yaml:"simd_arrays_per_engine"`
	CUPerSIMDArray     uint32 `yaml:"cu_per_simd_array"`
	NumXCC             uint32 `yaml:"num_xcc"`
	MaxWavesPerSIMD    uint32 `yaml:"max_waves_per_simd"`
	LDSSizeKB          uint32 `yaml:"lds_size_in_kb"`
	GDSSizeKB          uint32 `yaml:"gds_size_in_kb"`
	NumSDMAEngines     uint32 `yaml:"num_sdma_engines"`
	NumSDMAXGMIEngines uint32 `yaml:"num_sdma_xgmi_engines"`
	NumCPQueues        uint32 `yaml:"num_cp_queues"`
}

type MemoryConfig struct {
	VRAMType      string `yaml:"vram_type"`
	VRAMSizeBytes uint64 `yaml:"vram_size_bytes"`
	VRAMUsedBytes uint64 `yaml:"vram_used_bytes"`
	VRAMBusWidth  uint32 `yaml:"vram_bus_width"`
	VisVRAMBytes  uint64 `yaml:"vis_vram_size_bytes"`
	GTTSizeBytes  uint64 `yaml:"gtt_size_bytes"`
	MaxMemClkMHz  uint32 `yaml:"max_mem_clk_mhz"`
}

type PowerConfig struct {
	CurrentSocketPowerW uint32 `yaml:"current_socket_power_w"`
	DefaultPowerCapW    uint32 `yaml:"default_power_cap_w"`
	MaxPowerCapW        uint32 `yaml:"max_power_cap_w"`
	MinPowerCapW        uint32 `yaml:"min_power_cap_w"`
}

type ThermalConfig struct {
	EdgeTempC     uint32 `yaml:"edge_temperature_c"`
	HotspotTempC  uint32 `yaml:"hotspot_temperature_c"`
	MemTempC      uint32 `yaml:"mem_temperature_c"`
	ShutdownTempC uint32 `yaml:"shutdown_temperature_c"`
	SlowdownTempC uint32 `yaml:"slowdown_temperature_c"`
}

type ClocksConfig struct {
	MaxGFXClkMHz     uint32 `yaml:"max_gfx_clk_mhz"`
	MinGFXClkMHz     uint32 `yaml:"min_gfx_clk_mhz"`
	CurrentGFXClkMHz uint32 `yaml:"current_gfx_clk_mhz"`
	MaxMemClkMHz     uint32 `yaml:"max_mem_clk_mhz"`
	MinMemClkMHz     uint32 `yaml:"min_mem_clk_mhz"`
	CurrentMemClkMHz uint32 `yaml:"current_mem_clk_mhz"`
}

type PCIeConfig struct {
	Gen         uint32 `yaml:"gen"`
	Width       uint32 `yaml:"width"`
	MaxGen      uint32 `yaml:"max_gen"`
	MaxWidth    uint32 `yaml:"max_width"`
	ReplayCount uint32 `yaml:"replay_count"`
}

type ECCConfig struct {
	Enabled            bool   `yaml:"enabled"`
	CorrectableCount   uint64 `yaml:"correctable_count"`
	UncorrectableCount uint64 `yaml:"uncorrectable_count"`
}

type FirmwareConfig struct {
	PMFWVersion string `yaml:"pmfw_version"`
}

type UtilizationConfig struct {
	GFXActivityPercent uint32 `yaml:"gfx_activity_percent"`
	UMCActivityPercent uint32 `yaml:"umc_activity_percent"`
	MMActivityPercent  uint32 `yaml:"mm_activity_percent"`
}

type PartitionConfig struct {
	Mode    string `yaml:"mode"`
	NPSMode string `yaml:"nps_mode"`
}

type XGMIConfig struct {
	HiveID           string `yaml:"hive_id"`
	LinksPerGPU      uint32 `yaml:"links_per_gpu"`
	LanesPerLink     uint32 `yaml:"lanes_per_link"`
	BandwidthPerLink uint32 `yaml:"bandwidth_per_link_gbps"`
	LinkType         uint32 `yaml:"link_type"`
}

type PCIETopologyConfig struct {
	RootComplexes []RootComplex `yaml:"root_complexes"`
}

type RootComplex struct {
	ID       string   `yaml:"id"`
	NUMANode int      `yaml:"numa_node"`
	Devices  []string `yaml:"devices"`
}

type DeviceConfig struct {
	PartitionIndex int    `yaml:"partition_index" json:"partition_index"`
	Index          int    `yaml:"index"`
	UUID           string `yaml:"uuid"`
	PCIBDF         string `yaml:"pci_bdf"`
	DRMRenderMinor int    `yaml:"drm_render_minor"`
	UniqueID       string `yaml:"unique_id"`
	XGMIDeviceID   string `yaml:"xgmi_device_id"`
}

// SysfsProductName returns the value rendered into
// /sys/class/drm/cardN/device/product_name.
func (d *DeviceDefaultConfig) SysfsProductName() string {
	if d.ProductName != "" {
		return d.ProductName
	}
	return d.Name
}
