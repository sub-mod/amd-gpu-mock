#!/usr/bin/env python3
"""Translate one original renderer snapshot into a RocJITsu functional topology."""
import json,sys
from pathlib import Path
props=dict(l.split(maxsplit=1) for l in Path(sys.argv[1]).read_text().splitlines())
smi=Path(sys.argv[2]).read_text().splitlines()
c=json.loads(Path(sys.argv[3]).read_text())
d=c['vm']['gpu']['device']
assert int(props['gfx_target_version'])==90402
cu=int(props['simd_count'])//int(props['simd_per_cu']); xcc=int(props['num_xcc'])
assert cu==304 and xcc==8 # Deliberately one supported profile, no silent approximation.
for k in ['unique_id','location_id','domain','device_id','vendor_id','drm_render_minor','simd_count','simd_per_cu','wave_front_size','local_mem_size','gfx_target_version']:
 d[k]=int(props[k],0)
d['gpu_id']=1
d['marketing_name']=smi[1]
# A functional arrangement: 8 XCDs x 2 shader engines x 19 CUs = 304.
# Not a physical MI300X floorplan or fuse-layout simulation.
d.update(num_shader_engines=2,num_shader_arrays_per_engine=1,num_cu_per_sh=19)
root=c['topology']['root']; x=root['children'][1]; x['name']='xcd[0:8]'
se=x['children'][2];se['name']='se[0:2]';se['children'][0]['name']='cu[0:19]'
for link in c['topology']['links']:
 link['pattern']=link['pattern'].replace('j*10+k','j*19+k')
 for r in link['for_ranges']:
  if r['var_name']=='j':r['end']=2
  if r['var_name']=='k':r['end']=19
Path(sys.argv[4]).write_text(json.dumps(c,indent=2)+'\n')
print(json.dumps({'source':'original renderer snapshot','kfd_unique_id':d['unique_id'],'rocr_uuid':f"GPU-{d['unique_id']:016x}",'smi_uuid':smi[2],'bdf':smi[3],'cu_count':cu,'vram_bytes':d['local_mem_size'],'functional_topology':'8x2x19'}))
