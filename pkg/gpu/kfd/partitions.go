package kfd

import (
	"fmt"
	"strings"
)

// PartitionProfile models the logical DRM/KFD devices of a pre-partitioned
// MI300X. Siblings retain the physical PCI identity, but have distinct DRM
// minors. This models discovery/allocation, not hardware execution or isolation.
func PartitionProfile(physical *Profile, mode string) (*Profile, error) {
	mode = strings.ToUpper(mode)
	counts := map[string]int{"SPX": 1, "DPX": 2}
	parts, ok := counts[mode]
	if !ok {
		return nil, fmt.Errorf("invalid partition mode %q: use SPX or DPX", mode)
	}
	p := *physical
	p.Devices = append([]DeviceConfig(nil), physical.Devices...)
	p.DeviceDefault.Partition.Mode = mode
	if parts == 1 {
		return &p, nil
	}
	if !strings.Contains(physical.DeviceDefault.Name, "MI300X") {
		return nil, fmt.Errorf("schedulable partitions currently support MI300X only")
	}
	if physical.DeviceDefault.Partition.Mode != "SPX" {
		return nil, fmt.Errorf("partition input must be a physical SPX profile")
	}
	p.DeviceDefault.Partition.NPSMode = "NPS2"
	p.DeviceDefault.Memory.VRAMSizeBytes /= uint64(parts)
	p.DeviceDefault.Memory.VRAMUsedBytes /= uint64(parts)
	p.DeviceDefault.Memory.VisVRAMBytes /= uint64(parts)
	p.DeviceDefault.Compute.CUCount /= uint32(parts)
	p.DeviceDefault.Compute.SIMDCount /= uint32(parts)
	p.DeviceDefault.Compute.NumXCC /= uint32(parts)
	p.DeviceDefault.Power.CurrentSocketPowerW /= uint32(parts)
	p.DeviceDefault.Power.DefaultPowerCapW /= uint32(parts)
	p.DeviceDefault.Power.MaxPowerCapW /= uint32(parts)
	p.Devices = nil
	for _, parent := range physical.Devices {
		for slice := 0; slice < parts; slice++ {
			dev := parent
			dev.Index = len(p.Devices)
			dev.DRMRenderMinor = 128 + dev.Index
			dev.PartitionIndex = slice
			dev.UUID = fmt.Sprintf("%s-part%d", parent.UUID, slice)
			// KFD unique identity stays shared, as AMD's discovery uses it to find
			// the physical parent of each amdgpu_xcp platform device.
			p.Devices = append(p.Devices, dev)
		}
	}
	return &p, nil
}

func (r *Renderer) renderPartitionDevices() error {
	for _, dev := range r.profile.Devices {
		if dev.PartitionIndex == 0 {
			continue
		}
		platform := fmt.Sprintf("sys/devices/platform/amdgpu_xcp_%d", dev.Index)
		for _, name := range []string{fmt.Sprintf("card%d", dev.Index), fmt.Sprintf("renderD%d", dev.DRMRenderMinor)} {
			if err := writeFile(r.rootDir+"/"+platform+"/drm/"+name+"/device/vendor", fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID)); err != nil {
				return err
			}
		}
	}
	return nil
}
