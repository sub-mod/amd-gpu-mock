package kfd

import (
	"math"
	"math/rand"
	"sync"
	"time"
)

// DynamicSimulator produces time-varying GPU metrics that look realistic.
// Temperature ramps with a sine wave, power fluctuates around a base,
// and utilization follows a configurable pattern.
type DynamicSimulator struct {
	mu      sync.Mutex
	running bool
	stop    chan struct{}
	state   *FleetState
	rng     *rand.Rand
	epoch   time.Time
	onTick  func(*GPUState)
}

func NewDynamicSimulator(state *FleetState, callbacks ...func(*GPUState)) *DynamicSimulator {
	var callback func(*GPUState)
	if len(callbacks) > 0 {
		callback = callbacks[0]
	}
	return &DynamicSimulator{
		onTick: callback,
		state:  state,
		rng:    rand.New(rand.NewSource(time.Now().UnixNano())),
		epoch:  time.Now(),
	}
}

func (d *DynamicSimulator) Start(intervalMs int) {
	d.mu.Lock()
	if d.running {
		d.mu.Unlock()
		return
	}
	d.running = true
	d.stop = make(chan struct{})
	d.mu.Unlock()

	go d.loop(time.Duration(intervalMs) * time.Millisecond)
}

func (d *DynamicSimulator) Stop() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.running {
		close(d.stop)
		d.running = false
	}
}

func (d *DynamicSimulator) loop(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-d.stop:
			return
		case <-ticker.C:
			d.tick()
		}
	}
}

func (d *DynamicSimulator) tick() {
	d.state.mu.Lock()
	defer d.state.mu.Unlock()
	defer func() {
		if d.onTick != nil {
			for i := range d.state.GPUs {
				d.onTick(&d.state.GPUs[i])
			}
		}
	}()

	elapsed := time.Since(d.epoch).Seconds()

	for i := range d.state.GPUs {
		gpu := &d.state.GPUs[i]

		if gpu.Status == "crashed" {
			continue
		}

		phase := float64(i) * 0.7

		// Temperature: sine ramp around base with noise
		baseTemp := 45.0
		rampC := 12.0
		rampPeriod := 120.0
		temp := baseTemp + rampC*math.Sin(2*math.Pi*elapsed/rampPeriod+phase)
		temp += float64(d.rng.Intn(5)) - 2
		if gpu.Status == "overheating" {
			temp = float64(gpu.TemperatureC)
		} else {
			gpu.TemperatureC = clampInt(int(temp), 30, 95)
		}

		// Utilization: steady pattern with per-GPU phase offset
		if gpu.UtilizationPct == 0 && gpu.Status == "healthy" {
			// Idle GPU gets slight background noise
			gpu.UtilizationPct = d.rng.Intn(8)
		} else if gpu.UtilizationPct > 50 {
			// Busy GPU fluctuates around its set point
			gpu.UtilizationPct = clampInt(gpu.UtilizationPct+d.rng.Intn(11)-5, 40, 100)
		}

		// Power: proportional to utilization with noise
		if gpu.Status != "crashed" && gpu.PowerCapW > 0 {
			basePower := float64(gpu.PowerCapW) * (0.15 + 0.85*float64(gpu.UtilizationPct)/100.0)
			basePower += float64(d.rng.Intn(20)) - 10
			gpu.PowerW = clampInt(int(basePower), 50, gpu.PowerCapW)
		}

		// Clocks: higher when busy
		if gpu.UtilizationPct > 20 {
			gpu.ClockGFXMHz = 1800 + d.rng.Intn(300)
		} else {
			gpu.ClockGFXMHz = 400 + d.rng.Intn(200)
		}
	}
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
