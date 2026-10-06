#ifndef NET_HOLD_H
#define NET_HOLD_H

/* Initialise sch_plug on SLOWPOKE_NET_IFACE (default eth0) when
 * SLOWPOKE_NETPOKE=1.  Safe to call when NetPoke is disabled. */
int net_pause_init_from_env(void);

/* Hold / release egress via sch_plug.  No-ops when NetPoke is off. */
void net_hold(void);
void net_release(void);

int netpoke_active(void);

#endif
