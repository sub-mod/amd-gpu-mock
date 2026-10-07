//go:build dradiscovery

// Command probe checks amd-gpu-mock against the GPU discovery code in AMD's
// DRA driver (github.com/ROCm/k8s-gpu-dra-driver/pkg/amdgpu), unmodified.
//
//	probe render <profile.yaml> <root>   render the mock sysfs tree under <root>
//	probe check  <profile.yaml>          run AMD's discovery against /sys and
//	                                     compare each device with the profile
//
// AMD's code reads hardcoded /sys paths, so "check" must run with the
// rendered tree mounted at /sys. tests/dra/discovery-check.sh does that in a
// private mount namespace, and builds this file in GOPATH mode so it can use
// AMD's package without pulling in the driver's whole module (which needs a
// newer Go and the Kubernetes dependency tree). The build tag keeps this file
// out of "go build ./..." in module mode.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"amdgpumock/kfd"

	"github.com/ROCm/k8s-gpu-dra-driver/pkg/amdgpu"
	"gopkg.in/yaml.v3"
)

func main() {
	if len(os.Args) < 3 {
		usage()
	}
	p := loadProfile(os.Args[2])
	if mode := os.Getenv("PARTITION_MODE"); mode != "" {
		var err error
		p, err = kfd.PartitionProfile(p, mode)
		if err != nil {
			fatalf("partition: %v", err)
		}
	}
	switch os.Args[1] {
	case "render":
		if len(os.Args) != 4 {
			usage()
		}
		if err := kfd.NewRenderer(p, os.Args[3]).RenderAll(); err != nil {
			fatalf("render: %v", err)
		}
	case "check":
		if n := check(p); n > 0 {
			fmt.Printf("FAIL: %d mismatch(es)\n", n)
			os.Exit(1)
		}
		fmt.Println("PASS")
	default:
		usage()
	}
}

func check(p *kfd.Profile) int {
	fails := 0
	failf := func(format string, a ...any) {
		fails++
		fmt.Printf("  FAIL "+format+"\n", a...)
	}

	// The DRA chart's driver-init container loops until these exist.
	for _, dir := range []string{"/sys/class/kfd", "/sys/module/amdgpu/drivers"} {
		if fi, err := os.Stat(dir); err != nil || !fi.IsDir() {
			failf("init container would wait forever: %s is not a directory", dir)
		}
	}

	got := amdgpu.GetAMDGPUs()
	if len(got) != len(p.Devices) {
		failf("AMD's discovery found %d devices, profile defines %d", len(got), len(p.Devices))
	}

	d := p.DeviceDefault
	// AMD's discovery turns the sysfs product_name into an attribute value
	// with this replacer.
	wantName := strings.NewReplacer(" ", "_", "(", "", ")", "").Replace(d.SysfsProductName())

	for _, dev := range p.Devices {
		if !bdfRe.MatchString(dev.PCIBDF) {
			failf("%s: not a lowercase extended BDF; Kubernetes rejects it as pciBusID", dev.PCIBDF)
		}
		key := dev.PCIBDF
		if dev.PartitionIndex > 0 {
			key = fmt.Sprintf("amdgpu_xcp_%d", dev.Index)
		}
		g, ok := got[key]
		if !ok {
			failf("%s: not discovered", dev.PCIBDF)
			continue
		}
		wantRoot, wantNUMA := rootComplex(p, dev.PCIBDF)
		if wantRoot == "" {
			failf("%s: not listed under any pcie_topology root complex, so it gets no PCI device, NUMA node or pcieRoot", dev.PCIBDF)
		}
		want := []struct {
			key  string
			want any
		}{
			{"pciAddr", dev.PCIBDF},
			{"card", dev.Index},
			{"renderD", dev.DRMRenderMinor},
			{"deviceID", fmt.Sprintf("0x%04x", d.DeviceID)},
			{"productName", wantName},
			{"driverVersion", p.System.AMDGPUVersion},
			{"cuCount", d.Compute.CUCount},
			{"simdCount", d.Compute.SIMDCount},
			{"vramBytes", d.Memory.VRAMSizeBytes},
			{"numaNode", wantNUMA},
			{"computePartitionType", strings.ToLower(d.Partition.Mode)},
			{"memoryPartitionType", strings.ToLower(d.Partition.NPSMode)},
		}
		for _, w := range want {
			if fmt.Sprint(g[w.key]) != fmt.Sprint(w.want) {
				failf("%s: %s = %q, want %q", dev.PCIBDF, w.key, fmt.Sprint(g[w.key]), fmt.Sprint(w.want))
			}
		}
		root, err := pcieRoot(dev.PCIBDF)
		if err != nil {
			failf("%s: pcieRoot: %v", dev.PCIBDF, err)
		} else if root != wantRoot {
			failf("%s: pcieRoot = %q, want %q", dev.PCIBDF, root, wantRoot)
		}
		fmt.Printf("  ok   %s card%v renderD%v %v cu=%v vram=%v numa=%v root=%s driver=%v\n",
			dev.PCIBDF, g["card"], g["renderD"], g["productName"], g["cuCount"],
			g["vramBytes"], g["numaNode"], root, g["driverVersion"])
	}
	return fails
}

// bdfRe is the format k8s.io/dynamic-resource-allocation/deviceattribute
// accepts for the standard pciBusID attribute.
var bdfRe = regexp.MustCompile(`^([0-9a-f]{4}):([0-9a-f]{2}):([0-9a-f]{2})\.([0-9a-f]{1})$`)

// pcieRoot resolves the PCIe root the way
// k8s.io/dynamic-resource-allocation/deviceattribute.GetPCIeRootAttributeByPCIBusID
// does (that package needs Go 1.25+, so it is mirrored here): follow
// /sys/bus/pci/devices/<BDF> and take the first element under /sys/devices.
func pcieRoot(bdf string) (string, error) {
	sysBusPath := filepath.Join("bus", "pci", "devices", bdf)
	target, err := os.Readlink(filepath.Join("/sys", sysBusPath))
	if err != nil {
		return "", err
	}
	if !filepath.IsAbs(target) {
		target = filepath.Clean(filepath.Join(filepath.Dir(sysBusPath), target))
	}
	if !strings.HasPrefix(target, filepath.Join("devices", "pci")) {
		return "", fmt.Errorf("symlink target %q must start with devices/pci", target)
	}
	if filepath.Base(target) != bdf {
		return "", fmt.Errorf("symlink target %q must end with %s", target, bdf)
	}
	return strings.Split(strings.TrimPrefix(target, "devices/"), "/")[0], nil
}

func rootComplex(p *kfd.Profile, bdf string) (string, int) {
	for _, rc := range p.PCIETopology.RootComplexes {
		for _, d := range rc.Devices {
			if d == bdf {
				return rc.ID, rc.NUMANode
			}
		}
	}
	return "", -1
}

func loadProfile(path string) *kfd.Profile {
	data, err := os.ReadFile(path)
	if err != nil {
		fatalf("%v", err)
	}
	var p kfd.Profile
	if err := yaml.Unmarshal(data, &p); err != nil {
		fatalf("%s: %v", path, err)
	}
	return &p
}

func usage() {
	fatalf("usage: probe render <profile.yaml> <root> | probe check <profile.yaml>")
}

func fatalf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", a...)
	os.Exit(2)
}
