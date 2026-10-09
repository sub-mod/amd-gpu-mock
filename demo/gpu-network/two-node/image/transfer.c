// SPDX-License-Identifier: Apache-2.0
// CPU-buffer verbs transfer. TCP carries QP metadata, digests and synchronization only.
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <infiniband/verbs.h>
#include <netinet/in.h>
#include <openssl/sha.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/time.h>

#include <time.h>
#include <unistd.h>

#define SIZE 65536
#define PORT 18515
#define REQUIRE(x) do { if (!(x)) { fprintf(stderr,"FAIL line=%d operation=%s errno=%d (%s)\n",__LINE__,#x,errno,strerror(errno)); exit(1); } } while (0)

static void exchange(int fd, void *buffer, size_t length, int writing) {
    char *p=buffer;
    while (length) {
        ssize_t n=writing ? send(fd,p,length,MSG_NOSIGNAL) : recv(fd,p,length,0);
        if (n<0 && errno==EINTR) continue;
        REQUIRE(n>0); p+=n; length-=(size_t)n;
    }
}
static uint64_t now(void) { struct timespec t; REQUIRE(clock_gettime(CLOCK_MONOTONIC,&t)==0); return (uint64_t)t.tv_sec*1000000000+t.tv_nsec; }
static void completion(struct ibv_cq *cq, enum ibv_wc_opcode expected, uint32_t imm) {
    uint64_t deadline=now()+120000000000ULL;
    for (;;) {
        struct ibv_wc wc; int n=ibv_poll_cq(cq,1,&wc); REQUIRE(n>=0);
        if(n) {
            if(wc.status!=IBV_WC_SUCCESS) fprintf(stderr,"completion status=%s vendor=%u\n",ibv_wc_status_str(wc.status),wc.vendor_err);
            REQUIRE(wc.status==IBV_WC_SUCCESS); REQUIRE(wc.opcode==expected);
            if(expected==IBV_WC_RECV_RDMA_WITH_IMM) { REQUIRE(wc.wc_flags&IBV_WC_WITH_IMM); REQUIRE(ntohl(wc.imm_data)==imm); }
            printf("CQ_SUCCESS opcode=%u wr_id=%llu\n",wc.opcode,(unsigned long long)wc.wr_id); return;
        }
        REQUIRE(now()<deadline); struct timespec nap={0,1000000}; nanosleep(&nap,NULL);
    }
}
static void digest(const unsigned char *buffer, unsigned char hash[SHA256_DIGEST_LENGTH]) { REQUIRE(SHA256(buffer,SIZE,hash)!=NULL); }
static void print_hash(const char *label,const unsigned char *hash) { printf("%s=",label);for(int i=0;i<SHA256_DIGEST_LENGTH;i++)printf("%02x",hash[i]);printf("\n"); }
static int control(int server, const char *ip) {
    struct sockaddr_in addr={.sin_family=AF_INET,.sin_port=htons(PORT)};
    REQUIRE(inet_pton(AF_INET,server?"0.0.0.0":ip,&addr.sin_addr)==1);
    int fd=-1;
    if(server) {
        int listener=socket(AF_INET,SOCK_STREAM,0); REQUIRE(listener>=0);
        int yes=1; REQUIRE(setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof yes)==0);
        REQUIRE(bind(listener,(struct sockaddr*)&addr,sizeof addr)==0); REQUIRE(listen(listener,1)==0);
        printf("CONTROL_LISTEN port=%d\n",PORT);
        fd=accept(listener,NULL,NULL); REQUIRE(fd>=0);close(listener);
    } else {
        uint64_t deadline=now()+120000000000ULL;
        while(now()<deadline) {
            fd=socket(AF_INET,SOCK_STREAM,0); REQUIRE(fd>=0);
            if(connect(fd,(struct sockaddr*)&addr,sizeof addr)==0)break;
            close(fd);fd=-1;struct timespec nap={1,0};nanosleep(&nap,NULL);
        }
        REQUIRE(fd>=0);
    }
    struct timeval timeout={120,0};
    REQUIRE(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout)==0);
    REQUIRE(setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout)==0);
    return fd;
}
int main(int argc,char **argv) {
    setvbuf(stdout,NULL,_IOLBF,0);
    REQUIRE(argc==2 || argc==3);
    int server=!strcmp(argv[1],"server"); REQUIRE(server || !strcmp(argv[1],"client")); REQUIRE(server || argc==3);
    int count;struct ibv_device **list=ibv_get_device_list(&count); REQUIRE(list && count==1);
    struct ibv_context *ctx=ibv_open_device(list[0]); REQUIRE(ctx);
    const char *node=getenv("NODE_NAME"); const char *nic=getenv("PCIDEVICE_AMD_COM_NIC"); REQUIRE(node && nic);
    printf("ROLE=%s NODE=%s NIC=%s RDMA_DEVICE=%s bytes=%d\n",server?"receiver":"sender",node,nic,ibv_get_device_name(list[0]),SIZE);
    struct ibv_pd *pd=ibv_alloc_pd(ctx); REQUIRE(pd);
    struct ibv_cq *cq=ibv_create_cq(ctx,16,NULL,NULL,0); REQUIRE(cq);
    unsigned char *buffer=NULL; REQUIRE(posix_memalign((void**)&buffer,4096,SIZE)==0); memset(buffer,0,SIZE);
    struct ibv_mr *mr=ibv_reg_mr(pd,buffer,SIZE,IBV_ACCESS_LOCAL_WRITE|IBV_ACCESS_REMOTE_WRITE); REQUIRE(mr);
    struct ibv_qp_init_attr init={.send_cq=cq,.recv_cq=cq,.qp_type=IBV_QPT_RC,.cap={.max_send_wr=8,.max_recv_wr=8,.max_send_sge=1,.max_recv_sge=1}};
    struct ibv_qp *qp=ibv_create_qp(pd,&init); REQUIRE(qp);
    struct ibv_qp_attr a={.qp_state=IBV_QPS_INIT,.pkey_index=0,.port_num=1,.qp_access_flags=IBV_ACCESS_REMOTE_WRITE};
    REQUIRE(ibv_modify_qp(qp,&a,IBV_QP_STATE|IBV_QP_PKEY_INDEX|IBV_QP_PORT|IBV_QP_ACCESS_FLAGS)==0);
    union ibv_gid gid; REQUIRE(ibv_query_gid(ctx,1,0,&gid)==0);
    // Fixed wire format: QPN, GID, registered address, rkey (all integers big endian).
    unsigned char local[32],remote[32]; uint32_t v=htonl(qp->qp_num);memcpy(local,&v,4);memcpy(local+4,gid.raw,16);
    uint64_t address=(uintptr_t)buffer;for(int i=0;i<8;i++)local[20+i]=(unsigned char)(address>>(56-8*i));
    v=htonl(mr->rkey);memcpy(local+28,&v,4);
    int fd=control(server,server?NULL:argv[2]);exchange(fd,local,sizeof local,1);exchange(fd,remote,sizeof remote,0);
    memcpy(&v,remote,4);uint32_t remote_qpn=ntohl(v); union ibv_gid remote_gid;memcpy(remote_gid.raw,remote+4,16);
    uint64_t remote_addr=0;for(int i=0;i<8;i++)remote_addr=(remote_addr<<8)|remote[20+i];memcpy(&v,remote+28,4);uint32_t remote_key=ntohl(v);
    char gid_text[INET6_ADDRSTRLEN]; REQUIRE(inet_ntop(AF_INET6,remote_gid.raw,gid_text,sizeof gid_text));
    printf("QP_METADATA local_qpn=%u remote_qpn=%u peer_gid=%s\n",qp->qp_num,remote_qpn,gid_text);
    a=(struct ibv_qp_attr){.qp_state=IBV_QPS_RTR,.path_mtu=IBV_MTU_1024,.dest_qp_num=remote_qpn,.rq_psn=0,.max_dest_rd_atomic=1,.min_rnr_timer=12,.ah_attr={.is_global=1,.port_num=1,.grh={.dgid=remote_gid,.sgid_index=0,.hop_limit=1}}};
    REQUIRE(ibv_modify_qp(qp,&a,IBV_QP_STATE|IBV_QP_AV|IBV_QP_PATH_MTU|IBV_QP_DEST_QPN|IBV_QP_RQ_PSN|IBV_QP_MAX_DEST_RD_ATOMIC|IBV_QP_MIN_RNR_TIMER)==0);
    a=(struct ibv_qp_attr){.qp_state=IBV_QPS_RTS,.timeout=14,.retry_cnt=7,.rnr_retry=7,.sq_psn=0,.max_rd_atomic=1};
    REQUIRE(ibv_modify_qp(qp,&a,IBV_QP_STATE|IBV_QP_TIMEOUT|IBV_QP_RETRY_CNT|IBV_QP_RNR_RETRY|IBV_QP_SQ_PSN|IBV_QP_MAX_QP_RD_ATOMIC)==0);
    for(unsigned iteration=0;iteration<2;iteration++) {
        const char *op=iteration?"RDMA_WRITE_WITH_IMM":"SEND_RECV";unsigned char expected[32],actual[32];
        memset(buffer,0,SIZE);
        if(server) {
            struct ibv_sge sg={.addr=(uintptr_t)buffer,.length=SIZE,.lkey=mr->lkey};struct ibv_recv_wr wr={.wr_id=1,.sg_list=&sg,.num_sge=1},*bad;
            REQUIRE(ibv_post_recv(qp,&wr,&bad)==0);
            exchange(fd,expected,sizeof expected,0);char ready='R';exchange(fd,&ready,1,1);
            completion(cq,iteration?IBV_WC_RECV_RDMA_WITH_IMM:IBV_WC_RECV,iteration+1);
            if(getenv("RDMA_CORRUPT"))buffer[SIZE-1]^=1;
            digest(buffer,actual);print_hash("EXPECTED_SHA256",expected);print_hash("RECEIVED_SHA256",actual);
            unsigned char match=!memcmp(expected,actual,sizeof expected);exchange(fd,&match,1,1);
            REQUIRE(match);printf("PAYLOAD_PASS operation=%s bytes=%d\n",op,SIZE);
        } else {
            size_t filled=0;while(filled<SIZE){ssize_t n=getrandom(buffer+filled,SIZE-filled,0);if(n<0 && errno==EINTR)continue;REQUIRE(n>0);filled+=(size_t)n;}
            digest(buffer,expected);print_hash("SENT_SHA256",expected);exchange(fd,expected,sizeof expected,1);char ready;exchange(fd,&ready,1,0);REQUIRE(ready=='R');
            struct ibv_sge sg={.addr=(uintptr_t)buffer,.length=SIZE,.lkey=mr->lkey};
            struct ibv_send_wr wr={.wr_id=2,.sg_list=&sg,.num_sge=1,.opcode=iteration?IBV_WR_RDMA_WRITE_WITH_IMM:IBV_WR_SEND,.send_flags=IBV_SEND_SIGNALED,.imm_data=htonl(iteration+1),.wr={.rdma={.remote_addr=remote_addr,.rkey=remote_key}}},*bad;
            REQUIRE(ibv_post_send(qp,&wr,&bad)==0);completion(cq,iteration?IBV_WC_RDMA_WRITE:IBV_WC_SEND,0);
            unsigned char match;exchange(fd,&match,1,0);REQUIRE(match);printf("PAYLOAD_PASS operation=%s bytes=%d\n",op,SIZE);
        }
    }
    printf("TRANSFER_PASS role=%s node=%s payload_path=libibverbs/ionic/ERNIC_TCP_mesh\n",server?"receiver":"sender",node);
    close(fd);REQUIRE(ibv_destroy_qp(qp)==0);REQUIRE(ibv_dereg_mr(mr)==0);free(buffer);REQUIRE(ibv_destroy_cq(cq)==0);REQUIRE(ibv_dealloc_pd(pd)==0);REQUIRE(ibv_close_device(ctx)==0);ibv_free_device_list(list);return 0;
}
