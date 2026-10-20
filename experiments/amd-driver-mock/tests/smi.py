#!/usr/bin/env python3
"""Exercise actual exported AMD SMI ABI functions against original renderer state."""
import ctypes as c, os
lib=c.CDLL('/opt/amd-driver-mock/lib/libamd_smi.so.27')
lib.amdsmi_get_processor_handle_from_bdf.argtypes=[c.c_uint64,c.POINTER(c.c_void_p)]
lib.amdsmi_get_gpu_device_bdf.argtypes=[c.c_void_p,c.POINTER(c.c_uint64)]
lib.amdsmi_get_gpu_device_uuid.argtypes=[c.c_void_p,c.POINTER(c.c_uint),c.c_void_p]
lib.amdsmi_get_processor_handles.argtypes=[c.c_void_p,c.POINTER(c.c_uint),c.c_void_p]
h=c.c_void_p(123)
assert lib.amdsmi_get_processor_handle_from_bdf(0x500,c.byref(h))==32 and h.value is None
assert lib.amdsmi_init(c.c_uint64(0))==0
assert lib.amdsmi_get_processor_handle_from_bdf(0x500,None)==1
assert lib.amdsmi_get_processor_handle_from_bdf(0x500,c.byref(h))==0 and h.value==0x1000
bdf=c.c_uint64();assert lib.amdsmi_get_gpu_device_bdf(h,c.byref(bdf))==0 and bdf.value==0x500
n=c.c_uint(128);uuid=c.create_string_buffer(128)
assert lib.amdsmi_get_gpu_device_uuid(h,c.byref(n),uuid)==0
assert uuid.value.decode() in open(os.environ['MOCK_AMDSMI_STATE_DIR']+'/gpu0').read()
unknown=c.c_void_p(123)
assert lib.amdsmi_get_processor_handle_from_bdf(0x600,c.byref(unknown))==31 and unknown.value is None
assert lib.amdsmi_shut_down()==0
assert lib.amdsmi_get_processor_handle_from_bdf(0x500,c.byref(h))==32 and h.value is None
print('PASS: AMD SMI BDF lookup/UUID roundtrip; null, unknown BDF, and uninitialized state rejected')
