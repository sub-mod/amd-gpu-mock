# GPU Profiles

Each profile is a YAML file describing an AMD GPU model. The node agent
reads it and renders all simulated surfaces from it.

## Available profiles

| Profile | GPU | Architecture | Memory | GPUs | xGMI | Status |
|---------|-----|-------------|--------|------|------|--------|
| `mi210` | AMD Instinct MI210 | CDNA 2 (gfx90a) | 64 GB HBM2e | 8 | 3 links | Available |
| `mi250x` | AMD Instinct MI250X | CDNA 2 (gfx90a) | 64 GB HBM2e per GCD | 16 (2 GCDs × 8 OAMs) | 8 links | Available |
| `mi300a` | AMD Instinct MI300A | CDNA 3 (gfx942) | 128 GB HBM3 | 4 | 7 links | Available |
| `mi300x` | AMD Instinct MI300X | CDNA 3 (gfx942) | 192 GB HBM3 | 8 | 7 links | Available |
| `mi325x` | AMD Instinct MI325X | CDNA 3 (gfx942) | 256 GB HBM3E | 8 | 8 links | Available |
| `mi350x` | AMD Instinct MI350X | CDNA 4 (gfx950) | 288 GB HBM3E | 8 | 7 links | Available |
| `mi355x` | AMD Instinct MI355X | CDNA 4 (gfx950) | 288 GB HBM3E | 8 | 7 links | Available |

## Profile YAML schema

```yaml
version: "1.0"

system:
  amdgpu_version: "6.19.4"        # Kernel amdgpu driver version
  rocm_version: "7.14.0"          # ROCm platform version
  amdsmi_version: "27.0.0"        # AMD SMI library version

device_defaults:
  name: "AMD Instinct MI300X"     # GPU name shown in amd-smi
  vendor_id: 0x1002               # Always 0x1002 for AMD
  device_id: 0x74a1               # PCI device ID
  gfx_target_version: 90402       # gfx942 encoded as MMMNNRR
  architecture: "cdna3"           # cdna2, cdna3, rdna3

  compute:                        # Compute unit configuration
    cu_count: 304
    simd_per_cu: 4
    simd_count: 1216
    wave_front_size: 64
    num_xcc: 8                    # XCD count (MI300X = 8)

  memory:                         # VRAM configuration
    vram_type: "hbm3"
    vram_size_bytes: 206158430208 # ~192 GB
    vram_bus_width: 8192

  power:                          # Power envelope
    default_power_cap_w: 750
    max_power_cap_w: 750

  thermal:                        # Temperature thresholds
    edge_temperature_c: 49
    hotspot_temperature_c: 52
    shutdown_temperature_c: 110

  clocks:                         # Clock speeds
    max_gfx_clk_mhz: 2100
    max_mem_clk_mhz: 1300

  pcie:                           # PCIe link
    gen: 5
    width: 16

  ecc:                            # ECC memory
    enabled: true

xgmi:                             # Inter-GPU interconnect
  hive_id: "0x..."
  links_per_gpu: 7
  bandwidth_per_link_gbps: 50

pcie_topology:                    # PCIe root complex layout
  root_complexes:
    - id: "pci0000:00"
      numa_node: 0
      devices: [...]

devices:                          # Per-GPU overrides
  - index: 0
    uuid: "GPU-..."
    pci_bdf: "0000:05:00.0"
    drm_render_minor: 128
```

## PCI device IDs

| GPU | Vendor:Device | lspci description |
|-----|--------------|-------------------|
| MI300X | `1002:74a1` | Aqua Vanjaram [Instinct MI300X] |
| MI300A | `1002:74a0` | Aqua Vanjaram [Instinct MI300A] |
| MI325X | `1002:74a5` | Aqua Vanjaram [Instinct MI325X] |
| MI250X | `1002:740c` | Aldebaran [Instinct MI250X] |
| MI210 | `1002:740f` | Aldebaran/MI200 [Instinct MI210] |

## Writing a custom profile

Copy an existing profile and modify:

```bash
cp profiles/mi300x.yaml profiles/my-custom.yaml
# Edit device_defaults, devices, xgmi, pcie_topology
```

Key fields to change for a new GPU model:
- `device_defaults.name` — GPU name
- `device_defaults.device_id` — PCI device ID
- `device_defaults.gfx_target_version` — GFX ISA
- `device_defaults.compute.*` — CU count, SIMD, XCC
- `device_defaults.memory.vram_size_bytes` — VRAM
- `xgmi.*` — interconnect topology
- `devices` — per-GPU BDFs and render minors

## Runtime and telemetry limits

Use `--set gpu.profile=<slug>` at installation for allocation tests. Healthy
telemetry varies dynamically rather than remaining at YAML defaults. The real
exporter reads runtime name, canonical device UUID, PCI BDF, memory and sensor
values through the [SMI bridge](guides/telemetry.md). Its initial ASIC metadata,
PCIe limits and clock ranges still use MI300X constants; all-profile telemetry
fidelity is not claimed. Allocation discovery tests separately cover all seven
profiles. Live profile switching requires consumer rediscovery; per-tray
switching lacks immediate renderer synchronization. Virtual partition state
does not create schedulable hardware slices.

## MI300X startup partitions

`gpu.profile=mi300x` with `gpu.partition=DPX` models DPX/NPS2 at startup.
Each parent becomes two schedulable devices with 96 GiB and 152 compute units,
shared parent BDF/KFD identity, and unique card/render nodes. The original
physical profile remains unchanged. Other model/mode combinations are rejected.
See [same-GPU partition allocation](guides/partition-allocation.md). Fixed DPX
blocks runtime profile, tray and virtual partition changes; it does not
implement real GPU execution, arbitrary slice sizes or hardware isolation.
