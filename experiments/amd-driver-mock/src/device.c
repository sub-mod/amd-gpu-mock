// SPDX-License-Identifier: Apache-2.0
#define FUSE_USE_VERSION 31
#include <cuse_lowlevel.h>
#include <fuse_lowlevel.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

// A genuine openable Linux character-device provider. libdrm calls are mocked
// separately; raw ioctls intentionally fail so this cannot imply GPU execution.
static void device_open(fuse_req_t req, struct fuse_file_info *fi) { fuse_reply_open(req,fi); }
static void device_read(fuse_req_t req,size_t size,off_t off,struct fuse_file_info *fi) { (void)size;(void)off;(void)fi;fuse_reply_err(req,EOPNOTSUPP); }
static void device_write(fuse_req_t req,const char *buf,size_t size,off_t off,struct fuse_file_info *fi) { (void)buf;(void)size;(void)off;(void)fi;fuse_reply_err(req,EOPNOTSUPP); }
static void device_ioctl(fuse_req_t req,int cmd,void *arg,struct fuse_file_info *fi,unsigned flags,const void *in,size_t insize,size_t outsize) { (void)cmd;(void)arg;(void)fi;(void)flags;(void)in;(void)insize;(void)outsize;fuse_reply_err(req,ENOTTY); }
int main(int argc,char **argv) {
    if(argc!=3) { fprintf(stderr,"usage: mock-device CARD_INDEX NODE_PATH\n");return 2; }
    char *end; long card=strtol(argv[1],&end,10);
    if(*end || card<0 || card>=256) return 2;
    char devname[100];snprintf(devname,sizeof(devname),"DEVNAME=amd-driver-mock-card%ld",card);
    const char *dev_info[]={devname};
    struct cuse_info ci={.dev_major=0,.dev_minor=(unsigned)card,.dev_info_argc=1,.dev_info_argv=dev_info};
    struct cuse_lowlevel_ops ops={.open=device_open,.read=device_read,.write=device_write,.ioctl=device_ioctl};
    char *args[]={argv[0],"-f"};
    // The caller creates the node only after CUSE has registered successfully.
    fprintf(stderr,"amd-driver-mock: CUSE requested card%ld dynamic-major minor=%ld path=%s\n",card,card,argv[2]);
    return cuse_lowlevel_main(2,args,&ci,&ops,NULL);
}
