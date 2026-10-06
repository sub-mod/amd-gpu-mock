package kfd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"gopkg.in/yaml.v3"
)

// GPUState holds the mutable runtime state for a single GPU.
type GPUState struct {
	Index          int    `json:"index"`
	UUID           string `json:"uuid"`
	Name           string `json:"name"`
	PCIBDF         string `json:"pci_bdf"`
	NUMANode       int    `json:"numa_node"`
	Architecture   string `json:"architecture"`
	Status         string `json:"status"`
	TemperatureC   int    `json:"temperature_c"`
	PowerW         int    `json:"power_w"`
	PowerCapW      int    `json:"power_cap_w"`
	UtilizationPct int    `json:"utilization_pct"`
	MemoryUsedMB   int    `json:"memory_used_mb"`
	MemoryTotalMB  int    `json:"memory_total_mb"`
	ECCErrors      int    `json:"ecc_errors"`
	ClockGFXMHz    int    `json:"clock_gfx_mhz"`
	ClockMemMHz    int    `json:"clock_mem_mhz"`
	Partition      string `json:"partition"`
	ProfileSlug    string `json:"profile_slug"`
}

// ProfileInfo is the summary for the profile selector.
type ProfileInfo struct {
	Slug         string `json:"slug"`
	Name         string `json:"name"`
	Architecture string `json:"architecture"`
	MemoryGB     int    `json:"memory_gb"`
	GPUCount     int    `json:"gpu_count"`
	TDP          int    `json:"tdp_w"`
}

// FleetState holds the state of all GPUs on this node.
type FleetState struct {
	mu             sync.RWMutex
	GPUs           []GPUState
	Sys            SystemState
	Profiles       map[string]*Profile
	ProfileCatalog []ProfileInfo
}

type SystemState struct {
	AMDGPUVersion string `json:"amdgpu_version"`
	ROCmVersion   string `json:"rocm_version"`
	AMDSMIVersion string `json:"amdsmi_version"`
	ProfileName   string `json:"profile_name"`
	NodeName      string `json:"node_name"`
}

// NewFleetState creates a FleetState from a loaded profile.
// initialSlug is the profile file slug (e.g. "mi300x") used to match
// the dropdown in the dashboard.
func NewFleetState(profile *Profile, initialSlug string) *FleetState {
	gpus := gpusFromProfile(profile, initialSlug)

	fs := &FleetState{
		GPUs: gpus,
		Sys: SystemState{
			AMDGPUVersion: profile.System.AMDGPUVersion,
			ROCmVersion:   profile.System.ROCmVersion,
			AMDSMIVersion: profile.System.AMDSMIVersion,
			ProfileName:   profile.DeviceDefault.Name,
			NodeName:      "mock-node",
		},
		Profiles:       map[string]*Profile{initialSlug: profile},
		ProfileCatalog: []ProfileInfo{},
	}

	return fs
}

// LoadProfiles reads all YAML profile files from a directory.
func (f *FleetState) LoadProfiles(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("reading profile dir: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".yaml") {
			continue
		}
		slug := strings.TrimSuffix(entry.Name(), ".yaml")

		data, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			continue
		}

		var p Profile
		if err := yaml.Unmarshal(data, &p); err != nil {
			continue
		}

		f.Profiles[slug] = &p
		f.ProfileCatalog = append(f.ProfileCatalog, ProfileInfo{
			Slug:         slug,
			Name:         p.DeviceDefault.Name,
			Architecture: p.DeviceDefault.Architecture,
			MemoryGB:     int(p.DeviceDefault.Memory.VRAMSizeBytes / (1024 * 1024 * 1024)),
			GPUCount:     len(p.Devices),
			TDP:          int(p.DeviceDefault.Power.MaxPowerCapW),
		})
	}

	return nil
}

// SwitchProfile changes all GPUs to a different profile.
func (f *FleetState) SwitchProfile(slug string) ([]GPUState, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()

	p, ok := f.Profiles[slug]
	if !ok {
		return nil, false
	}

	f.GPUs = gpusFromProfile(p, slug)
	f.Sys.ProfileName = p.DeviceDefault.Name
	f.Sys.AMDGPUVersion = p.System.AMDGPUVersion
	f.Sys.ROCmVersion = p.System.ROCmVersion

	cpy := make([]GPUState, len(f.GPUs))
	copy(cpy, f.GPUs)
	return cpy, true
}

// ServerTraySize returns GPUs per server tray based on the profile's architecture.
// OAM models (MI300X, MI325X, MI350X, MI355X): always 8 — UBB baseboard is fixed.
// APU (MI300A): always 4.
// PCIe (MI210, MI250X): 4 in multi-server configs, 8 in single-server.
func ServerTraySize(gpuCount int) int {
	if gpuCount >= 8 {
		return 8
	}
	return 4
}

// ProfileAllowsSplit returns true if this profile's form factor supports
// splitting into multiple server trays (PCIe cards can be in separate servers).
// OAM baseboard models are always a single 8-GPU unit — can't be split.
func ProfileAllowsSplit(profileName string) bool {
	oamModels := map[string]bool{
		"AMD Instinct MI300X": true,
		"AMD Instinct MI325X": true,
		"AMD Instinct MI350X": true,
		"AMD Instinct MI355X": true,
	}
	return !oamModels[profileName]
}

// SwitchTrayProfile changes all GPUs in a server tray to a different profile.
// The tray is determined by the GPU index: 0-3 = Tray A, 4-7 = Tray B.
func (f *FleetState) SwitchTrayProfile(index int, slug string) ([]GPUState, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()

	if index < 0 || index >= len(f.GPUs) {
		return nil, false
	}

	p, ok := f.Profiles[slug]
	if !ok {
		return nil, false
	}

	ts := ServerTraySize(len(f.GPUs))
	trayStart := (index / ts) * ts
	trayEnd := trayStart + ts
	if trayEnd > len(f.GPUs) {
		trayEnd = len(f.GPUs)
	}

	d := p.DeviceDefault
	for i := trayStart; i < trayEnd; i++ {
		gpu := &f.GPUs[i]
		gpu.Name = d.Name
		gpu.Architecture = d.Architecture
		gpu.PowerCapW = int(d.Power.MaxPowerCapW)
		gpu.PowerW = int(d.Power.CurrentSocketPowerW)
		gpu.MemoryTotalMB = int(d.Memory.VRAMSizeBytes / (1024 * 1024))
		gpu.MemoryUsedMB = int(d.Memory.VRAMUsedBytes / (1024 * 1024))
		gpu.TemperatureC = int(d.Thermal.EdgeTempC)
		gpu.ClockGFXMHz = int(d.Clocks.CurrentGFXClkMHz)
		gpu.ClockMemMHz = int(d.Clocks.CurrentMemClkMHz)
		gpu.Partition = d.Partition.Mode
		gpu.ProfileSlug = slug
		gpu.Status = "healthy"
		gpu.ECCErrors = 0
		gpu.UtilizationPct = 0
	}

	result := make([]GPUState, trayEnd-trayStart)
	copy(result, f.GPUs[trayStart:trayEnd])
	return result, true
}

// GetTrayInfo returns which tray a GPU belongs to and the tray's profile.
func (f *FleetState) GetTrayInfo() []TrayInfo {
	f.mu.RLock()
	defer f.mu.RUnlock()

	ts := ServerTraySize(len(f.GPUs))
	numTrays := (len(f.GPUs) + ts - 1) / ts
	trays := make([]TrayInfo, numTrays)
	for i := range trays {
		start := i * ts
		end := start + ts
		if end > len(f.GPUs) {
			end = len(f.GPUs)
		}
		trays[i] = TrayInfo{
			Index:       i,
			StartGPU:    start,
			EndGPU:      end - 1,
			GPUCount:    end - start,
			ProfileSlug: f.GPUs[start].ProfileSlug,
			ProfileName: f.GPUs[start].Name,
		}
	}
	return trays
}

// TrayInfo describes a server tray in the rack.
type TrayInfo struct {
	Index       int    `json:"index"`
	StartGPU    int    `json:"start_gpu"`
	EndGPU      int    `json:"end_gpu"`
	GPUCount    int    `json:"gpu_count"`
	ProfileSlug string `json:"profile_slug"`
	ProfileName string `json:"profile_name"`
}

// SetPartitionMode changes the compute partition mode for all GPUs.
// In CPX mode (8 partitions), each physical GPU becomes 8 virtual GPUs.
// The GPU list expands or contracts accordingly.
func (f *FleetState) SetPartitionMode(mode string, partitionsPerGPU int) {
	f.mu.Lock()
	defer f.mu.Unlock()

	// Always derive partitions from physical profile data. Deriving a second
	// mode from existing virtual GPUs compounds memory division and duplicates IDs.
	if len(f.GPUs) == 0 {
		return
	}
	slug := f.GPUs[0].ProfileSlug
	profile, ok := f.Profiles[slug]
	if !ok {
		return
	}
	physical := gpusFromProfile(profile, slug)
	if partitionsPerGPU <= 1 {
		for i := range physical {
			physical[i].Partition = mode
		}
		f.GPUs = physical
		return
	}
	newGPUs := make([]GPUState, len(physical)*partitionsPerGPU)
	for i := range newGPUs {
		base := physical[i/partitionsPerGPU]
		newGPUs[i] = base
		newGPUs[i].Index = i
		newGPUs[i].Partition = mode
		newGPUs[i].UUID = fmt.Sprintf("%s-part%d", base.UUID, i%partitionsPerGPU)
		newGPUs[i].MemoryTotalMB = base.MemoryTotalMB / partitionsPerGPU
		newGPUs[i].MemoryUsedMB = base.MemoryUsedMB / partitionsPerGPU
		newGPUs[i].PowerCapW = base.PowerCapW / partitionsPerGPU
		newGPUs[i].PowerW = base.PowerW / partitionsPerGPU
	}
	f.GPUs = newGPUs
}

func (f *FleetState) GetAll() ([]GPUState, SystemState) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	cpy := make([]GPUState, len(f.GPUs))
	copy(cpy, f.GPUs)
	return cpy, f.Sys
}

func (f *FleetState) GetGPU(index int) (GPUState, bool) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	if index < 0 || index >= len(f.GPUs) {
		return GPUState{}, false
	}
	return f.GPUs[index], true
}

func (f *FleetState) UpdateGPU(index int, patch json.RawMessage) (GPUState, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if index < 0 || index >= len(f.GPUs) {
		return GPUState{}, false
	}
	json.Unmarshal(patch, &f.GPUs[index])
	return f.GPUs[index], true
}

func gpusFromProfile(profile *Profile, slug string) []GPUState {
	gpus := make([]GPUState, len(profile.Devices))
	d := profile.DeviceDefault

	for i, dev := range profile.Devices {
		gpus[i] = GPUState{
			Index:          dev.Index,
			UUID:           dev.UUID,
			Name:           d.Name,
			PCIBDF:         dev.PCIBDF,
			NUMANode:       numaForBDFStatic(dev.PCIBDF, profile),
			Architecture:   d.Architecture,
			Status:         "healthy",
			TemperatureC:   int(d.Thermal.EdgeTempC),
			PowerW:         int(d.Power.CurrentSocketPowerW),
			PowerCapW:      int(d.Power.MaxPowerCapW),
			UtilizationPct: int(d.Utilization.GFXActivityPercent),
			MemoryUsedMB:   int(d.Memory.VRAMUsedBytes / (1024 * 1024)),
			MemoryTotalMB:  int(d.Memory.VRAMSizeBytes / (1024 * 1024)),
			ECCErrors:      0,
			ClockGFXMHz:    int(d.Clocks.CurrentGFXClkMHz),
			ClockMemMHz:    int(d.Clocks.CurrentMemClkMHz),
			Partition:      d.Partition.Mode,
			ProfileSlug:    slug,
		}
	}
	return gpus
}

func numaForBDFStatic(bdf string, p *Profile) int {
	for _, rc := range p.PCIETopology.RootComplexes {
		for _, d := range rc.Devices {
			if d == bdf {
				return rc.NUMANode
			}
		}
	}
	return -1
}
