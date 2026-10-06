package kfd

const dashboardHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AMD GPU Mock Dashboard</title>
<style>
  :root {
    --bg: #0d1117; --card: #161b22; --border: #30363d;
    --text: #e6edf3; --dim: #8b949e; --accent: #ed1c24;
    --green: #3fb950; --yellow: #d29922; --red: #f85149; --blue: #58a6ff;
    --tray-a: #1a2332; --tray-b: #1a1a2e;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: var(--bg); color: var(--text); padding: 20px; }
  .header { display: flex; align-items: center; gap: 16px; margin-bottom: 16px;
            border-bottom: 1px solid var(--border); padding-bottom: 16px; }
  .header h1 { font-size: 22px; font-weight: 600; }
  .header .badge { background: var(--accent); color: #fff; padding: 3px 10px;
                   border-radius: 12px; font-size: 12px; font-weight: 600; }
  .sys-info { display: flex; gap: 24px; color: var(--dim); font-size: 13px; margin-left: auto; }
  .toolbar { display: flex; align-items: center; gap: 12px; margin-bottom: 20px;
             padding: 12px 16px; background: var(--card); border: 1px solid var(--border);
             border-radius: 8px; flex-wrap: wrap; }
  .toolbar label { font-size: 12px; color: var(--dim); text-transform: uppercase;
                   letter-spacing: 0.5px; }
  .toolbar select { background: var(--bg); color: var(--text); border: 1px solid var(--border);
                    border-radius: 4px; padding: 6px 10px; font-size: 13px; cursor: pointer; }
  .toolbar select:hover { border-color: var(--accent); }
  .toolbar .sep { width: 1px; height: 24px; background: var(--border); }
  .tray { margin-bottom: 24px; }
  .tray-header { display: flex; align-items: center; gap: 12px; margin-bottom: 12px;
                 padding: 8px 12px; border-radius: 6px; }
  .tray-header.tray-a { background: var(--tray-a); border-left: 3px solid var(--blue); }
  .tray-header.tray-b { background: var(--tray-b); border-left: 3px solid #a371f7; }
  .tray-label { font-size: 13px; font-weight: 600; }
  .tray-detail { font-size: 12px; color: var(--dim); }
  .tray-select { background: var(--bg); color: var(--text); border: 1px solid var(--border);
                 border-radius: 4px; padding: 4px 8px; font-size: 12px; cursor: pointer;
                 margin-left: auto; }
  .tray-select:hover { border-color: var(--accent); }
  .gpu-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 12px; }
  .gpu-card { background: var(--card); border: 1px solid var(--border); border-radius: 8px;
              padding: 14px; transition: border-color 0.2s; }
  .gpu-card:hover { border-color: var(--accent); }
  .gpu-card.crashed { border-color: var(--red); background: #1a0a0a; }
  .gpu-card.overheating { border-color: var(--yellow); }
  .gpu-card.ecc_error { border-color: var(--yellow); }
  .gpu-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
  .gpu-name { font-weight: 600; font-size: 14px; }
  .gpu-index { color: var(--dim); font-size: 12px; }
  .status { padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
  .status.healthy { background: #0d2818; color: var(--green); }
  .status.crashed { background: #2d0a0a; color: var(--red); }
  .status.overheating { background: #2d1f0a; color: var(--yellow); }
  .status.ecc_error { background: #2d1f0a; color: var(--yellow); }
  .metrics { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; margin-bottom: 10px; }
  .metric { background: var(--bg); border-radius: 6px; padding: 6px 8px; }
  .metric-label { font-size: 10px; color: var(--dim); text-transform: uppercase; letter-spacing: 0.5px; }
  .metric-value { font-size: 16px; font-weight: 600; margin-top: 1px; }
  .metric-value.warn { color: var(--yellow); }
  .metric-value.crit { color: var(--red); }
  .bar { height: 4px; background: var(--border); border-radius: 2px; margin-top: 3px; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 2px; transition: width 0.5s; }
  .bar-fill.low { background: var(--green); }
  .bar-fill.mid { background: var(--yellow); }
  .bar-fill.high { background: var(--red); }
  .gpu-footer { display: flex; gap: 5px; flex-wrap: wrap; }
  .btn { padding: 3px 8px; border-radius: 4px; border: 1px solid var(--border);
         background: var(--card); color: var(--dim); font-size: 11px; cursor: pointer;
         transition: all 0.15s; }
  .btn:hover { border-color: var(--accent); color: var(--text); background: #1a1a2e; }
  .btn.active-danger { border-color: var(--red); background: var(--red); color: #fff; }
  .btn.active-warn { border-color: var(--yellow); background: var(--yellow); color: #000; }
  .btn.active-ok { border-color: var(--green); background: var(--green); color: #000; }
  .info-row { display: flex; gap: 10px; font-size: 11px; color: var(--dim); margin-bottom: 6px; }
  .note { font-size: 11px; color: var(--dim); margin-top: 16px; padding: 10px 12px;
          background: var(--card); border: 1px solid var(--border); border-radius: 6px; }
</style>
</head>
<body>
<div class="header">
  <h1>AMD GPU Mock Dashboard</h1>
  <span class="badge">SIMULATED</span>
  <div class="sys-info">
    <span id="sys-driver"></span>
    <span id="sys-rocm"></span>
  </div>
</div>
<div class="toolbar">
  <label>Whole Fleet</label>
  <select id="fleet-select" onchange="switchFleetProfile(this.value)">
    <option value="">Loading...</option>
  </select>
  <div class="sep"></div>
  <span id="layout-info" style="font-size:12px;color:var(--dim)"></span>
</div>
<div id="rack"></div>
<div class="note">
  GPUs are grouped by <strong>server tray</strong>. All GPUs in a tray are always the
  same model — you cannot mix GPU types within a single server. Change the tray's model with
  the dropdown in each tray header. This reflects how real AMD Instinct servers are built.
</div>

<script>
const API = window.location.origin;
let profiles = [];
let trays = [];

function barClass(pct) { return pct < 50 ? 'low' : pct < 80 ? 'mid' : 'high'; }
function tempClass(c) { return c < 80 ? '' : c < 100 ? 'warn' : 'crit'; }

function profileOptions(currentSlug) {
  return profiles.map(p =>
    '<option value="' + p.slug + '"' + (p.slug === currentSlug ? ' selected' : '') + '>'
    + p.name + ' (' + p.memory_gb + ' GB, ' + p.tdp_w + 'W)</option>'
  ).join('');
}

function renderGPU(gpu) {
  const memPct = gpu.memory_total_mb > 0 ? Math.round(gpu.memory_used_mb / gpu.memory_total_mb * 100) : 0;
  const memGB = (gpu.memory_used_mb / 1024).toFixed(1);
  const totalGB = (gpu.memory_total_mb / 1024).toFixed(0);
  return ` + "`" + `
    <div class="gpu-card ${gpu.status}">
      <div class="gpu-header">
        <div>
          <div class="gpu-name">${gpu.name}</div>
          <div class="gpu-index">GPU ${gpu.index} &middot; ${gpu.pci_bdf} &middot; NUMA ${gpu.numa_node}</div>
        </div>
        <span class="status ${gpu.status}">${gpu.status}</span>
      </div>
      <div class="info-row">
        <span>${gpu.architecture.toUpperCase()}</span>
        <span>${gpu.partition || 'N/A'}</span>
        <span>ECC: ${gpu.ecc_errors}</span>
      </div>
      <div class="metrics">
        <div class="metric">
          <div class="metric-label">Temp</div>
          <div class="metric-value ${tempClass(gpu.temperature_c)}">${gpu.temperature_c}&deg;C</div>
        </div>
        <div class="metric">
          <div class="metric-label">Power</div>
          <div class="metric-value">${gpu.power_w}W / ${gpu.power_cap_w}W</div>
        </div>
        <div class="metric">
          <div class="metric-label">Utilization</div>
          <div class="metric-value">${gpu.utilization_pct}%</div>
          <div class="bar"><div class="bar-fill ${barClass(gpu.utilization_pct)}" style="width:${gpu.utilization_pct}%"></div></div>
        </div>
        <div class="metric">
          <div class="metric-label">Memory</div>
          <div class="metric-value">${memGB} / ${totalGB} GB</div>
          <div class="bar"><div class="bar-fill ${barClass(memPct)}" style="width:${memPct}%"></div></div>
        </div>
      </div>
      <div class="gpu-footer">
        <button class="btn ${gpu.status==='crashed'?'active-danger':''}" onclick="action('crash',${gpu.index})">Crash</button>
        <button class="btn ${gpu.status==='overheating'?'active-warn':''}" onclick="action('overheat',${gpu.index})">Overheat</button>
        <button class="btn ${gpu.status==='ecc_error'?'active-warn':''}" onclick="action('ecc-error',${gpu.index})">ECC Error</button>
        <button class="btn ${gpu.utilization_pct>50?'active-warn':''}" onclick="action('busy',${gpu.index})">Busy</button>
        <button class="btn ${gpu.status==='healthy'&&gpu.utilization_pct===0?'active-ok':''}" onclick="action('idle',${gpu.index})">Idle</button>
        <button class="btn ${gpu.status==='healthy'?'active-ok':''}" onclick="action('recover',${gpu.index})">Recover</button>
      </div>
    </div>
  ` + "`" + `;
}

function renderTray(trayIdx, trayGPUs, traySlug) {
  const trayClass = trayIdx === 0 ? 'tray-a' : 'tray-b';
  const trayLabel = 'Server Tray ' + String.fromCharCode(65 + trayIdx);
  const gpuRange = trayGPUs[0].index + '-' + trayGPUs[trayGPUs.length - 1].index;
  return ` + "`" + `
    <div class="tray">
      <div class="tray-header ${trayClass}">
        <span class="tray-label">${trayLabel}</span>
        <span class="tray-detail">GPUs ${gpuRange} &middot; ${trayGPUs.length}x ${trayGPUs[0].name}</span>
        <select class="tray-select" onchange="switchTray(${trayGPUs[0].index}, this.value)"
                title="Change all GPUs in this tray">
          ${profileOptions(traySlug)}
        </select>
      </div>
      <div class="gpu-grid">
        ${trayGPUs.map(renderGPU).join('')}
      </div>
    </div>
  ` + "`" + `;
}

async function loadProfiles() {
  try {
    const res = await fetch(API + '/api/profiles');
    profiles = await res.json();
    if (!profiles || profiles.length === 0) profiles = [];
  } catch (e) { profiles = []; }
}

async function refresh() {
  try {
    const [gpuRes, trayRes] = await Promise.all([
      fetch(API + '/api/gpus'),
      fetch(API + '/api/trays')
    ]);
    const data = await gpuRes.json();
    trays = await trayRes.json();

    document.getElementById('sys-driver').textContent = 'amdgpu ' + data.system.amdgpu_version;
    document.getElementById('sys-rocm').textContent = 'ROCm ' + data.system.rocm_version;

    // Update fleet selector
    const fleetSel = document.getElementById('fleet-select');
    const allSameSlug = trays.length > 0 && trays.every(t => t.profile_slug === trays[0].profile_slug);
    fleetSel.innerHTML = '<option value="">' + (allSameSlug ? '' : '(mixed fleet) ') + 'Select profile...</option>' + profileOptions(allSameSlug ? trays[0].profile_slug : '');
    if (allSameSlug && trays.length > 0) fleetSel.value = trays[0].profile_slug;

    // Layout info
    const gpuName = data.gpus.length > 0 ? data.gpus[0].name : '';
    const isOAM = gpuName.includes('MI300X') || gpuName.includes('MI325X') || gpuName.includes('MI350X') || gpuName.includes('MI355X');
    const layoutEl = document.getElementById('layout-info');
    if (isOAM) {
      layoutEl.textContent = trays.length + ' OAM server (' + data.gpus.length + ' GPUs — UBB baseboard, cannot split)';
    } else if (gpuName.includes('MI300A')) {
      layoutEl.textContent = trays.length + ' APU server (' + data.gpus.length + ' GPUs)';
    } else {
      layoutEl.textContent = trays.length + ' server(s) (' + data.gpus.length + ' GPUs — PCIe, ' + (trays.length > 1 ? 'multi-server' : 'single server') + ')';
    }

    // Render trays
    let html = '';
    for (const tray of trays) {
      const trayGPUs = data.gpus.filter(g => g.index >= tray.start_gpu && g.index <= tray.end_gpu);
      html += renderTray(tray.index, trayGPUs, tray.profile_slug);
    }
    document.getElementById('rack').innerHTML = html;
  } catch (e) { console.error('refresh failed:', e); }
}

async function action(name, gpu) {
  await fetch(API + '/api/actions/' + name + '?gpu=' + gpu, { method: 'POST' });
  refresh();
}

async function switchFleetProfile(slug) {
  if (!slug) return;
  await fetch(API + '/api/profiles/switch?profile=' + slug, { method: 'POST' });
  refresh();
}

async function switchTray(gpuIndex, slug) {
  if (!slug) return;
  await fetch(API + '/api/profiles/switch-tray?gpu=' + gpuIndex + '&profile=' + slug, { method: 'POST' });
  refresh();
}

(async () => {
  await loadProfiles();
  refresh();
  setInterval(refresh, 2000);
})();
</script>
</body>
</html>`
