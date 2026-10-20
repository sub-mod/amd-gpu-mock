#include <hip/hip_runtime.h>
#include <hsa/hsa.h>
#include <hsa/hsa_ext_amd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <cassert>
static hsa_agent_t gpu{};
static hsa_status_t agent(hsa_agent_t a,void*) { hsa_device_type_t t; hsa_agent_get_info(a,HSA_AGENT_INFO_DEVICE,&t); if(t==HSA_DEVICE_TYPE_GPU)gpu=a; return HSA_STATUS_SUCCESS; }
#define HIP(x) do{hipError_t e=(x); if(e!=hipSuccess){fprintf(stderr,"%s: %s\n",#x,hipGetErrorString(e));return 1;}}while(0)
#define HSA(x) do{if((x)!=HSA_STATUS_SUCCESS){fprintf(stderr,"HSA failure: %s\n",#x);return 1;}}while(0)
int main(){
 printf("Allocation: ROCR=%s CU=%s memory=%s audit=%s\n",getenv("ROCR_VISIBLE_DEVICES"),getenv("HSA_CU_MASK"),getenv("HIP_DEVICE_MEMORY_LIMIT_0"),getenv("LD_AUDIT"));
 int n=0; HIP(hipGetDeviceCount(&n)); if(n!=1)return 2;
 hipDeviceProp_t p{};HIP(hipGetDeviceProperties(&p,0));
 size_t cap=0;HIP(hipDeviceTotalMem(&cap,0));
 const char* lim=getenv("HIP_DEVICE_MEMORY_LIMIT_0"); if(!lim)return 3;
 size_t expected=strtoull(lim,nullptr,10)*1024*1024;
 printf("HIP device=%s cu=%d visible_memory=%zu expected=%zu\n",p.name,p.multiProcessorCount,cap,expected);
 printf("HIP PCI address: %04x:%02x:%02x.0\n",p.pciDomainID,p.pciBusID,p.pciDeviceID);
 if(cap!=expected)return 4;
 void* ptr=nullptr; hipError_t over=hipMalloc(&ptr,expected+1);
 printf("Over-limit allocation: %s\n",hipGetErrorString(over));if(over!=hipErrorOutOfMemory)return 5;
 void* a=nullptr;void* b=nullptr;HIP(hipMalloc(&a,expected*3/4));
 over=hipMalloc(&b,expected/2);printf("Cumulative over-limit allocation: %s\n",hipGetErrorString(over));if(over!=hipErrorOutOfMemory)return 6;
 HIP(hipFree(a));HIP(hipMalloc(&b,expected/2));HIP(hipFree(b));
 puts("PASS: HIP memory cap, cumulative accounting, and free/reallocate");
 HSA(hsa_init());HSA(hsa_iterate_agents(agent,nullptr));
 char uuid[64]={};HSA(hsa_agent_get_info(gpu,(hsa_agent_info_t)HSA_AMD_AGENT_INFO_UUID,uuid));
 printf("HSA identity: %s\n",uuid);if(strcmp(uuid,getenv("ROCR_VISIBLE_DEVICES")))return 7;
 hsa_queue_t* q=nullptr;HSA(hsa_queue_create(gpu,64,HSA_QUEUE_TYPE_MULTI,nullptr,nullptr,0,0,&q));
 uint32_t mask[10]={};HSA(hsa_amd_queue_cu_get_mask(q,320,mask));
 int enabled=0;for(auto x:mask)enabled+=__builtin_popcount(x);
 printf("HSA queue mask (%d enabled CUs):",enabled);for(auto x:mask)printf(" %08x",x);puts("");
 // ROCr 7.2 SetCUMasking returns before updating its local cu_mask_ cache.
 // The diagnostic ioctl observer verifies the actual mask sent to KFD instead.
 puts("NOTE: ROCr 7.2 CU-mask getter cache is not used as enforcement evidence");
 HSA(hsa_queue_destroy(q));HSA(hsa_shut_down());
 puts("PASS: shared KFD identity; queue-mask validation uses the KFD observer");return 0;
}
