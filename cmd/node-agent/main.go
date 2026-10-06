package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/amd-gpu-mock/pkg/gpu/kfd"
	"gopkg.in/yaml.v3"
)

func main() {
	configPath := flag.String("config", "/etc/amd-gpu-mock/config.yaml", "path to GPU profile config")
	profilesDir := flag.String("profiles", "/etc/amd-gpu-mock/profiles", "directory containing all GPU profile YAML files")
	rootDir := flag.String("root", "/var/lib/amd-gpu-mock", "root directory for staged surfaces")
	apiAddr := flag.String("api", ":8080", "address for the status/control API and dashboard")
	flag.Parse()

	log.Printf("amd-gpu-mock node agent starting")
	log.Printf("config: %s", *configPath)
	log.Printf("root:   %s", *rootDir)

	data, err := os.ReadFile(*configPath)
	if err != nil {
		log.Fatalf("reading config: %v", err)
	}

	var profile kfd.Profile
	if err := yaml.Unmarshal(data, &profile); err != nil {
		log.Fatalf("parsing config: %v", err)
	}

	log.Printf("profile: %s (%d GPUs, %s)",
		profile.DeviceDefault.Name,
		len(profile.Devices),
		profile.DeviceDefault.Architecture)

	renderer := kfd.NewRenderer(&profile, *rootDir)

	if err := renderer.RenderAll(); err != nil {
		log.Fatalf("rendering surfaces: %v", err)
	}

	// Stage the mock library to the host overlay so other containers can use it.
	libSrc := "/usr/lib64/libamd_smi.so"
	libDst := filepath.Join(*rootDir, "driver/usr/lib64/libamd_smi.so")
	if data, err := os.ReadFile(libSrc); err == nil {
		os.MkdirAll(filepath.Dir(libDst), 0o755)
		os.WriteFile(libDst, data, 0o755)
		// Also create versioned symlink
		os.Symlink("libamd_smi.so", filepath.Join(filepath.Dir(libDst), "libamd_smi.so.27"))
		log.Printf("mock library staged: %s -> %s", libSrc, libDst)
	} else {
		log.Printf("warning: mock library not found at %s (non-fatal)", libSrc)
	}

	log.Printf("all surfaces staged at %s", *rootDir)
	log.Printf("kfd topology: %s/sys/class/kfd/kfd/topology/", *rootDir)
	log.Printf("device nodes: %s/dev/", *rootDir)
	log.Printf("pci sysfs:    %s/sys/bus/pci/devices/", *rootDir)
	log.Printf("driver module: %s/sys/module/amdgpu/", *rootDir)

	// Generate CDI spec for container device injection.
	// Written to both the mock root and /etc/cdi/ so the AMD container runtime
	// (amd-container-runtime) finds it when resolving CDI device references.
	cdiSpec := kfd.GenerateCDISpec(&profile, *rootDir)
	cdiPath := filepath.Join(*rootDir, "cdi/amd.json")
	if err := kfd.WriteCDISpec(cdiSpec, cdiPath); err != nil {
		log.Printf("warning: CDI spec generation failed: %v", err)
	} else {
		log.Printf("CDI spec:     %s (%d devices)", cdiPath, len(cdiSpec.Devices))
	}
	// Also write to /etc/cdi/ for the containerd CDI runtime path
	if err := kfd.WriteCDISpec(cdiSpec, "/etc/cdi/amd.json"); err != nil {
		log.Printf("warning: CDI spec at /etc/cdi/ failed (non-fatal): %v", err)
	} else {
		log.Printf("CDI spec:     /etc/cdi/amd.json (for amd-container-runtime)")
	}
	// And /var/run/cdi/ as fallback
	if err := kfd.WriteCDISpec(cdiSpec, "/var/run/cdi/amd.json"); err != nil {
		log.Printf("warning: CDI spec at /var/run/cdi/ failed (non-fatal): %v", err)
	}

	// Create device nodes with mknod if running as root.
	if os.Getuid() == 0 {
		if err := createDeviceNodes(&profile, *rootDir); err != nil {
			log.Printf("warning: device node creation in mock root failed (non-fatal): %v", err)
		}
		// Also create device nodes at the real /dev on the host.
		// The device plugin tells kubelet to expose /dev/kfd and
		// /dev/dri/renderD* to workload containers. Those paths must
		// exist on the host for kubelet's device mount to succeed.
		if err := createDeviceNodes(&profile, ""); err != nil {
			log.Printf("warning: device node creation in /dev failed (non-fatal): %v", err)
		}
	}

	// Derive the profile slug from the config filename (e.g. "mi300x" from ".../mi300x.yaml").
	initialSlug := strings.TrimSuffix(filepath.Base(*configPath), filepath.Ext(*configPath))
	if initialSlug == "config" {
		initialSlug = "mi300x"
	}

	// Start the API server for the dashboard and runtime control.
	state := kfd.NewFleetState(&profile, initialSlug)
	if err := state.LoadProfiles(*profilesDir); err != nil {
		log.Printf("warning: loading profile catalog from %s: %v", *profilesDir, err)
	} else {
		// Helm mounts every selected profile as config.yaml. Bind API state to
		// its actual catalog slug rather than treating every profile as MI300X.
		if filepath.Base(*configPath) == "config.yaml" {
			for slug, catalogProfile := range state.Profiles {
				if catalogProfile.DeviceDefault.Name == profile.DeviceDefault.Name {
					for i := range state.GPUs {
						state.GPUs[i].ProfileSlug = slug
					}
					state.Profiles[slug] = &profile
					break
				}
			}
		}
		log.Printf("loaded %d profiles from %s", len(state.ProfileCatalog), *profilesDir)
	}
	sim := kfd.NewDynamicSimulator(state)
	sim.Start(1000)
	defer sim.Stop()

	api := kfd.NewAPIServer(state, renderer)
	go func() {
		if err := api.Start(*apiAddr); err != nil {
			log.Printf("API server error: %v", err)
		}
	}()
	log.Printf("dashboard: http://localhost%s", *apiAddr)

	// Wait for termination signal, then clean up.
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
	s := <-sig
	log.Printf("received %v, cleaning up", s)

	if err := renderer.Cleanup(); err != nil {
		log.Printf("cleanup error: %v", err)
	}
	log.Printf("shutdown complete")
}

func createDeviceNodes(profile *kfd.Profile, rootDir string) error {
	var devDir string
	if rootDir == "" {
		devDir = "/dev"
	} else {
		devDir = rootDir + "/dev"
	}

	// /dev/kfd — major 234 (common), minor 0
	kfdPath := devDir + "/kfd"
	if err := os.MkdirAll(filepath.Dir(kfdPath), 0o755); err != nil {
		return err
	}
	os.Remove(kfdPath)
	if err := syscall.Mknod(kfdPath, syscall.S_IFCHR|0o660, int(makedev(234, 0))); err != nil {
		return fmt.Errorf("mknod %s: %w", kfdPath, err)
	}
	log.Printf("created %s (234:0)", kfdPath)

	// /dev/dri/renderDN — major 226, minor 128+N
	// /dev/dri/cardN — major 226, minor N (device plugin exposes both)
	driDir := devDir + "/dri"
	if err := os.MkdirAll(driDir, 0o755); err != nil {
		return err
	}
	for _, dev := range profile.Devices {
		renderPath := fmt.Sprintf("%s/renderD%d", driDir, dev.DRMRenderMinor)
		os.Remove(renderPath)
		minor := uint32(dev.DRMRenderMinor)
		if err := syscall.Mknod(renderPath, syscall.S_IFCHR|0o660, int(makedev(226, minor))); err != nil {
			return fmt.Errorf("mknod %s: %w", renderPath, err)
		}
		log.Printf("created %s (226:%d)", renderPath, minor)

		cardPath := fmt.Sprintf("%s/card%d", driDir, dev.Index)
		os.Remove(cardPath)
		if err := syscall.Mknod(cardPath, syscall.S_IFCHR|0o660, int(makedev(226, uint32(dev.Index)))); err != nil {
			log.Printf("warning: mknod %s: %v", cardPath, err)
		} else {
			log.Printf("created %s (226:%d)", cardPath, dev.Index)
		}
	}

	return nil
}

func makedev(major, minor uint32) uint64 {
	return uint64(major)<<8 | uint64(minor)
}
