/*
 * NetPoke egress hold via Linux sch_plug (tc plug qdisc).
 * Controlled at runtime with SLOWPOKE_NETPOKE=1.
 */
#include "net_hold.h"

#include <errno.h>
#include <stdint.h>
#include <time.h>
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
static int plug_is_buffering = 0;
static char net_iface[IFNAMSIZ] = "eth0";
/* Set once if a netlink toggle fails at runtime; after that we fall back to
 * the tc CLI for the rest of this process's life instead of re-trying (and
 * re-failing) netlink on every single pause. See net_hold()/net_release(). */
static int netlink_toggle_broken = 0;

static long long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

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

/*
 * IMPORTANT: sch_plug's kernel handler (net/sched/sch_plug.c) reads TCA_OPTIONS
 * as a *raw* `struct tc_plug_qopt { int action; __u32 limit; }` (nla_data(opt)
 * cast straight to the struct) — it is NOT a nested rtattr tree keyed by
 * action. An earlier version of this file built TCA_OPTIONS as a nested
 * attribute whose sub-type equaled the numeric action (see git history:
 * "Fix net_hold netlink: CREATE|REPLACE for plug block/release", reverted one
 * commit later as "Netlink toggle EINVAL on cluster kernel"). That mismatch
 * — sending a nested-attribute blob where the kernel expects 8 raw bytes —
 * is the most likely cause of that EINVAL. This version sends the flat
 * struct directly as the TCA_OPTIONS payload, matching the kernel UAPI.
 */
static int plug_msg_raw(int action, uint32_t limit, int flags)
{
    struct {
        struct nlmsghdr nlh;
        struct tcmsg tcm;
        char buf[256];
    } req;
    struct tc_plug_qopt qopt;

    memset(&req, 0, sizeof(req));
    req.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(struct tcmsg));
    req.nlh.nlmsg_type = RTM_NEWQDISC;
    req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK | flags;
    req.nlh.nlmsg_seq = nl_seq++;

    req.tcm.tcm_family = AF_UNSPEC;
    req.tcm.tcm_ifindex = ifindex;
    req.tcm.tcm_handle = PLUG_QDISC_HANDLE;
    req.tcm.tcm_parent = PLUG_QDISC_PARENT;

    if (addattr_l(&req.nlh, sizeof(req), TCA_KIND, "plug", 5) < 0) {
        return -1;
    }

    memset(&qopt, 0, sizeof(qopt));
    qopt.action = action;
    qopt.limit = limit;
    if (addattr_l(&req.nlh, sizeof(req), TCA_OPTIONS, &qopt, sizeof(qopt)) < 0) {
        return -1;
    }

    return netlink_send_ack(nl_sock, &req.nlh);
}

static int plug_add(void)
{
    int rc = plug_msg_raw(TCQ_PLUG_LIMIT, PLUG_BUFFER_LIMIT, NLM_F_CREATE | NLM_F_EXCL);
    if (rc == 0) {
        return 0;
    }
    if (errno == EEXIST) {
        errno = 0;
        return 0;
    }
    return rc;
}

/* Fast path for net_hold()/net_release(): toggle the already-created qdisc
 * via NLM_F_REPLACE (no create/exclusive flags — the qdisc must already
 * exist from plug_add()). Returns 0 on success, -1 with errno set on failure
 * (e.g. EINVAL if this kernel's sch_plug still rejects the encoding above). */
static int plug_toggle(int action)
{
    return plug_msg_raw(action, 0, NLM_F_REPLACE);
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

/* Fallback only: forks+execs the tc CLI. This is the path the design doc
 * warns is "far too slow and jittery" for a per-pause toggle (fork/exec/shell
 * parse, easily single-digit-to-tens of milliseconds). Used only if the
 * netlink fast path (plug_toggle) fails at runtime — see net_hold(). */
static int tc_plug_action(const char *action)
{
    char cmd[256];
    int rc;

    snprintf(cmd, sizeof(cmd), "tc qdisc change dev %s root plug %s", net_iface, action);
    rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "netpoke: tc plug %s on %s failed (rc=%d)\n", action, net_iface, rc);
        return -1;
    }
    return 0;
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
    strncpy(net_iface, iface, sizeof(net_iface) - 1);
    net_iface[sizeof(net_iface) - 1] = '\0';

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
    plug_is_buffering = 0;
    fprintf(stderr, "netpoke: sch_plug ready on %s (limit=%u)\n", net_iface, PLUG_BUFFER_LIMIT);
    return 0;
}

/* Try the microsecond netlink toggle first; only fall back to the slow CLI
 * path (and only once, permanently, for this process) if netlink fails at
 * runtime. Every toggle is timed and logged to stderr (captured by
 * `kubectl logs`) so a smoke test can immediately confirm which path is
 * active and how expensive each toggle actually is, instead of assuming. */
void net_hold(void)
{
    if (!netpoke_enabled) {
        return;
    }
    long long t0 = now_ns();
    int rc = -1;
    const char *via = "netlink";
    if (!netlink_toggle_broken) {
        rc = plug_toggle(TCQ_PLUG_BUFFER);
        if (rc != 0) {
            fprintf(stderr, "netpoke: netlink hold failed (%s) — falling back to tc CLI for rest of run\n",
                    strerror(errno));
            netlink_toggle_broken = 1;
        }
    }
    if (netlink_toggle_broken) {
        via = "cli";
        rc = tc_plug_action("block");
    }
    long long t1 = now_ns();
    fprintf(stderr, "netpoke: hold via=%s took_ns=%lld\n", via, t1 - t0);
    if (rc == 0) {
        plug_is_buffering = 1;
    }
}

void net_release(void)
{
    if (!netpoke_enabled || !plug_is_buffering) {
        return;
    }
    long long t0 = now_ns();
    int rc;
    const char *via = "netlink";
    if (!netlink_toggle_broken) {
        rc = plug_toggle(TCQ_PLUG_RELEASE_INDEFINITE);
        if (rc != 0) {
            fprintf(stderr, "netpoke: netlink release failed (%s) — falling back to tc CLI for rest of run\n",
                    strerror(errno));
            netlink_toggle_broken = 1;
        }
    }
    if (netlink_toggle_broken) {
        via = "cli";
        rc = tc_plug_action("release_indefinite");
    }
    long long t1 = now_ns();
    fprintf(stderr, "netpoke: release via=%s took_ns=%lld\n", via, t1 - t0);
    if (rc == 0) {
        plug_is_buffering = 0;
    }
}
