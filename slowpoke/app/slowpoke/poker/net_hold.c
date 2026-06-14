/*
 * NetPoke egress hold via Linux sch_plug (tc plug qdisc).
 * Controlled at runtime with SLOWPOKE_NETPOKE=1.
 */
#include "net_hold.h"

#include <errno.h>
#include <linux/netlink.h>
#include <linux/pkt_sched.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <unistd.h>

#define PLUG_QDISC_HANDLE TC_H_MAKE(0x10000, 0)
#define PLUG_QDISC_PARENT TC_H_ROOT
#define PLUG_BUFFER_LIMIT 100000U

static int nl_sock = -1;
static int ifindex = -1;
static unsigned int nl_seq = 1;
static int netpoke_enabled = 0;

static int env_truthy(const char *value)
{
    if (value == NULL || *value == '\0') {
        return 0;
    }
    return strcmp(value, "0") != 0 && strcasecmp(value, "false") != 0;
}

int netpoke_active(void)
{
    return netpoke_enabled;
}

static struct rtattr *nlmsg_tail(struct nlmsghdr *n)
{
    return (struct rtattr *)((char *)n + NLMSG_ALIGN(n->nlmsg_len));
}

static int addattr_l(struct nlmsghdr *n, int maxlen, int type, const void *data, int alen)
{
    int len = RTA_LENGTH(alen);
    struct rtattr *rta;

    if (NLMSG_ALIGN(n->nlmsg_len) + RTA_ALIGN(len) > (unsigned int)maxlen) {
        return -1;
    }

    rta = nlmsg_tail(n);
    rta->rta_type = type;
    rta->rta_len = len;
    if (alen > 0 && data != NULL) {
        memcpy(RTA_DATA(rta), data, (size_t)alen);
    }
    n->nlmsg_len = NLMSG_ALIGN(n->nlmsg_len) + RTA_ALIGN(len);
    return 0;
}

static int addattr_nest(struct nlmsghdr *n, int maxlen, int type)
{
    struct rtattr *rta = nlmsg_tail(n);
    if (addattr_l(n, maxlen, type, NULL, 0) < 0) {
        return -1;
    }
    return (int)((char *)rta - (char *)n);
}

static void addattr_nest_end(struct nlmsghdr *n, int nest)
{
    struct rtattr *rta = (struct rtattr *)((char *)n + nest);
    rta->rta_len = (unsigned short)((char *)nlmsg_tail(n) - (char *)rta);
}

static int netlink_send_ack(int fd, struct nlmsghdr *n)
{
    struct sockaddr_nl nladdr = {
        .nl_family = AF_NETLINK,
    };
    struct iovec iov = {
        .iov_base = n,
        .iov_len = n->nlmsg_len,
    };
    struct msghdr msg = {
        .msg_name = &nladdr,
        .msg_namelen = sizeof(nladdr),
        .msg_iov = &iov,
        .msg_iovlen = 1,
    };
    char reply[8192];
    ssize_t len;

    if (sendmsg(fd, &msg, 0) < 0) {
        return -1;
    }

    iov.iov_base = reply;
    iov.iov_len = sizeof(reply);
    len = recvmsg(fd, &msg, 0);
    if (len < 0) {
        return -1;
    }

    for (struct nlmsghdr *h = (struct nlmsghdr *)reply; NLMSG_OK(h, (unsigned int)len);
         h = NLMSG_NEXT(h, len)) {
        if (h->nlmsg_type == NLMSG_ERROR) {
            struct nlmsgerr *err = (struct nlmsgerr *)NLMSG_DATA(h);
            if (err->error != 0) {
                errno = -err->error;
                return -1;
            }
            return 0;
        }
    }

    return 0;
}

static int plug_msg(int action, int flags)
{
    struct {
        struct nlmsghdr nlh;
        struct tcmsg tcm;
        char buf[256];
    } req;

    memset(&req, 0, sizeof(req));
    req.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(struct tcmsg));
    req.nlh.nlmsg_type = RTM_NEWQDISC;
    req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK | flags;
    req.nlh.nlmsg_seq = nl_seq++;

    req.tcm.tcm_family = AF_UNSPEC;
    req.tcm.tcm_ifindex = ifindex;
    req.tcm.tcm_handle = PLUG_QDISC_HANDLE;
    req.tcm.tcm_parent = PLUG_QDISC_PARENT;

    if (addattr_l(&req.nlh, sizeof(req), TCA_KIND, "plug", 4) < 0) {
        return -1;
    }

    if (action >= 0) {
        int nest = addattr_nest(&req.nlh, sizeof(req), TCA_OPTIONS);
        if (nest < 0) {
            return -1;
        }
        if (addattr_l(&req.nlh, sizeof(req), action, NULL, 0) < 0) {
            return -1;
        }
        addattr_nest_end(&req.nlh, nest);
    } else {
        uint32_t limit = PLUG_BUFFER_LIMIT;
        int nest = addattr_nest(&req.nlh, sizeof(req), TCA_OPTIONS);
        if (nest < 0) {
            return -1;
        }
        if (addattr_l(&req.nlh, sizeof(req), TCQ_PLUG_LIMIT, &limit, sizeof(limit)) < 0) {
            return -1;
        }
        addattr_nest_end(&req.nlh, nest);
    }

    return netlink_send_ack(nl_sock, &req.nlh);
}

static int plug_add(void)
{
    int rc = plug_msg(-1, NLM_F_CREATE | NLM_F_EXCL);
    if (rc == 0) {
        return 0;
    }
    if (errno == EEXIST) {
        errno = 0;
        return 0;
    }
    return rc;
}

static int plug_delete(void)
{
    struct {
        struct nlmsghdr nlh;
        struct tcmsg tcm;
    } req;

    memset(&req, 0, sizeof(req));
    req.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(struct tcmsg));
    req.nlh.nlmsg_type = RTM_DELQDISC;
    req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
    req.nlh.nlmsg_seq = nl_seq++;

    req.tcm.tcm_family = AF_UNSPEC;
    req.tcm.tcm_ifindex = ifindex;
    req.tcm.tcm_handle = PLUG_QDISC_HANDLE;
    req.tcm.tcm_parent = PLUG_QDISC_PARENT;

    return netlink_send_ack(nl_sock, &req.nlh);
}

static int plug_change(int action)
{
    return plug_msg(action, NLM_F_REPLACE);
}

int net_pause_init_from_env(void)
{
    const char *enabled = getenv("SLOWPOKE_NETPOKE");
    const char *iface = getenv("SLOWPOKE_NET_IFACE");
    struct sockaddr_nl local = {
        .nl_family = AF_NETLINK,
    };

    if (!env_truthy(enabled)) {
        return 0;
    }

    if (iface == NULL || *iface == '\0') {
        iface = "eth0";
    }

    ifindex = (int)if_nametoindex(iface);
    if (ifindex <= 0) {
        fprintf(stderr, "netpoke: unknown interface %s\n", iface);
        return -1;
    }

    nl_sock = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
    if (nl_sock < 0) {
        perror("netpoke: socket");
        return -1;
    }

    if (bind(nl_sock, (struct sockaddr *)&local, sizeof(local)) < 0) {
        perror("netpoke: bind");
        close(nl_sock);
        nl_sock = -1;
        return -1;
    }

    plug_delete();
    if (plug_add() != 0) {
        fprintf(stderr, "netpoke: failed to install sch_plug on %s: %s\n", iface, strerror(errno));
        close(nl_sock);
        nl_sock = -1;
        return -1;
    }

    netpoke_enabled = 1;
    fprintf(stderr, "netpoke: sch_plug ready on %s (limit=%u)\n", iface, PLUG_BUFFER_LIMIT);
    return 0;
}

void net_hold(void)
{
    if (!netpoke_enabled || nl_sock < 0) {
        return;
    }
    if (plug_change(TCQ_PLUG_BUFFER) != 0) {
        fprintf(stderr, "netpoke: net_hold failed: %s\n", strerror(errno));
    }
}

void net_release(void)
{
    if (!netpoke_enabled || nl_sock < 0) {
        return;
    }
    if (plug_change(TCQ_PLUG_RELEASE_INDEFINITE) != 0) {
        fprintf(stderr, "netpoke: net_release failed: %s\n", strerror(errno));
    }
}
