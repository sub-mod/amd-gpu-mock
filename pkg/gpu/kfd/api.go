package kfd

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
)

// APIServer serves GPU status and control endpoints.
type APIServer struct {
	state    *FleetState
	renderer *Renderer
	mux      *http.ServeMux
}

func NewAPIServer(state *FleetState, renderer *Renderer) *APIServer {
	s := &APIServer{state: state, renderer: renderer, mux: http.NewServeMux()}
	s.mux.HandleFunc("/api/gpus", s.handleGPUs)
	s.mux.HandleFunc("/api/gpus/", s.handleGPU)
	s.mux.HandleFunc("/api/system", s.handleSystem)
	s.mux.HandleFunc("/api/actions/crash", s.handleCrash)
	s.mux.HandleFunc("/api/actions/recover", s.handleRecover)
	s.mux.HandleFunc("/api/actions/busy", s.handleBusy)
	s.mux.HandleFunc("/api/actions/idle", s.handleIdle)
	s.mux.HandleFunc("/api/actions/overheat", s.handleOverheat)
	s.mux.HandleFunc("/api/actions/ecc-error", s.handleECCError)
	s.mux.HandleFunc("/api/profiles", s.handleProfiles)
	s.mux.HandleFunc("/api/profiles/switch", s.handleSwitchProfile)
	s.mux.HandleFunc("/api/profiles/switch-tray", s.handleSwitchTray)
	s.mux.HandleFunc("/api/trays", s.handleTrays)
	s.mux.HandleFunc("/api/trays/layout", s.handleTrayLayout)
	s.mux.HandleFunc("/api/partitions", s.handlePartitions)
	s.mux.HandleFunc("/api/partitions/set", s.handleSetPartition)
	s.mux.HandleFunc("/metrics", s.handleMetrics)
	s.mux.HandleFunc("/healthz", s.handleHealthz)
	s.mux.HandleFunc("/", s.handleDashboard)
	return s
}

func (s *APIServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *APIServer) Start(addr string) error {
	log.Printf("API server listening on %s", addr)
	return http.ListenAndServe(addr, s)
}

func (s *APIServer) handleGPUs(w http.ResponseWriter, r *http.Request) {
	gpus, sys := s.state.GetAll()
	trays := s.state.GetTrayInfo()
	writeJSON(w, map[string]any{"gpus": gpus, "system": sys, "trays": trays})
}

func (s *APIServer) handleGPU(w http.ResponseWriter, r *http.Request) {
	idx := parseGPUIndex(r.URL.Path, "/api/gpus/")
	if idx < 0 {
		http.Error(w, "invalid gpu index", http.StatusBadRequest)
		return
	}

	if r.Method == http.MethodPatch || r.Method == http.MethodPut {
		defer r.Body.Close()
		var patch json.RawMessage
		if err := json.NewDecoder(r.Body).Decode(&patch); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		gpu, ok := s.state.UpdateGPU(idx, patch)
		if !ok {
			http.Error(w, "gpu not found", http.StatusNotFound)
			return
		}
		s.syncSysfs(&gpu)
		log.Printf("GPU %d updated via API", idx)
		writeJSON(w, gpu)
		return
	}

	gpu, ok := s.state.GetGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	writeJSON(w, gpu)
}

func (s *APIServer) handleSystem(w http.ResponseWriter, r *http.Request) {
	_, sys := s.state.GetAll()
	writeJSON(w, sys)
}

// syncSysfs writes the current GPU state to the staged sysfs tree so
// that the device plugin and other filesystem consumers see the change.
func (s *APIServer) syncSysfs(gpu *GPUState) {
	if s.renderer == nil {
		return
	}
	if err := s.renderer.UpdateGPUSysfs(gpu); err != nil {
		log.Printf("warning: sysfs sync for GPU %d failed: %v", gpu.Index, err)
	}
}

// recoverGPU resets a GPU to healthy idle state using its profile defaults.
func (s *APIServer) recoverGPU(idx int) (GPUState, bool) {
	gpu, ok := s.state.GetGPU(idx)
	if !ok {
		return gpu, false
	}
	p, exists := s.state.Profiles[gpu.ProfileSlug]
	var temp, power, gfxClk, memClk, memUsed int
	if exists {
		d := p.DeviceDefault
		temp = int(d.Thermal.EdgeTempC)
		power = int(d.Power.CurrentSocketPowerW)
		gfxClk = int(d.Clocks.CurrentGFXClkMHz)
		memClk = int(d.Clocks.CurrentMemClkMHz)
		memUsed = int(d.Memory.VRAMUsedBytes / (1024 * 1024))
	} else {
		temp = 49
		power = 183
		gfxClk = 500
		memClk = 1300
		memUsed = 300
	}
	patch := json.RawMessage(fmt.Sprintf(
		`{"status":"healthy","utilization_pct":0,"temperature_c":%d,"power_w":%d,"clock_gfx_mhz":%d,"clock_mem_mhz":%d,"memory_used_mb":%d,"ecc_errors":0}`,
		temp, power, gfxClk, memClk, memUsed))
	return s.state.UpdateGPU(idx, patch)
}

func (s *APIServer) handleCrash(w http.ResponseWriter, r *http.Request) {
	idx := parseQueryIndex(r)
	if idx < 0 {
		http.Error(w, "?gpu=N required", http.StatusBadRequest)
		return
	}
	gpu, ok := s.state.GetGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	if gpu.Status == "crashed" {
		gpu, _ = s.recoverGPU(idx)
		log.Printf("GPU %d RECOVERED (toggle off crash) via API", idx)
	} else {
		patch := json.RawMessage(`{"status":"crashed","utilization_pct":0,"power_w":0,"clock_gfx_mhz":0,"clock_mem_mhz":0,"temperature_c":0}`)
		gpu, _ = s.state.UpdateGPU(idx, patch)
		log.Printf("GPU %d CRASHED via API", idx)
	}
	s.syncSysfs(&gpu)
	writeJSON(w, gpu)
}

func (s *APIServer) handleRecover(w http.ResponseWriter, r *http.Request) {
	idx := parseQueryIndex(r)
	if idx < 0 {
		http.Error(w, "?gpu=N required", http.StatusBadRequest)
		return
	}
	gpu, ok := s.recoverGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	log.Printf("GPU %d RECOVERED via API", idx)
	s.syncSysfs(&gpu)
	writeJSON(w, gpu)
}

func (s *APIServer) handleBusy(w http.ResponseWriter, r *http.Request) {
	idx := parseQueryIndex(r)
	if idx < 0 {
		http.Error(w, "?gpu=N required", http.StatusBadRequest)
		return
	}
	gpu, ok := s.state.GetGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	if gpu.UtilizationPct > 50 {
		gpu, _ = s.recoverGPU(idx)
		log.Printf("GPU %d set IDLE (toggle off busy) via API", idx)
	} else {
		utilPct := 85
		if v := r.URL.Query().Get("util"); v != "" {
			if u, err := strconv.Atoi(v); err == nil && u >= 0 && u <= 100 {
				utilPct = u
			}
		}
		memPct := 70
		if v := r.URL.Query().Get("mem"); v != "" {
			if m, err := strconv.Atoi(v); err == nil && m >= 0 && m <= 100 {
				memPct = m
			}
		}
		memUsed := gpu.MemoryTotalMB * memPct / 100
		patch := json.RawMessage(fmt.Sprintf(
			`{"status":"healthy","utilization_pct":%d,"memory_used_mb":%d,"power_w":%d,"clock_gfx_mhz":2100}`,
			utilPct, memUsed, gpu.PowerCapW*utilPct/100))
		gpu, _ = s.state.UpdateGPU(idx, patch)
		log.Printf("GPU %d set BUSY (%d%% util) via API", idx, utilPct)
	}
	s.syncSysfs(&gpu)
	writeJSON(w, gpu)
}

func (s *APIServer) handleIdle(w http.ResponseWriter, r *http.Request) {
	idx := parseQueryIndex(r)
	if idx < 0 {
		http.Error(w, "?gpu=N required", http.StatusBadRequest)
		return
	}
	gpu, ok := s.recoverGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	log.Printf("GPU %d set IDLE via API", idx)
	s.syncSysfs(&gpu)
	writeJSON(w, gpu)
}

func (s *APIServer) handleOverheat(w http.ResponseWriter, r *http.Request) {
	idx := parseQueryIndex(r)
	if idx < 0 {
		http.Error(w, "?gpu=N required", http.StatusBadRequest)
		return
	}
	gpu, ok := s.state.GetGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	if gpu.Status == "overheating" {
		gpu, _ = s.recoverGPU(idx)
		log.Printf("GPU %d COOLED (toggle off overheat) via API", idx)
	} else {
		temp := 105
		if v := r.URL.Query().Get("temp"); v != "" {
			if t, err := strconv.Atoi(v); err == nil {
				temp = t
			}
		}
		patch := json.RawMessage(fmt.Sprintf(`{"status":"overheating","temperature_c":%d}`, temp))
		gpu, _ = s.state.UpdateGPU(idx, patch)
		log.Printf("GPU %d OVERHEATING (%d°C) via API", idx, temp)
	}
	s.syncSysfs(&gpu)
	writeJSON(w, gpu)
}

func (s *APIServer) handleECCError(w http.ResponseWriter, r *http.Request) {
	idx := parseQueryIndex(r)
	if idx < 0 {
		http.Error(w, "?gpu=N required", http.StatusBadRequest)
		return
	}
	gpu, ok := s.state.GetGPU(idx)
	if !ok {
		http.Error(w, "gpu not found", http.StatusNotFound)
		return
	}
	if gpu.Status == "ecc_error" {
		gpu, _ = s.recoverGPU(idx)
		log.Printf("GPU %d ECC CLEARED (toggle off) via API", idx)
	} else {
		count := 1
		if v := r.URL.Query().Get("count"); v != "" {
			if c, err := strconv.Atoi(v); err == nil && c > 0 {
				count = c
			}
		}
		newCount := gpu.ECCErrors + count
		patch := json.RawMessage(fmt.Sprintf(`{"status":"ecc_error","ecc_errors":%d}`, newCount))
		gpu, _ = s.state.UpdateGPU(idx, patch)
		log.Printf("GPU %d ECC ERROR (+%d, total %d) via API", idx, count, newCount)
	}
	s.syncSysfs(&gpu)
	writeJSON(w, gpu)
}

func (s *APIServer) handleProfiles(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, s.state.ProfileCatalog)
}

func (s *APIServer) handleSwitchProfile(w http.ResponseWriter, r *http.Request) {
	if s.renderer != nil && s.renderer.profile.DeviceDefault.Partition.Mode == "DPX" {
		http.Error(w, "fixed DPX/NPS2 topology: drain claims and restart with a new startup configuration", http.StatusConflict)
		return
	}

	slug := r.URL.Query().Get("profile")
	if slug == "" {
		http.Error(w, "?profile=<slug> required", http.StatusBadRequest)
		return
	}
	gpus, ok := s.state.SwitchProfile(slug)
	if !ok {
		http.Error(w, "profile not found: "+slug, http.StatusNotFound)
		return
	}
	if s.renderer != nil {
		if p, exists := s.state.Profiles[slug]; exists {
			if err := s.renderer.SwitchProfile(p); err != nil {
				log.Printf("warning: sysfs re-render failed: %v", err)
			} else {
				log.Printf("sysfs re-rendered for profile: %s", slug)
			}
		}
	}
	log.Printf("Fleet switched to profile: %s", slug)
	writeJSON(w, gpus)
}

func (s *APIServer) handleSwitchTray(w http.ResponseWriter, r *http.Request) {
	if s.renderer != nil && s.renderer.profile.DeviceDefault.Partition.Mode == "DPX" {
		http.Error(w, "fixed DPX/NPS2 topology: drain claims and restart with a new startup configuration", http.StatusConflict)
		return
	}

	idx := parseQueryIndex(r)
	slug := r.URL.Query().Get("profile")
	if idx < 0 || slug == "" {
		http.Error(w, "?gpu=N&profile=<slug> required", http.StatusBadRequest)
		return
	}
	gpus, ok := s.state.SwitchTrayProfile(idx, slug)
	if !ok {
		http.Error(w, "gpu or profile not found", http.StatusNotFound)
		return
	}
	trayIdx := idx / ServerTraySize(len(gpus))
	log.Printf("Server Tray %d (GPUs %d-%d) switched to profile: %s",
		trayIdx, gpus[0].Index, gpus[len(gpus)-1].Index, slug)
	writeJSON(w, gpus)
}

func (s *APIServer) handleTrays(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, s.state.GetTrayInfo())
}

func (s *APIServer) handleTrayLayout(w http.ResponseWriter, r *http.Request) {
	gpus, _ := s.state.GetAll()
	currentName := ""
	if len(gpus) > 0 {
		currentName = gpus[0].Name
	}
	canSplit := ProfileAllowsSplit(currentName)

	writeJSON(w, map[string]any{
		"tray_size": ServerTraySize(len(gpus)),
		"can_split": canSplit,
		"gpu_count": len(gpus),
		"profile":   currentName,
	})
}

// Compute partition modes — AMD's GPU partitioning (equivalent of MIG).
// Compute partition modes supported by MI300X/MI325X/MI350X/MI355X.
// SPX=1 (full GPU), DPX=2, QPX=4, CPX=8 (one per XCD).
// TPX (3-way) is not supported on MI300X — removed.
var partitionModes = []map[string]any{
	{"mode": "SPX", "partitions": 1, "description": "Single Partition — full GPU"},
	{"mode": "DPX", "partitions": 2, "description": "Dual Partition"},
	{"mode": "QPX", "partitions": 4, "description": "Quad Partition"},
	{"mode": "CPX", "partitions": 8, "description": "Compute Partition — one per XCD"},
}

func (s *APIServer) handlePartitions(w http.ResponseWriter, r *http.Request) {
	gpus, _ := s.state.GetAll()
	current := "SPX"
	if len(gpus) > 0 {
		current = gpus[0].Partition
	}
	writeJSON(w, map[string]any{
		"current":   current,
		"available": partitionModes,
	})
}

func (s *APIServer) handleSetPartition(w http.ResponseWriter, r *http.Request) {
	if s.renderer != nil && s.renderer.profile.DeviceDefault.Partition.Mode == "DPX" {
		http.Error(w, "fixed DPX/NPS2 topology: drain claims and restart with a new startup configuration", http.StatusConflict)
		return
	}

	mode := r.URL.Query().Get("mode")
	if mode == "" {
		http.Error(w, "?mode=SPX|DPX|QPX|CPX required", http.StatusBadRequest)
		return
	}

	var partCount int
	for _, p := range partitionModes {
		if p["mode"] == mode {
			partCount = p["partitions"].(int)
		}
	}
	if partCount == 0 {
		http.Error(w, "invalid mode: "+mode, http.StatusBadRequest)
		return
	}

	s.state.SetPartitionMode(mode, partCount)
	log.Printf("Compute partition set to %s (%d partitions per GPU)", mode, partCount)

	gpus, sys := s.state.GetAll()
	writeJSON(w, map[string]any{
		"mode":       mode,
		"partitions": partCount,
		"total_gpus": len(gpus),
		"system":     sys,
	})
}

func (s *APIServer) handleMetrics(w http.ResponseWriter, r *http.Request) {
	gpus, _ := s.state.GetAll()
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	for _, g := range gpus {
		idx := fmt.Sprintf("%d", g.Index)
		bdf := g.PCIBDF
		model := g.Name
		fmt.Fprintf(w, "gpu_temperature{gpu_id=\"%s\",card_model=\"%s\",pci_bdf=\"%s\"} %d\n", idx, model, bdf, g.TemperatureC)
		fmt.Fprintf(w, "gpu_power{gpu_id=\"%s\",card_model=\"%s\",pci_bdf=\"%s\"} %d\n", idx, model, bdf, g.PowerW)
		fmt.Fprintf(w, "gpu_gfx_activity{gpu_id=\"%s\",card_model=\"%s\",pci_bdf=\"%s\"} %d\n", idx, model, bdf, g.UtilizationPct)
		fmt.Fprintf(w, "gpu_used_vram{gpu_id=\"%s\",card_model=\"%s\",pci_bdf=\"%s\"} %d\n", idx, model, bdf, g.MemoryUsedMB*1024*1024)
		fmt.Fprintf(w, "gpu_total_vram{gpu_id=\"%s\",card_model=\"%s\",pci_bdf=\"%s\"} %d\n", idx, model, bdf, g.MemoryTotalMB*1024*1024)
		fmt.Fprintf(w, "gpu_clock{gpu_id=\"%s\",card_model=\"%s\",clock_type=\"gfx\"} %d\n", idx, model, g.ClockGFXMHz)
		fmt.Fprintf(w, "gpu_clock{gpu_id=\"%s\",card_model=\"%s\",clock_type=\"mem\"} %d\n", idx, model, g.ClockMemMHz)
		fmt.Fprintf(w, "gpu_ecc_uncorrectable{gpu_id=\"%s\",card_model=\"%s\"} %d\n", idx, model, g.ECCErrors)
		fmt.Fprintf(w, "gpu_power_cap{gpu_id=\"%s\",card_model=\"%s\"} %d\n", idx, model, g.PowerCapW)
	}
}

func (s *APIServer) handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func (s *APIServer) handleDashboard(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(dashboardHTML))
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(v)
}

func parseGPUIndex(path, prefix string) int {
	s := strings.TrimPrefix(path, prefix)
	s = strings.TrimSuffix(s, "/")
	idx, err := strconv.Atoi(s)
	if err != nil {
		return -1
	}
	return idx
}

func parseQueryIndex(r *http.Request) int {
	v := r.URL.Query().Get("gpu")
	if v == "" {
		return -1
	}
	idx, err := strconv.Atoi(v)
	if err != nil {
		return -1
	}
	return idx
}
