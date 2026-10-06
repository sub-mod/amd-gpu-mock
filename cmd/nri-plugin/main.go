package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"strings"

	"github.com/containerd/nri/pkg/api"
	"github.com/containerd/nri/pkg/stub"
)

const (
	pluginName  = "amd-gpu-mock"
	pluginIndex = "10"
)

type plugin struct {
	stub stub.Stub

	overlayHostPath string
	overlayMountPath string
	excludedNS      map[string]bool
	optOutAnnotation string
	deviceAnnotation string
}

func main() {
	overlayHost := flag.String("overlay-host", "/var/lib/amd-gpu-mock", "host path of the staged mock overlay")
	overlayMount := flag.String("overlay-mount", "/opt/amd-gpu-mock", "path to mount the overlay inside containers")
	excludeNS := flag.String("excluded-namespaces", "kube-system", "comma-separated namespaces to skip")
	releaseNS := flag.String("release-namespace", "amd-mock", "the release namespace (always excluded)")
	flag.Parse()

	excluded := make(map[string]bool)
	excluded[*releaseNS] = true
	for _, ns := range strings.Split(*excludeNS, ",") {
		ns = strings.TrimSpace(ns)
		if ns != "" {
			excluded[ns] = true
		}
	}

	p := &plugin{
		overlayHostPath:  *overlayHost,
		overlayMountPath: *overlayMount,
		excludedNS:       excluded,
		optOutAnnotation: "amd-gpu-mock.amd.com/inject",
		deviceAnnotation: "amd-gpu-mock.amd.com/devices",
	}

	var err error
	p.stub, err = stub.New(p,
		stub.WithPluginName(pluginName),
		stub.WithPluginIdx(pluginIndex),
	)
	if err != nil {
		log.Fatalf("failed to create NRI stub: %v", err)
	}

	log.Printf("amd-gpu-mock NRI plugin starting (overlay: %s → %s)", *overlayHost, *overlayMount)
	log.Printf("excluded namespaces: %v", excluded)

	ctx := context.Background()
	if err := p.stub.Run(ctx); err != nil {
		log.Fatalf("NRI plugin exited: %v", err)
	}
}

func (p *plugin) CreateContainer(_ context.Context, pod *api.PodSandbox, ctr *api.Container) (*api.ContainerAdjustment, []*api.ContainerUpdate, error) {
	ns := pod.GetNamespace()

	// Skip excluded namespaces.
	if p.excludedNS[ns] {
		return nil, nil, nil
	}

	// Skip if pod has opt-out annotation.
	if v, ok := pod.GetAnnotations()[p.optOutAnnotation]; ok && v == "false" {
		return nil, nil, nil
	}

	// Only inject if the pod has the device annotation or holds a GPU allocation.
	annotations := pod.GetAnnotations()
	hasDeviceAnnotation := annotations[p.deviceAnnotation] == "true"
	hasGPUAllocation := containerHasGPU(ctr)

	if !hasDeviceAnnotation && !hasGPUAllocation {
		return nil, nil, nil
	}

	log.Printf("injecting AMD GPU mock into %s/%s container %s", ns, pod.GetName(), ctr.GetName())

	adj := &api.ContainerAdjustment{}

	// Mount the overlay read-only.
	adj.AddMount(&api.Mount{
		Source:      p.overlayHostPath,
		Destination: p.overlayMountPath,
		Type:        "bind",
		Options:     []string{"rbind", "ro"},
	})

	// Mount KFD sysfs for GPU discovery.
	adj.AddMount(&api.Mount{
		Source:      p.overlayHostPath + "/sys/class/kfd",
		Destination: "/sys/class/kfd",
		Type:        "bind",
		Options:     []string{"rbind", "ro"},
	})

	// Mount driver module sysfs.
	adj.AddMount(&api.Mount{
		Source:      p.overlayHostPath + "/sys/module/amdgpu",
		Destination: "/sys/module/amdgpu",
		Type:        "bind",
		Options:     []string{"rbind", "ro"},
	})

	// Set environment for the mock library and ROCm.
	adj.AddEnv("LD_LIBRARY_PATH", fmt.Sprintf("/usr/lib64:%s/driver/usr/lib64", p.overlayMountPath))
	adj.AddEnv("MOCK_AMDSMI_CONFIG", p.overlayMountPath+"/config/config.yaml")
	adj.AddEnv("ROCR_VISIBLE_DEVICES", "all")
	adj.AddEnv("AMD_GPU_MOCK", "1")

	// Inject device nodes if the annotation requests them.
	if hasDeviceAnnotation {
		adj.AddDevice(&api.LinuxDevice{
			Path:  "/dev/kfd",
			Type:  "c",
			Major: 234,
			Minor: 0,
			FileMode: api.FileMode(0o660),
		})

		for i := 0; i < 8; i++ {
			adj.AddDevice(&api.LinuxDevice{
				Path:  fmt.Sprintf("/dev/dri/renderD%d", 128+i),
				Type:  "c",
				Major: 226,
				Minor: int64(128 + i),
				FileMode: api.FileMode(0o660),
			})
		}
	}

	return adj, nil, nil
}

func containerHasGPU(ctr *api.Container) bool {
	if ctr.GetLinux() == nil {
		return false
	}
	for _, dev := range ctr.GetLinux().GetDevices() {
		if strings.Contains(dev.GetPath(), "/dev/kfd") ||
			strings.Contains(dev.GetPath(), "/dev/dri/renderD") {
			return true
		}
	}
	return false
}
