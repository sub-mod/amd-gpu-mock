package kfd

import (
	"gopkg.in/yaml.v3"
	"os"
	"path/filepath"
	"testing"
)

type recordingBackend struct {
	profiles int
	restored []int
}

func (b *recordingBackend) Reconcile(p *Profile) error   { b.profiles++; return nil }
func (b *recordingBackend) RemoveDevice(index int) error { return nil }
func (b *recordingBackend) RestoreDevice(index int) error {
	b.restored = append(b.restored, index)
	return nil
}
func TestRendererBackendProfileAndRecovery(t *testing.T) {
	data, err := os.ReadFile("../../../profiles/mi300x.yaml")
	if err != nil {
		t.Fatal(err)
	}
	profile := &Profile{}
	err = yaml.Unmarshal(data, profile)
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	backend := &recordingBackend{}
	r := NewRenderer(profile, root)
	r.SetDeviceBackend(backend)
	if err := r.RenderAll(); err != nil {
		t.Fatal(err)
	}
	if backend.profiles != 1 {
		t.Fatal("initial devices not reconciled")
	}
	if err := r.SwitchProfile(profile); err != nil {
		t.Fatal(err)
	}
	if backend.profiles != 2 {
		t.Fatal("profile switch did not reconcile devices")
	}
	state := NewFleetState(profile, "mi300x")
	if err := r.UpdateGPUSysfs(&state.GPUs[0]); err != nil {
		t.Fatal(err)
	}
	if len(backend.restored) != 1 || backend.restored[0] != 0 {
		t.Fatal("recovery bypassed backend")
	}
	if _, err := os.Stat(filepath.Join(root, "sys/class/kfd/kfd/topology/nodes/1/properties")); err != nil {
		t.Fatal(err)
	}
}
