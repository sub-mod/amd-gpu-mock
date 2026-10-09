package kfd

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

func TestRenderDeviceNodesAfterUncleanShutdown(t *testing.T) {
	root := t.TempDir()
	p := &Profile{Devices: []DeviceConfig{{DRMRenderMinor: 128}}}
	r := NewRenderer(p, root)
	if err := r.renderDeviceNodes(); err != nil {
		t.Fatal(err)
	}
	paths := []string{filepath.Join(root, "dev/kfd"), filepath.Join(root, "dev/dri/renderD128")}
	for _, path := range paths {
		if err := os.Remove(path); err != nil {
			t.Fatal(err)
		}
		if err := syscall.Mknod(path, syscall.S_IFCHR|0600, int(uint64(234)<<8)); err != nil {
			if err == syscall.EPERM {
				t.Skip("requires CAP_MKNOD; run in privileged Linux test container")
			}
			t.Fatal(err)
		}
	}
	before := make([]os.FileInfo, len(paths))
	for i, path := range paths {
		before[i], _ = os.Lstat(path)
	}
	for n := 0; n < 2; n++ {
		if err := r.renderDeviceNodes(); err != nil {
			t.Fatalf("restart %d: %v", n, err)
		}
	}
	for i, path := range paths {
		after, err := os.Lstat(path)
		if err != nil {
			t.Fatal(err)
		}
		if after.Mode()&os.ModeCharDevice == 0 || !os.SameFile(before[i], after) {
			t.Fatalf("device replaced: %s", path)
		}
	}
}
