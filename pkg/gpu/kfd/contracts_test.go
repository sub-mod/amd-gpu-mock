package kfd

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func profilesForTest(t *testing.T) map[string]*Profile {
	t.Helper()
	files, err := filepath.Glob("../../../profiles/*.yaml")
	if err != nil || len(files) != 7 {
		t.Fatalf("expected seven profiles: %v (%d)", err, len(files))
	}
	result := map[string]*Profile{}
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		p := new(Profile)
		if err := yaml.Unmarshal(data, p); err != nil {
			t.Fatal(err)
		}
		result[strings.TrimSuffix(filepath.Base(file), ".yaml")] = p
	}
	return result
}

func TestProfileSysfsContract(t *testing.T) {
	for slug, p := range profilesForTest(t) {
		t.Run(slug, func(t *testing.T) {
			root := t.TempDir()
			r := NewRenderer(p, root)
			if err := r.RenderAll(); err != nil {
				t.Fatal(err)
			}
			read := func(path string) string {
				t.Helper()
				b, err := os.ReadFile(filepath.Join(root, path))
				if err != nil {
					t.Fatal(err)
				}
				return strings.TrimSpace(string(b))
			}
			for _, d := range p.Devices {
				base := fmt.Sprintf("sys/class/kfd/kfd/topology/nodes/%d", d.Index+1)
				if read(base+"/name") != p.DeviceDefault.Name {
					t.Fatal("KFD name differs from profile")
				}
				fields := strings.Fields(read(base + "/properties"))
				props := map[string]string{}
				for i := 0; i < len(fields); i += 2 {
					props[fields[i]] = fields[i+1]
				}
				for key, want := range map[string]uint32{"simd_count": p.DeviceDefault.Compute.SIMDCount, "gfx_target_version": p.DeviceDefault.GFXTargetVersion, "vendor_id": p.DeviceDefault.VendorID, "device_id": p.DeviceDefault.DeviceID, "drm_render_minor": uint32(128 + d.Index)} {
					if props[key] != strconv.FormatUint(uint64(want), 10) {
						t.Errorf("GPU %d %s: got %s want %d", d.Index, key, props[key], want)
					}
				}
				memory := strings.Fields(read(base + "/mem_banks/0/properties"))[3]
				if memory != strconv.FormatUint(p.DeviceDefault.Memory.VRAMSizeBytes, 10) {
					t.Fatal("VRAM differs from profile")
				}
			}
			// Runtime hooks require this mount destination on native AMD64 kind nodes.
			paths := []string{"sys/class/dmi/id/product_uuid", "sys/devices/virtual/dmi/id/product_uuid"}
			for _, path := range paths {
				if len(read(path)) != 36 {
					t.Fatal("invalid DMI UUID mount target: " + path)
				}
			}
			if err := r.SwitchProfile(p); err != nil {
				t.Fatal(err)
			}
			for _, path := range paths {
				if len(read(path)) != 36 {
					t.Fatal("DMI UUID target lost after profile switch: " + path)
				}
			}
		})
	}
}

func TestPartitionTransitions(t *testing.T) {
	p := profilesForTest(t)["mi300x"]
	state := NewFleetState(p, "mi300x")
	api := NewAPIServer(state, nil)
	for _, step := range []struct {
		mode  string
		parts int
	}{{"DPX", 2}, {"CPX", 8}, {"QPX", 4}, {"SPX", 1}, {"CPX", 8}, {"SPX", 1}} {
		response := httptest.NewRecorder()
		api.ServeHTTP(response, httptest.NewRequest("POST", "/api/partitions/set?mode="+step.mode, nil))
		if response.Code != 200 {
			t.Fatal(response.Body.String())
		}
		gpus, _ := state.GetAll()
		if len(gpus) != len(p.Devices)*step.parts {
			t.Fatalf("%s count=%d", step.mode, len(gpus))
		}
		ids := map[string]bool{}
		for i, gpu := range gpus {
			if ids[gpu.UUID] {
				t.Fatalf("%s duplicate GPU UUID %s", step.mode, gpu.UUID)
			}
			ids[gpu.UUID] = true
			if gpu.MemoryTotalMB != int(p.DeviceDefault.Memory.VRAMSizeBytes/(1024*1024))/step.parts {
				t.Fatalf("%s memory compounded", step.mode)
			}
			if gpu.PCIBDF != p.Devices[i/step.parts].PCIBDF {
				t.Fatalf("%s wrong physical GPU identity", step.mode)
			}
		}
	}
	before, _ := state.GetAll()
	response := httptest.NewRecorder()
	api.ServeHTTP(response, httptest.NewRequest("POST", "/api/partitions/set?mode=INVALID", nil))
	after, _ := state.GetAll()
	if response.Code != 400 || len(after) != len(before) {
		t.Fatal("invalid partition request mutated fleet")
	}
}

func TestFaultAPIRoundTrip(t *testing.T) {
	p := profilesForTest(t)["mi300x"]
	state := NewFleetState(p, "mi300x")
	api := NewAPIServer(state, nil)
	for _, action := range []string{"crash", "overheat", "ecc-error"} {
		response := httptest.NewRecorder()
		api.ServeHTTP(response, httptest.NewRequest("POST", "/api/actions/"+action+"?gpu=0", nil))
		if response.Code != 200 {
			t.Fatal(response.Body.String())
		}
		gpu, _ := state.GetGPU(0)
		if gpu.Status == "healthy" {
			t.Fatalf("%s had no effect", action)
		}
		response = httptest.NewRecorder()
		api.ServeHTTP(response, httptest.NewRequest("POST", "/api/actions/recover?gpu=0", nil))
		gpu, _ = state.GetGPU(0)
		if response.Code != 200 || gpu.Status != "healthy" || gpu.ECCErrors != 0 {
			t.Fatalf("%s recovery failed", action)
		}
	}
	response := httptest.NewRecorder()
	api.ServeHTTP(response, httptest.NewRequest("GET", "/api/gpus", nil))
	var body struct {
		GPUs []GPUState `json:"gpus"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || len(body.GPUs) != 8 {
		t.Fatal("API fleet serialization failed")
	}
}
