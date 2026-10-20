#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/ioctl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
/* Observation only: forward the original request/buffer and preserve errno. */
#include <errno.h>
struct cu_args {uint32_t queue_id,num_cu_mask;uint64_t cu_mask_ptr;};
int ioctl(int fd,unsigned long request,...){
 va_list ap;va_start(ap,request);void* arg=va_arg(ap,void*);va_end(ap);
 int (*next)(int,unsigned long,...)=dlsym(RTLD_NEXT,"ioctl");
 int rc=next(fd,request,arg),saved=errno;
 if(_IOC_TYPE(request)=='K' && _IOC_NR(request)==0x1a && arg){
  struct cu_args* a=arg;uint32_t* mask=(void*)(uintptr_t)a->cu_mask_ptr;
  int first=-1,last=-1;const char* expected=getenv("HSA_CU_MASK");
  int valid=expected&&sscanf(expected,"0:%d-%d",&first,&last)==2;
  valid=valid && first>=0 && last>=first && a->num_cu_mask>(unsigned)last;
  for(unsigned i=0;i<a->num_cu_mask && valid;i++)if(!!(mask[i/32]&(1u<<(i%32)))!=(i>=first&&i<=last))valid=0;
  fprintf(stderr,"KFD_MASK queue=%u bits=%u result=%d errno=%d expected=%s match=%s\n",a->queue_id,a->num_cu_mask,rc,rc?saved:0,expected?expected:"unset",valid?"yes":"NO");
  if(!valid||rc) _exit(91);
 }
 errno=saved;return rc;
}
