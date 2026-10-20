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

// A consumer may hold a bind mount to sys/smi across a rolling agent update.
// Re-rendering must preserve those directory inodes and remove stale inventory.
func TestRerenderPreservesMountedDirectoriesAndDropsStaleGPUs(t *testing.T) {
	load := func(name string) *Profile {
		t.Helper()
		data, err := os.ReadFile("../../../profiles/" + name + ".yaml")
		if err != nil {
			t.Fatal(err)
		}
		p := &Profile{}
		if err := yaml.Unmarshal(data, p); err != nil {
			t.Fatal(err)
		}
		return p
	}
	root := t.TempDir()
	if err := NewRenderer(load("mi250x"), root).RenderAll(); err != nil {
		t.Fatal(err)
	}
	sysBefore, err := os.Stat(filepath.Join(root, "sys"))
	if err != nil {
		t.Fatal(err)
	}
	smiBefore, err := os.Stat(filepath.Join(root, "smi"))
	if err != nil {
		t.Fatal(err)
	}
	if err := NewRenderer(load("mi300a"), root).RenderAll(); err != nil {
		t.Fatal(err)
	}
	for name, previous := range map[string]os.FileInfo{"sys": sysBefore, "smi": smiBefore} {
		current, err := os.Stat(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		if !os.SameFile(previous, current) {
			t.Fatalf("%s directory inode replaced", name)
		}
	}
	nodes, err := os.ReadDir(filepath.Join(root, "sys/class/kfd/kfd/topology/nodes"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "smi/gpu15")); !os.IsNotExist(err) {
		t.Fatal("stale SMI GPU survived profile shrink")
	}
	if len(nodes) != 5 {
		t.Fatalf("stale KFD inventory: got %d nodes, want CPU + 4 GPUs", len(nodes))
	}
}
