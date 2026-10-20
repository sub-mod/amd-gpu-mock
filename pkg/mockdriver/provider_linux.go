// SPDX-License-Identifier: Apache-2.0
// Package mockdriver supplies optional openable devices. It does not emulate
// the AMD kernel driver: unsupported reads/writes/ioctls fail explicitly.
package mockdriver

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/amd-gpu-mock/pkg/gpu/kfd"
	"golang.org/x/sys/unix"
)

type endpoint struct {
	cmd   *exec.Cmd
	done  chan struct{}
	minor uint32
	paths []string
}

type Provider struct {
	previousMajor                 uint32
	root, hostDev, helper, prefix string
	major                         uint32
	endpoints                     map[uint32]*endpoint
	mu                            sync.Mutex
	closing                       bool
	Errors                        chan error
}

func New(root, hostDev, helper string) (*Provider, error) {
	st, err := os.Stat("/dev/cuse")
	if err != nil || st.Mode()&os.ModeCharDevice == 0 {
		return nil, fmt.Errorf("CUSE backend requires host /dev/cuse; load the matching cuse kernel module")
	}
	if _, err := exec.LookPath(helper); err != nil {
		return nil, err
	}
	if _, err := os.Stat("/sys/module/amdgpu"); err == nil {
		return nil, fmt.Errorf("CUSE backend requires a CPU-only node without the real amdgpu module")
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	hostname, err := os.Hostname()
	if err != nil {
		return nil, err
	}
	hash := sha256.Sum256([]byte(hostname + ":" + abs))
	var previous uint32
	if data, err := os.ReadFile(filepath.Join(abs, "device-major")); err == nil {
		_, _ = fmt.Sscan(string(data), &previous)
	}
	return &Provider{previousMajor: previous, root: abs, hostDev: hostDev, helper: helper, prefix: fmt.Sprintf("amd-mock-%x", hash[:6]), endpoints: make(map[uint32]*endpoint), Errors: make(chan error, 1)}, nil
}

// Reconcile supports the main renderer's physical and fixed partition inventory.
// Registration is kernel-backed; majors are never guessed or borrowed from a
// real GPU. One major is reserved by KFD and shared by all this provider's nodes.
func (p *Provider) Reconcile(profile *kfd.Profile) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	wanted := map[uint32][]string{255: {"kfd"}}
	for _, dev := range profile.Devices {
		if dev.Index < 0 || dev.Index >= 64 || dev.DRMRenderMinor != 128+dev.Index {
			return fmt.Errorf("CUSE requires contiguous DRM indices below 64")
		}
		wanted[uint32(dev.Index)] = []string{fmt.Sprintf("dri/card%d", dev.Index)}
		wanted[uint32(dev.DRMRenderMinor)] = []string{fmt.Sprintf("dri/renderD%d", dev.DRMRenderMinor)}
	}
	if _, ok := p.endpoints[255]; !ok {
		if err := p.start(255, wanted[255]); err != nil {
			return err
		}
	}
	for minor, paths := range wanted {
		if _, ok := p.endpoints[minor]; !ok {
			if err := p.start(minor, paths); err != nil {
				return err
			}
		}
	}
	for minor, e := range p.endpoints {
		if _, ok := wanted[minor]; !ok {
			p.stop(e)
			delete(p.endpoints, minor)
		}
	}
	for _, e := range p.endpoints {
		if err := p.nodes(e); err != nil {
			return err
		}
	}
	// Consumers only accept device handles bearing this live provider's major.
	path := filepath.Join(p.root, "device-major")
	if err := os.WriteFile(path+".tmp", []byte(fmt.Sprintln(p.major)), 0644); err != nil {
		return err
	}
	return os.Rename(path+".tmp", path)
}

func (p *Provider) start(minor uint32, paths []string) error {
	name := fmt.Sprintf("%s-%d", p.prefix, minor)
	cmd := exec.Command(p.helper, name, strconv.Itoa(int(p.major)), strconv.Itoa(int(minor)))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	e := &endpoint{cmd: cmd, done: make(chan struct{}), minor: minor, paths: paths}
	p.endpoints[minor] = e
	go func() {
		err := cmd.Wait()
		close(e.done)
		p.mu.Lock()
		expected := p.closing || p.endpoints[minor] != e
		p.mu.Unlock()
		if !expected {
			select {
			case p.Errors <- fmt.Errorf("CUSE endpoint %s exited: %v", name, err):
			default:
			}
		}
	}()
	for i := 0; i < 100; i++ {
		data, err := os.ReadFile(filepath.Join("/sys/class/cuse", name, "dev"))
		if err == nil {
			var major, registeredMinor uint32
			if _, err := fmt.Sscanf(strings.TrimSpace(string(data)), "%d:%d", &major, &registeredMinor); err != nil {
				return err
			}
			if registeredMinor != minor || (p.major != 0 && p.major != major) {
				return fmt.Errorf("unexpected CUSE registration %s", data)
			}
			p.major = major
			return nil
		}
		select {
		case <-e.done:
			return fmt.Errorf("CUSE endpoint %s failed to register", name)
		default:
		}
		time.Sleep(50 * time.Millisecond)
	}
	return fmt.Errorf("CUSE registration timed out: %s", name)
}

func (p *Provider) nodes(e *endpoint) error {
	for _, rel := range e.paths {
		for _, base := range []string{filepath.Join(p.root, "dev"), p.hostDev} {
			path := filepath.Join(base, rel)
			if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
				return err
			}
			var st unix.Stat_t
			if err := unix.Lstat(path, &st); err == nil {
				if st.Mode&unix.S_IFMT == unix.S_IFCHR && uint64(st.Rdev) == unix.Mkdev(p.major, e.minor) {
					continue
				}
				// Refuse an unrelated real driver device. Stale mock nodes are allowed
				// only for main's fixed legacy numbers or this provider's current major.
				if st.Mode&unix.S_IFMT == unix.S_IFCHR && unix.Major(uint64(st.Rdev)) != p.major && unix.Major(uint64(st.Rdev)) != 226 && unix.Major(uint64(st.Rdev)) != 234 && unix.Major(uint64(st.Rdev)) != p.previousMajor {
					return fmt.Errorf("refusing unrelated device %s", path)
				}
				if st.Mode&unix.S_IFMT == unix.S_IFCHR {
					registered := fmt.Sprintf("/sys/dev/char/%d:%d", unix.Major(uint64(st.Rdev)), unix.Minor(uint64(st.Rdev)))
					if _, err := os.Stat(registered); err == nil {
						return fmt.Errorf("refusing registered unrelated device %s", path)
					}
				}
				if st.Mode&unix.S_IFMT == unix.S_IFCHR && base == p.hostDev {
					if _, err := os.Stat("/sys/module/amdgpu"); err == nil {
						return fmt.Errorf("CUSE backend requires a CPU-only node; real amdgpu module present")
					}
				}
				if err := os.Remove(path); err != nil {
					return err
				}
			} else if !os.IsNotExist(err) {
				return err
			}
			if err := unix.Mknod(path, unix.S_IFCHR|0660, int(unix.Mkdev(p.major, e.minor))); err != nil {
				return fmt.Errorf("mknod %s: %w", path, err)
			}
			if err := os.Chmod(path, 0660); err != nil {
				return err
			}
		}
	}
	return nil
}

// RestoreDevice keeps crash/recovery from recreating main's legacy stat-only
// major/minor pair. The same registered endpoints survive a simulated fault.
func (p *Provider) RestoreDevice(index int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, minor := range []uint32{uint32(index), uint32(128 + index)} {
		e, ok := p.endpoints[minor]
		if !ok {
			return fmt.Errorf("no CUSE endpoint for GPU %d", index)
		}
		if err := p.nodes(e); err != nil {
			return err
		}
	}
	return nil
}

// RemoveDevice removes only this provider's host nodes during a simulated crash.
// Staged CDI nodes remain backed; libdrm queries reject the unhealthy GPU.
func (p *Provider) RemoveDevice(index int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, minor := range []uint32{uint32(index), uint32(128 + index)} {
		e, ok := p.endpoints[minor]
		if !ok {
			return fmt.Errorf("no CUSE endpoint for GPU %d", index)
		}
		for _, rel := range e.paths {
			path := filepath.Join(p.hostDev, rel)
			var st unix.Stat_t
			if unix.Lstat(path, &st) == nil && st.Mode&unix.S_IFMT == unix.S_IFCHR && uint64(st.Rdev) == unix.Mkdev(p.major, e.minor) {
				if err := os.Remove(path); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

func (p *Provider) stop(e *endpoint) {
	// Caller removes the endpoint before its waiter classifies the exit.
	delete(p.endpoints, e.minor)
	_ = e.cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-e.done:
	case <-time.After(2 * time.Second):
		_ = e.cmd.Process.Kill()
		<-e.done
	}
	for _, rel := range e.paths {
		for _, base := range []string{filepath.Join(p.root, "dev"), p.hostDev} {
			path := filepath.Join(base, rel)
			var st unix.Stat_t
			if unix.Lstat(path, &st) == nil && st.Mode&unix.S_IFMT == unix.S_IFCHR && uint64(st.Rdev) == unix.Mkdev(p.major, e.minor) {
				_ = os.Remove(path)
			}
		}
	}
}

func (p *Provider) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.closing = true
	for _, e := range p.endpoints {
		p.stop(e)
	}
	_ = os.Remove(filepath.Join(p.root, "device-major"))
}
