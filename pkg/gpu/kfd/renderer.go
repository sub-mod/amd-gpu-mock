package kfd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// Renderer writes the KFD sysfs topology tree and device nodes from a Profile.
type Renderer struct {
	profile *Profile
	rootDir string // e.g. /var/lib/amd-gpu-mock
}

func NewRenderer(profile *Profile, rootDir string) *Renderer {
	return &Renderer{profile: profile, rootDir: rootDir}
}

// SwitchProfile cleans the old sysfs surfaces, loads a new profile, and
// re-renders the sysfs tree. Device nodes are not recreated — they don't
// change between profiles (same /dev/kfd and /dev/dri/renderD* paths).
func (r *Renderer) SwitchProfile(profile *Profile) error {
	sysDir := filepath.Join(r.rootDir, "sys")
	os.RemoveAll(sysDir)
	r.profile = profile
	if err := r.renderKFDTopology(); err != nil {
		return fmt.Errorf("kfd topology: %w", err)
	}
	if err := r.renderDRMDevices(); err != nil {
		return fmt.Errorf("drm devices: %w", err)
	}
	if err := r.renderDriverModule(); err != nil {
		return fmt.Errorf("driver module: %w", err)
	}
	if err := r.renderPCISysfs(); err != nil {
		return fmt.Errorf("pci sysfs: %w", err)
	}
	if err := r.renderDriverLinks(); err != nil {
		return fmt.Errorf("driver links: %w", err)
	}
	if err := r.renderHostCompat(); err != nil {
		return fmt.Errorf("host compat: %w", err)
	}
	return nil
}

// UpdateGPUSysfs writes runtime state changes for a single GPU back to the
// staged sysfs tree, so the device plugin and other consumers see the change.
func (r *Renderer) UpdateGPUSysfs(gpu *GPUState) error {
	nodeIdx := gpu.Index + 1 // KFD node 0 is CPU
	topoDir := filepath.Join(r.rootDir, "sys/class/kfd/kfd/topology")
	nodeDir := filepath.Join(topoDir, fmt.Sprintf("nodes/%d", nodeIdx))

	// Update the RAS/ECC status file — consumers check this for GPU health.
	rasDir := filepath.Join(nodeDir, "ras")
	if gpu.Status == "crashed" || gpu.ECCErrors > 0 {
		if err := writeFile(filepath.Join(rasDir, "fatal_error"), "1\n"); err != nil {
			return err
		}
	} else {
		if err := writeFile(filepath.Join(rasDir, "fatal_error"), "0\n"); err != nil {
			return err
		}
	}

	// Update ECC error counts in the properties-like ras directory.
	if err := writeFile(filepath.Join(rasDir, "ecc_uncorrectable"),
		fmt.Sprintf("%d\n", gpu.ECCErrors)); err != nil {
		return err
	}

	// Update DRM device power/thermal hwmon files for monitoring consumers.
	hwmonDir := filepath.Join(r.rootDir, fmt.Sprintf("sys/class/drm/card%d/device/hwmon/hwmon0", gpu.Index))
	if err := writeFile(filepath.Join(hwmonDir, "temp1_input"),
		fmt.Sprintf("%d\n", gpu.TemperatureC*1000)); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(hwmonDir, "power1_average"),
		fmt.Sprintf("%d\n", gpu.PowerW*1000000)); err != nil {
		return err
	}

	// Mark GPU as crashed by removing it from the driver binding if crashed.
	driverDir := filepath.Join(r.rootDir, "sys/module/amdgpu/drivers/pci:amdgpu")
	bdf := gpu.PCIBDF
	crashMarker := filepath.Join(driverDir, bdf, "gpu_crashed")

	// When crashed: remove device nodes AND the driver BDF directory.
	// The device plugin walks /sys/module/amdgpu/drivers/pci:amdgpu/<BDF>/drm/
	// to discover GPUs. Removing the BDF dir makes the GPU invisible to the
	// plugin. Removing /dev/dri/* prevents kubelet from mounting it.
	renderNode := fmt.Sprintf("/dev/dri/renderD%d", 128+gpu.Index)
	cardNode := fmt.Sprintf("/dev/dri/card%d", gpu.Index)
	bdfDriverDir := filepath.Join(driverDir, bdf)

	if gpu.Status == "crashed" {
		writeFile(crashMarker, "1\n")
		os.Remove(renderNode)
		os.Remove(cardNode)
		os.RemoveAll(bdfDriverDir)
	} else {
		os.Remove(crashMarker)
		if _, err := os.Stat(renderNode); os.IsNotExist(err) {
			syscall.Mknod(renderNode, syscall.S_IFCHR|0o660, int(uint64(226)<<8|uint64(128+gpu.Index)))
		}
		if _, err := os.Stat(cardNode); os.IsNotExist(err) {
			syscall.Mknod(cardNode, syscall.S_IFCHR|0o660, int(uint64(226)<<8|uint64(gpu.Index)))
		}
		// Restore driver BDF directory if it was removed
		if _, err := os.Stat(bdfDriverDir); os.IsNotExist(err) {
			r.renderDriverBDF(gpu)
		}
	}

	return nil
}

// RenderAll writes every simulated surface.
func (r *Renderer) RenderAll() error {
	if err := r.renderKFDTopology(); err != nil {
		return fmt.Errorf("kfd topology: %w", err)
	}
	if err := r.renderDRMDevices(); err != nil {
		return fmt.Errorf("drm devices: %w", err)
	}
	if err := r.renderDeviceNodes(); err != nil {
		return fmt.Errorf("device nodes: %w", err)
	}
	if err := r.renderDriverModule(); err != nil {
		return fmt.Errorf("driver module: %w", err)
	}
	if err := r.renderPCISysfs(); err != nil {
		return fmt.Errorf("pci sysfs: %w", err)
	}
	if err := r.renderDriverLinks(); err != nil {
		return fmt.Errorf("driver links: %w", err)
	}
	if err := r.renderHostCompat(); err != nil {
		return fmt.Errorf("host compat: %w", err)
	}
	return nil
}

// renderHostCompat creates sysfs paths that the container runtime or KIND
// expects to exist when /sys is mounted from our mock tree. Without these,
// containerd hooks fail with "mount point does not exist".
func (r *Renderer) renderHostCompat() error {
	compatPaths := map[string]string{
		"sys/class/dmi/id/product_name":   r.profile.DeviceDefault.Name + "\n",
		"sys/class/dmi/id/board_vendor":   "AMD\n",
		"sys/class/dmi/id/product_serial": "mock-serial\n",
		// kind bind-mounts the host UUID here on native x86 nodes.
		"sys/class/dmi/id/product_uuid":         "00000000-0000-0000-0000-000000000000\n",
		"sys/devices/system/node/node0/cpulist": "0-127\n",
	}
	for path, content := range compatPaths {
		if err := writeFile(filepath.Join(r.rootDir, path), content); err != nil {
			return err
		}
	}
	return nil
}

func (r *Renderer) renderKFDTopology() error {
	topoDir := filepath.Join(r.rootDir, "sys/class/kfd/kfd/topology")

	if err := writeFile(filepath.Join(topoDir, "generation_id"), "1\n"); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(topoDir, "system_properties"),
		"platform_oem 0\nplatform_id 0\nplatform_rev 0\n"); err != nil {
		return err
	}

	// Node 0 is the CPU node.
	cpuDir := filepath.Join(topoDir, "nodes/0")
	if err := r.renderCPUNode(cpuDir); err != nil {
		return err
	}

	// GPU nodes start at index 1.
	for i, dev := range r.profile.Devices {
		nodeDir := filepath.Join(topoDir, fmt.Sprintf("nodes/%d", i+1))
		if err := r.renderGPUNode(nodeDir, &dev); err != nil {
			return fmt.Errorf("gpu node %d: %w", i, err)
		}
	}

	return nil
}

func (r *Renderer) renderCPUNode(dir string) error {
	props := []string{
		"cpu_cores_count 128",
		"simd_count 0",
		"mem_banks_count 1",
		"caches_count 0",
		"io_links_count 0",
		"p2p_links_count 0",
		"cpu_core_id_base 0",
		"simd_id_base 0",
		"max_waves_per_simd 0",
		"lds_size_in_kb 0",
		"gds_size_in_kb 0",
		"num_gws 0",
		"wave_front_size 0",
		"array_count 0",
		"simd_arrays_per_engine 0",
		"cu_per_simd_array 0",
		"simd_per_cu 0",
		"max_slots_scratch_cu 0",
		"gfx_target_version 0",
		"vendor_id 0",
		"device_id 0",
		"location_id 0",
		"domain 0",
		"drm_render_minor 0",
		"hive_id 0",
		"num_sdma_engines 0",
		"num_sdma_xgmi_engines 0",
		"num_sdma_queues_per_engine 0",
		"num_cp_queues 0",
		"max_engine_clk_fcompute 0",
		"local_mem_size 0",
		"fw_version 0",
		"capability 0",
		"debug_prop 0",
		"sdma_fw_version 0",
		"unique_id 0",
		"num_xcc 0",
	}

	if err := writeFile(filepath.Join(dir, "gpu_id"), "0\n"); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(dir, "name"), "CPU\n"); err != nil {
		return err
	}
	return writeFile(filepath.Join(dir, "properties"), strings.Join(props, "\n")+"\n")
}

func (r *Renderer) renderGPUNode(dir string, dev *DeviceConfig) error {
	d := r.profile.DeviceDefault
	c := d.Compute

	numaNode := r.numaForBDF(dev.PCIBDF)
	locationID := bdfToLocationID(dev.PCIBDF)
	domain := bdfToDomain(dev.PCIBDF)

	gpuID := uint32(dev.Index + 1)

	props := []string{
		"cpu_cores_count 0",
		fmt.Sprintf("simd_count %d", c.SIMDCount),
		"mem_banks_count 1",
		"caches_count 0",
		fmt.Sprintf("io_links_count %d", r.ioLinkCount(dev)),
		"p2p_links_count 0",
		"cpu_core_id_base 0",
		"simd_id_base 0",
		fmt.Sprintf("max_waves_per_simd %d", c.MaxWavesPerSIMD),
		fmt.Sprintf("lds_size_in_kb %d", c.LDSSizeKB),
		fmt.Sprintf("gds_size_in_kb %d", c.GDSSizeKB),
		"num_gws 0",
		fmt.Sprintf("wave_front_size %d", c.WaveFrontSize),
		fmt.Sprintf("array_count %d", c.ArrayCount),
		fmt.Sprintf("simd_arrays_per_engine %d", c.SIMDArraysPerEng),
		fmt.Sprintf("cu_per_simd_array %d", c.CUPerSIMDArray),
		fmt.Sprintf("simd_per_cu %d", c.SIMDPerCU),
		"max_slots_scratch_cu 32",
		fmt.Sprintf("gfx_target_version %d", d.GFXTargetVersion),
		fmt.Sprintf("vendor_id %d", d.VendorID),
		fmt.Sprintf("device_id %d", d.DeviceID),
		fmt.Sprintf("location_id %d", locationID),
		fmt.Sprintf("domain %d", domain),
		fmt.Sprintf("drm_render_minor %d", dev.DRMRenderMinor),
		fmt.Sprintf("hive_id %s", r.profile.XGMI.HiveID),
		fmt.Sprintf("num_sdma_engines %d", c.NumSDMAEngines),
		fmt.Sprintf("num_sdma_xgmi_engines %d", c.NumSDMAXGMIEngines),
		"num_sdma_queues_per_engine 4",
		fmt.Sprintf("num_cp_queues %d", c.NumCPQueues),
		fmt.Sprintf("max_engine_clk_fcompute %d", d.Clocks.MaxGFXClkMHz),
		fmt.Sprintf("local_mem_size %d", d.Memory.VRAMSizeBytes),
		"fw_version 0",
		"capability 0x00002b3a",
		"debug_prop 0x0000000000000900",
		"sdma_fw_version 0",
		fmt.Sprintf("unique_id %s", dev.UniqueID),
		fmt.Sprintf("num_xcc %d", c.NumXCC),
	}

	if err := writeFile(filepath.Join(dir, "gpu_id"), fmt.Sprintf("%d\n", gpuID)); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(dir, "name"), d.Name+"\n"); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(dir, "properties"), strings.Join(props, "\n")+"\n"); err != nil {
		return err
	}

	// mem_banks/0/properties
	memProps := []string{
		"heap_type 1",
		fmt.Sprintf("size_in_bytes %d", d.Memory.VRAMSizeBytes),
		"flags 0",
		fmt.Sprintf("width %d", d.Memory.VRAMBusWidth),
		fmt.Sprintf("mem_clk_max %d", d.Memory.MaxMemClkMHz),
	}
	if err := writeFile(filepath.Join(dir, "mem_banks/0/properties"),
		strings.Join(memProps, "\n")+"\n"); err != nil {
		return err
	}

	// io_links — one PCIe link to CPU, then xGMI links to peer GPUs
	linkIdx := 0
	pcieLinkProps := []string{
		fmt.Sprintf("type %d", 2), // PCIe
		"version_major 0",
		"version_minor 0",
		fmt.Sprintf("node_from %d", dev.Index+1),
		"node_to 0",
		"weight 40",
		"min_latency 0",
		"max_latency 0",
		"min_bandwidth 0",
		"max_bandwidth 0",
		"recommended_transfer_size 0",
		"flags 0x0000000000000001",
	}
	if err := writeFile(filepath.Join(dir, fmt.Sprintf("io_links/%d/properties", linkIdx)),
		strings.Join(pcieLinkProps, "\n")+"\n"); err != nil {
		return err
	}
	linkIdx++

	// xGMI links to other GPUs
	for _, peer := range r.profile.Devices {
		if peer.Index == dev.Index {
			continue
		}
		xgmiProps := []string{
			fmt.Sprintf("type %d", r.profile.XGMI.LinkType), // xGMI
			"version_major 0",
			"version_minor 0",
			fmt.Sprintf("node_from %d", dev.Index+1),
			fmt.Sprintf("node_to %d", peer.Index+1),
			"weight 15",
			"min_latency 0",
			"max_latency 0",
			"min_bandwidth 0",
			fmt.Sprintf("max_bandwidth %d", r.profile.XGMI.BandwidthPerLink*1000), // GB/s -> MB/s
			"recommended_transfer_size 0",
			"flags 0x0000000000000001",
		}
		if err := writeFile(filepath.Join(dir, fmt.Sprintf("io_links/%d/properties", linkIdx)),
			strings.Join(xgmiProps, "\n")+"\n"); err != nil {
			return err
		}
		linkIdx++
	}

	// NUMA node in DRM path
	drmDir := filepath.Join(r.rootDir, fmt.Sprintf("sys/class/drm/card%d/device", dev.Index))
	if err := writeFile(filepath.Join(drmDir, "numa_node"), fmt.Sprintf("%d\n", numaNode)); err != nil {
		return err
	}

	return nil
}

// renderDriverBDF restores the driver sysfs directory for a single GPU.
// Called when recovering a crashed GPU.
func (r *Renderer) renderDriverBDF(gpu *GPUState) {
	moduleDir := filepath.Join(r.rootDir, "sys/module/amdgpu")
	driverDir := filepath.Join(moduleDir, "drivers/pci:amdgpu")
	bdfDir := filepath.Join(driverDir, gpu.PCIBDF)
	numaNode := 0
	for _, rc := range r.profile.PCIETopology.RootComplexes {
		for _, d := range rc.Devices {
			if d == gpu.PCIBDF {
				numaNode = rc.NUMANode
			}
		}
	}
	writeFile(filepath.Join(bdfDir, "numa_node"), fmt.Sprintf("%d\n", numaNode))
	writeFile(filepath.Join(bdfDir, "current_compute_partition"), gpu.Partition+"\n")
	writeFile(filepath.Join(bdfDir, "current_memory_partition"), "NPS1\n")
	writeFile(filepath.Join(bdfDir, "vendor"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID))
	writeFile(filepath.Join(bdfDir, "device"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.DeviceID))
	cardDir := filepath.Join(bdfDir, fmt.Sprintf("drm/card%d/device", gpu.Index))
	writeFile(filepath.Join(cardDir, "vendor"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID))
	renderDir := filepath.Join(bdfDir, fmt.Sprintf("drm/renderD%d/device", 128+gpu.Index))
	writeFile(filepath.Join(renderDir, "vendor"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID))
}

func (r *Renderer) renderDRMDevices() error {
	for _, dev := range r.profile.Devices {
		drmDir := filepath.Join(r.rootDir, fmt.Sprintf("sys/class/drm/card%d/device", dev.Index))

		if err := writeFile(filepath.Join(drmDir, "vendor"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID)); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(drmDir, "device"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.DeviceID)); err != nil {
			return err
		}
		// Read by AMD's DRA driver (productName attribute) and node labeller
		// (product-name label); without it both come back empty on the mock.
		if err := writeFile(filepath.Join(drmDir, "product_name"), r.profile.DeviceDefault.SysfsProductName()+"\n"); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(drmDir, "uevent"),
			fmt.Sprintf("DRIVER=amdgpu\nPCI_CLASS=38000\nPCI_ID=1002:%04X\nPCI_SUBSYS_ID=1002:%04X\nPCI_SLOT_NAME=%s\n",
				r.profile.DeviceDefault.DeviceID,
				r.profile.DeviceDefault.SubsystemDeviceID,
				dev.PCIBDF)); err != nil {
			return err
		}

		if r.profile.XGMI.HiveID != "" {
			xgmiDir := filepath.Join(drmDir, "xgmi_hive_info")
			if err := writeFile(filepath.Join(xgmiDir, "xgmi_hive_id"), r.profile.XGMI.HiveID+"\n"); err != nil {
				return err
			}
			if err := writeFile(filepath.Join(drmDir, "xgmi_device_id"), dev.XGMIDeviceID+"\n"); err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *Renderer) renderDeviceNodes() error {
	devDir := filepath.Join(r.rootDir, "dev")

	// /dev/kfd — KFD compute interface (one per system)
	kfdPath := filepath.Join(devDir, "kfd")
	if err := os.MkdirAll(filepath.Dir(kfdPath), 0o755); err != nil {
		return err
	}
	// Create a regular file as placeholder; real mknod requires privileges
	// and is done by the entrypoint script.
	if err := writeFile(kfdPath, ""); err != nil {
		return err
	}

	// /dev/dri/renderDN — one per GPU
	driDir := filepath.Join(devDir, "dri")
	for _, dev := range r.profile.Devices {
		renderPath := filepath.Join(driDir, fmt.Sprintf("renderD%d", dev.DRMRenderMinor))
		if err := writeFile(renderPath, ""); err != nil {
			return err
		}
	}

	return nil
}

func (r *Renderer) renderDriverModule() error {
	moduleDir := filepath.Join(r.rootDir, "sys/module/amdgpu")

	if err := writeFile(filepath.Join(moduleDir, "refcnt"), "1\n"); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(moduleDir, "version"), r.profile.System.AMDGPUVersion+"\n"); err != nil {
		return err
	}
	// amd-smi CLI checks this file to determine if the driver is loaded.
	// Must contain "live" for amd-smi to proceed with initialization.
	if err := writeFile(filepath.Join(moduleDir, "initstate"), "live\n"); err != nil {
		return err
	}

	// The AMD device plugin enumerates GPUs by walking:
	//   /sys/module/amdgpu/drivers/pci:amdgpu/<BDF>/drm/cardN/device/vendor
	// Each BDF directory must contain drm/cardN with a device/vendor file
	// reading 0x1002 for the plugin to recognize it as an AMD GPU.
	driverDir := filepath.Join(moduleDir, "drivers/pci:amdgpu")
	for _, dev := range r.profile.Devices {
		bdfDir := filepath.Join(driverDir, dev.PCIBDF)
		numaNode := r.numaForBDF(dev.PCIBDF)

		// Files the device plugin reads directly from the BDF directory
		if err := writeFile(filepath.Join(bdfDir, "numa_node"),
			fmt.Sprintf("%d\n", numaNode)); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(bdfDir, "current_compute_partition"),
			r.profile.DeviceDefault.Partition.Mode+"\n"); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(bdfDir, "current_memory_partition"),
			r.profile.DeviceDefault.Partition.NPSMode+"\n"); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(bdfDir, "vendor"),
			fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID)); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(bdfDir, "device"),
			fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.DeviceID)); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(bdfDir, "uevent"),
			fmt.Sprintf("DRIVER=amdgpu\nPCI_CLASS=038000\nPCI_ID=1002:%04X\nPCI_SUBSYS_ID=1002:%04X\nPCI_SLOT_NAME=%s\n",
				r.profile.DeviceDefault.DeviceID,
				r.profile.DeviceDefault.SubsystemDeviceID,
				dev.PCIBDF)); err != nil {
			return err
		}

		// drm/cardN and drm/renderDN inside the BDF directory
		cardDir := filepath.Join(bdfDir, fmt.Sprintf("drm/card%d", dev.Index))
		if err := writeFile(filepath.Join(cardDir, "device/vendor"),
			fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID)); err != nil {
			return err
		}

		renderDir := filepath.Join(bdfDir, fmt.Sprintf("drm/renderD%d", dev.DRMRenderMinor))
		if err := writeFile(filepath.Join(renderDir, "device/vendor"),
			fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID)); err != nil {
			return err
		}
	}
	return nil
}

func (r *Renderer) renderPCISysfs() error {
	for _, dev := range r.profile.Devices {
		numaNode := r.numaForBDF(dev.PCIBDF)

		for _, rc := range r.profile.PCIETopology.RootComplexes {
			for _, rcDev := range rc.Devices {
				if rcDev == dev.PCIBDF {
					devDir := filepath.Join(r.rootDir, "sys/bus/pci/devices", dev.PCIBDF)
					devicesDir := filepath.Join(r.rootDir, "sys/devices", rc.ID, dev.PCIBDF)

					if err := writeFile(filepath.Join(devicesDir, "vendor"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.VendorID)); err != nil {
						return err
					}
					if err := writeFile(filepath.Join(devicesDir, "device"), fmt.Sprintf("0x%04x\n", r.profile.DeviceDefault.DeviceID)); err != nil {
						return err
					}
					if err := writeFile(filepath.Join(devicesDir, "class"), "0x038000\n"); err != nil {
						return err
					}
					if err := writeFile(filepath.Join(devicesDir, "numa_node"), fmt.Sprintf("%d\n", numaNode)); err != nil {
						return err
					}

					// symlink from bus to devices
					if err := os.MkdirAll(filepath.Dir(devDir), 0o755); err != nil {
						return err
					}
					rel, _ := filepath.Rel(filepath.Dir(devDir), devicesDir)
					_ = os.Remove(devDir)
					if err := os.Symlink(rel, devDir); err != nil {
						return err
					}
				}
			}
		}
	}
	return nil
}

// renderDriverLinks adds the driver symlinks a real amdgpu system has:
//
//	/sys/bus/pci/drivers/amdgpu/module  -> /sys/module/amdgpu
//	/sys/bus/pci/drivers/amdgpu/<BDF>   -> the PCI device
//	/sys/devices/<root>/<BDF>/driver    -> /sys/bus/pci/drivers/amdgpu
//	/sys/class/drm/cardN/device/driver  -> /sys/bus/pci/drivers/amdgpu
//
// AMD's DRA driver v1.0.0 and node labeller read the driver version through
// /sys/class/drm/cardN/device/driver/module/version. Without these links the
// DRA driver publishes an empty driverVersion, which is not valid semver, so
// the API server rejects its ResourceSlice and no GPUs are advertised.
func (r *Renderer) renderDriverLinks() error {
	sysDir := filepath.Join(r.rootDir, "sys")
	drvDir := filepath.Join(sysDir, "bus/pci/drivers/amdgpu")
	if err := os.MkdirAll(drvDir, 0o755); err != nil {
		return err
	}
	if err := relSymlink(filepath.Join(sysDir, "module/amdgpu"), filepath.Join(drvDir, "module")); err != nil {
		return err
	}
	for _, dev := range r.profile.Devices {
		cardDriver := filepath.Join(sysDir, fmt.Sprintf("class/drm/card%d/device/driver", dev.Index))
		if err := relSymlink(drvDir, cardDriver); err != nil {
			return err
		}
		for _, rc := range r.profile.PCIETopology.RootComplexes {
			for _, bdf := range rc.Devices {
				if bdf != dev.PCIBDF {
					continue
				}
				pciDev := filepath.Join(sysDir, "devices", rc.ID, bdf)
				if err := relSymlink(drvDir, filepath.Join(pciDev, "driver")); err != nil {
					return err
				}
				if err := relSymlink(pciDev, filepath.Join(drvDir, bdf)); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

// relSymlink creates or replaces link so it points at target through a
// relative path, as sysfs does, so the tree resolves wherever it is mounted.
func relSymlink(target, link string) error {
	if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
		return err
	}
	rel, err := filepath.Rel(filepath.Dir(link), target)
	if err != nil {
		return err
	}
	_ = os.Remove(link)
	return os.Symlink(rel, link)
}

func (r *Renderer) ioLinkCount(dev *DeviceConfig) int {
	// 1 PCIe link + N-1 xGMI links to peers
	return 1 + len(r.profile.Devices) - 1
}

func (r *Renderer) numaForBDF(bdf string) int {
	for _, rc := range r.profile.PCIETopology.RootComplexes {
		for _, d := range rc.Devices {
			if d == bdf {
				return rc.NUMANode
			}
		}
	}
	return -1
}

func bdfToLocationID(bdf string) uint32 {
	// Parse "DDDD:BB:DD.F" to a location_id
	var domain, bus, device, fn uint32
	fmt.Sscanf(bdf, "%x:%x:%x.%x", &domain, &bus, &device, &fn)
	return (bus << 8) | (device << 3) | fn
}

func bdfToDomain(bdf string) uint32 {
	var domain uint32
	fmt.Sscanf(bdf, "%x:", &domain)
	return domain
}

// Cleanup removes all rendered surfaces.
func (r *Renderer) Cleanup() error {
	return os.RemoveAll(r.rootDir)
}

func writeFile(path, content string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), 0o644)
}
