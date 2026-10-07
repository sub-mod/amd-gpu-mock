package kfd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSMIStateProfilesAndUpdates(t *testing.T) {
	for slug, profile := range profilesForTest(t) {
		t.Run(slug, func(t *testing.T) {
			root := t.TempDir()
			r := NewRenderer(profile, root)
			if err := r.renderSMIState(); err != nil {
				t.Fatal(err)
			}
			count, err := os.ReadFile(filepath.Join(root, "smi/count"))
			if err != nil {
				t.Fatal(err)
			}
			if string(count) != fmt.Sprintf("%d\n", len(profile.Devices)) {
				t.Fatalf("count %q", count)
			}
			state := NewFleetState(profile, slug)
			g, ok := state.GetGPU(0)
			if !ok {
				t.Fatal("missing GPU")
			}
			g.TemperatureC = 72
			g.PowerW = 230
			g.ECCErrors = 7
			if err := r.WriteSMIState(&g); err != nil {
				t.Fatal(err)
			}
			data, err := os.ReadFile(filepath.Join(root, "smi/gpu0"))
			if err != nil {
				t.Fatal(err)
			}
			rows := strings.Split(strings.TrimSpace(string(data)), "\n")
			if len(rows) != 4 || !strings.HasPrefix(rows[0], "72 230 ") || rows[1] != g.Name || rows[2] != smiUUID(g.UUID) || rows[3] != g.PCIBDF {
				t.Fatalf("invalid snapshot %q", data)
			}
			files, _ := filepath.Glob(filepath.Join(root, "smi/.gpu-*"))
			if len(files) != 0 {
				t.Fatal("temporary files leaked")
			}
		})
	}
}

func TestDynamicTelemetryReachesSMIBackend(t *testing.T) {
	p := profilesForTest(t)["mi300x"]
	root := t.TempDir()
	r := NewRenderer(p, root)
	state := NewFleetState(p, "mi300x")
	sim := NewDynamicSimulator(state, func(g *GPUState) {
		if err := r.WriteSMIState(g); err != nil {
			t.Fatal(err)
		}
	})
	sim.tick()
	g, _ := state.GetGPU(0)
	data, err := os.ReadFile(filepath.Join(root, "smi/gpu0"))
	if err != nil {
		t.Fatal(err)
	}
	expected := fmt.Sprintf("%d %d %d %d", g.TemperatureC, g.PowerW, g.PowerCapW, g.UtilizationPct)
	if !strings.HasPrefix(string(data), expected) {
		t.Fatalf("state not synchronized: %q", data)
	}
}
