package kfd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// CDI spec structure — matches the Container Device Interface specification
// and the format that AMD's amd-ctk (ROCm/container-toolkit) generates.

type CDISpec struct {
	CDIVersion string      `json:"cdiVersion"`
	Kind       string      `json:"kind"`
	Devices    []CDIDevice `json:"devices"`
}

type CDIDevice struct {
	Name           string       `json:"name"`
	ContainerEdits CDIContEdits `json:"containerEdits"`
}

type CDIContEdits struct {
	DeviceNodes []CDIDeviceNode `json:"deviceNodes,omitempty"`
	Env         []string        `json:"env,omitempty"`
}

type CDIDeviceNode struct {
	Path        string `json:"path"`
	HostPath    string `json:"hostPath"`
	Permissions string `json:"permissions,omitempty"`
}

// GenerateCDISpec creates a CDI spec matching what amd-ctk cdi generate produces.
// Includes an "all" device entry (all GPUs) plus per-GPU entries (0, 1, 2, ...).
// Uses ROCR_VISIBLE_DEVICES to control which GPUs the ROCm runtime sees.
func GenerateCDISpec(profile *Profile, mockRoot string) *CDISpec {
	spec := &CDISpec{
		CDIVersion: "0.7.0",
		Kind:       "amd.com/gpu",
		Devices:    make([]CDIDevice, 0, len(profile.Devices)+1),
	}

	kfdHostPath := filepath.Join(mockRoot, "dev/kfd")

	// "all" device — includes every render node on the node.
	allDevice := CDIDevice{
		Name: "all",
		ContainerEdits: CDIContEdits{
			DeviceNodes: []CDIDeviceNode{
				{Path: "/dev/kfd", HostPath: kfdHostPath, Permissions: "rw"},
			},
			Env: []string{"ROCR_VISIBLE_DEVICES=all"},
		},
	}
	for _, dev := range profile.Devices {
		renderPath := fmt.Sprintf("/dev/dri/renderD%d", dev.DRMRenderMinor)
		allDevice.ContainerEdits.DeviceNodes = append(allDevice.ContainerEdits.DeviceNodes,
			CDIDeviceNode{
				Path:        renderPath,
				HostPath:    filepath.Join(mockRoot, fmt.Sprintf("dev/dri/renderD%d", dev.DRMRenderMinor)),
				Permissions: "rw",
			})
	}
	spec.Devices = append(spec.Devices, allDevice)

	// Per-GPU device entries.
	for _, dev := range profile.Devices {
		renderPath := fmt.Sprintf("/dev/dri/renderD%d", dev.DRMRenderMinor)
		device := CDIDevice{
			Name: fmt.Sprintf("%d", dev.Index),
			ContainerEdits: CDIContEdits{
				DeviceNodes: []CDIDeviceNode{
					{Path: "/dev/kfd", HostPath: kfdHostPath, Permissions: "rw"},
					{
						Path:        renderPath,
						HostPath:    filepath.Join(mockRoot, fmt.Sprintf("dev/dri/renderD%d", dev.DRMRenderMinor)),
						Permissions: "rw",
					},
				},
				Env: []string{fmt.Sprintf("ROCR_VISIBLE_DEVICES=%d", dev.Index)},
			},
		}
		spec.Devices = append(spec.Devices, device)
	}

	return spec
}

// WriteCDISpec writes the CDI spec to a JSON file.
func WriteCDISpec(spec *CDISpec, path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(spec, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling CDI spec: %w", err)
	}
	return os.WriteFile(path, data, 0o644)
}
