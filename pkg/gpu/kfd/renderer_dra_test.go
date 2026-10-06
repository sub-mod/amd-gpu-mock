package kfd

import (
	"fmt"
	"gopkg.in/yaml.v3"
	"os"
	"path/filepath"
	"testing"
)

// These paths are the discovery contract, including links that must resolve
// after the tree is mounted at a different location and after profile changes.
func TestDRAProfileDiscoveryPaths(t *testing.T) {
	files, err := filepath.Glob("../../../profiles/*.yaml")
	if err != nil || len(files) == 0 {
		t.Fatalf("profiles: %v (%d files)", err, len(files))
	}
	root := t.TempDir()
	var renderer *Renderer
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		var p Profile
		if err := yaml.Unmarshal(data, &p); err != nil {
			t.Fatal(err)
		}
		if renderer == nil {
			renderer = NewRenderer(&p, root)
			err = renderer.RenderAll()
		} else {
			err = renderer.SwitchProfile(&p)
		}
		if err != nil {
			t.Fatalf("%s: %v", file, err)
		}
		for _, dev := range p.Devices {
			for _, suffix := range []string{"driver/module/version", "product_name"} {
				path := filepath.Join(root, "sys/class/drm", fmt.Sprintf("card%d", dev.Index), "device", suffix)
				got, err := os.ReadFile(path)
				want := p.System.AMDGPUVersion
				if suffix == "product_name" {
					want = p.DeviceDefault.SysfsProductName()
				}
				if err != nil || string(got) != want+"\n" {
					t.Fatalf("%s %s: got %q, want %q, err=%v", file, path, got, want, err)
				}
			}
			path := filepath.Join(root, "sys/bus/pci/devices", dev.PCIBDF, "driver/module/version")
			if _, err := os.Stat(path); err != nil {
				t.Fatalf("%s: broken PCI driver path: %v", file, err)
			}
		}
	}
}
