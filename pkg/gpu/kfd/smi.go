package kfd

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
)

// The AMD SMI replacement reads this device state, not Prometheus responses.
// Atomic replacement prevents partial reads while telemetry is changing.
func (r *Renderer) WriteSMIState(g *GPUState) error {
	dir := filepath.Join(r.rootDir, "smi")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	text := fmt.Sprintf("%d %d %d %d %d %d %d %d %d\n%s\n%s\n%s\n", g.TemperatureC, g.PowerW, g.PowerCapW, g.UtilizationPct, g.MemoryUsedMB, g.MemoryTotalMB, g.ECCErrors, g.ClockGFXMHz, g.ClockMemMHz, g.Name, smiUUID(g.UUID), g.PCIBDF)
	path := filepath.Join(dir, fmt.Sprintf("gpu%d", g.Index))
	tmp, err := os.CreateTemp(dir, ".gpu-")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(text); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(0644); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
func (r *Renderer) renderSMIState() error {
	state := NewFleetState(r.profile, "")
	gpus, _ := state.GetAll()
	for i := range gpus {
		if err := r.WriteSMIState(&gpus[i]); err != nil {
			return err
		}
	}
	return writeFile(filepath.Join(r.rootDir, "smi/count"), fmt.Sprintf("%d\n", len(gpus)))
}

// AMD GPU Agent parses the vendor API UUID as a hexadecimal UUID. Profile IDs
// are human-readable identifiers, so derive a stable canonical device UUID.
func smiUUID(id string) string {
	hash := sha256.Sum256([]byte(id))
	hash[6] = (hash[6] & 0x0f) | 0x80
	hash[8] = (hash[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", hash[:4], hash[4:6], hash[6:8], hash[8:10], hash[10:16])
}
