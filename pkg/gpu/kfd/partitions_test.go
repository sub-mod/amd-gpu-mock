package kfd

import (
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestSchedulablePartitionTopology(t *testing.T) {
	physical := profilesForTest(t)["mi300x"]
	for mode, parts := range map[string]int{"SPX": 1, "DPX": 2} {
		t.Run(mode, func(t *testing.T) {
			p, err := PartitionProfile(physical, mode)
			if err != nil {
				t.Fatal(err)
			}
			if len(p.Devices) != 8*parts {
				t.Fatal("logical device count", len(p.Devices))
			}
			root := t.TempDir()
			r := NewRenderer(p, root)
			if err := r.RenderAll(); err != nil {
				t.Fatal(err)
			}
			seen := map[int]bool{}
			for i, dev := range p.Devices {
				if seen[dev.DRMRenderMinor] {
					t.Fatal("duplicate render minor")
				}
				seen[dev.DRMRenderMinor] = true
				if dev.UniqueID != physical.Devices[i/parts].UniqueID {
					t.Fatal("lost physical KFD identity")
				}
				if parts == 2 && p.DeviceDefault.Partition.NPSMode != "NPS2" {
					t.Fatal("DPX requires NPS2 memory model")
				}
				if dev.PCIBDF != physical.Devices[i/parts].PCIBDF {
					t.Fatal("lost parent PCI identity")
				}
				if p.DeviceDefault.Memory.VRAMSizeBytes*uint64(parts) != physical.DeviceDefault.Memory.VRAMSizeBytes {
					t.Fatal("memory division")
				}
				if p.DeviceDefault.Compute.CUCount*uint32(parts) != physical.DeviceDefault.Compute.CUCount {
					t.Fatal("compute division")
				}
				driver := "sys/module/amdgpu/drivers/pci:amdgpu/" + dev.PCIBDF
				if dev.PartitionIndex > 0 {
					driver = fmt.Sprintf("sys/devices/platform/amdgpu_xcp_%d", dev.Index)
				}
				if _, err := os.Stat(filepath.Join(root, driver, fmt.Sprintf("drm/renderD%d", dev.DRMRenderMinor))); err != nil {
					t.Fatal(err)
				}
				if dev.PartitionIndex > 0 {
					if _, err := os.Stat(filepath.Join(root, "sys/module/amdgpu/drivers/pci:amdgpu/", dev.PCIBDF, fmt.Sprintf("drm/card%d", dev.Index))); !os.IsNotExist(err) {
						t.Fatal("child must not be enumerated as a second PCI device")
					}
				}
			}
			if parts > 1 {
				api := NewAPIServer(NewFleetState(p, "mi300x"), r)
				for _, url := range []string{"/api/partitions/set?mode=SPX", "/api/profiles/switch?profile=mi210", "/api/profiles/switch-tray?gpu=0&profile=mi210"} {
					response := httptest.NewRecorder()
					api.ServeHTTP(response, httptest.NewRequest("POST", url, nil))
					if response.Code != 409 {
						t.Fatal("live topology mutation accepted", url, response.Code)
					}
				}
			}
		})
	}
	if len(physical.Devices) != 8 || physical.DeviceDefault.Memory.VRAMSizeBytes != 192*1024*1024*1024 {
		t.Fatal("physical profile mutated")
	}
	for _, mode := range []string{"invalid", "CPX", "QPX"} {
		if _, err := PartitionProfile(physical, mode); err == nil {
			t.Fatal("unsupported mode accepted", mode)
		}
	}
	if _, err := PartitionProfile(profilesForTest(t)["mi210"], "DPX"); err == nil {
		t.Fatal("unsupported GPU accepted")
	}
}

func TestPartitionRecoveryPreservesSiblingTopology(t *testing.T) {
	p, err := PartitionProfile(profilesForTest(t)["mi300x"], "DPX")
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	r := NewRenderer(p, root)
	if err := r.RenderAll(); err != nil {
		t.Fatal(err)
	}
	gpus, _ := NewFleetState(p, "mi300x").GetAll()
	parent := filepath.Join(root, "sys/module/amdgpu/drivers/pci:amdgpu", p.Devices[0].PCIBDF)
	child := filepath.Join(root, "sys/devices/platform/amdgpu_xcp_1")
	if err := os.RemoveAll(child); err != nil {
		t.Fatal(err)
	}
	r.renderDriverBDF(&gpus[1])
	for _, path := range []string{filepath.Join(parent, "drm/renderD128/device/vendor"), filepath.Join(child, "drm/renderD129/device/vendor")} {
		if _, err := os.Stat(path); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := os.Stat(filepath.Join(parent, "drm/renderD129")); !os.IsNotExist(err) {
		t.Fatal("recovery reclassified child as a PCI device")
	}
	if err := os.RemoveAll(filepath.Join(parent, "drm")); err != nil {
		t.Fatal(err)
	}
	r.renderDriverBDF(&gpus[0])
	data, err := os.ReadFile(filepath.Join(parent, "current_memory_partition"))
	if err != nil || string(data) != "NPS2\n" {
		t.Fatal("recovery changed memory mode", string(data), err)
	}
	if _, err := os.Stat(filepath.Join(child, "drm/renderD129/device/vendor")); err != nil {
		t.Fatal("sibling lost", err)
	}
}

func TestVirtualPartitionRecoveryDoesNotIndexPhysicalProfile(t *testing.T) {
	p := profilesForTest(t)["mi300x"]
	r := NewRenderer(p, t.TempDir())
	// Virtual display entries may outnumber the physical startup devices.
	gpu := GPUState{Index: 63, PCIBDF: p.Devices[0].PCIBDF, Partition: "CPX"}
	r.renderDriverBDF(&gpu)
}
