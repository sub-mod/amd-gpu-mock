// SPDX-License-Identifier: Apache-2.0
#include <amdgpu.h>
#include <amdgpu_drm.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc,char **argv) {
    assert(argc==2);
    int fd=open(argv[1],O_RDONLY);assert(fd>=0);
    uint32_t major,minor;amdgpu_device_handle dev=NULL;
    assert(amdgpu_device_initialize(fd,&major,&minor,&dev)==0);close(fd);
    struct amdgpu_gpu_info info;struct drm_amdgpu_info_vram_gtt mem;
    assert(amdgpu_query_gpu_info(dev,&info)==0);
    assert(amdgpu_query_info(dev,AMDGPU_INFO_MEMORY,sizeof(mem),&mem)==0);
    assert(info.cu_active_number==304);assert(mem.vram_size==206158430208ULL);
    assert(amdgpu_query_info(dev,0xffffffff,sizeof(mem),&mem)==-EOPNOTSUPP);
    assert(amdgpu_query_info(dev,AMDGPU_INFO_MEMORY,1,&mem)==-EINVAL);
    assert(amdgpu_device_deinitialize(dev)==0);
    fd=open("/dev/null",O_RDONLY);assert(fd>=0);
    assert(amdgpu_device_initialize(fd,&major,&minor,&dev)==-ENODEV);close(fd);
    printf("PASS: native open -> CUSE -> mock libdrm: 304 CUs, 192 GiB; unsupported query, wrong buffer size and /dev/null rejected\n");
    return 0;
}
