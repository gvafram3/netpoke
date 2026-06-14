# NetPoke design: synchronised I/O pause in POKER

Status: design (mechanism "A", the perfect pause). To be implemented after the
multi-node cluster is up and the gap is re-measured cleanly.

## 1. Goal

When POKER pauses a non-target service's process, also stop that service's
network activity for the **same** window, so the artificial slowdown is complete
across both CPU and network resources. This restores the bottleneck-equivalence
property that SlowPoke's model assumes, for I/O-bound services.

## 2. Where this plugs in

The integration point is already in the code. In `slowpoke/src/poker/poker.c`,
the FIFO-monitoring thread does, per pause event:

```
kill(-child_pgid, SIGSTOP);     // freeze CPU
precise_sleep(accumulated...);  // hold for the model-computed duration
... write recover FIFO ...
kill(-child_pgid, SIGCONT);     // resume CPU
```

NetPoke wraps the network around that existing pair:

```
NET_HOLD();                     // <-- new: stop network egress
kill(-child_pgid, SIGSTOP);
precise_sleep(accumulated...);
... write recover FIFO ...
kill(-child_pgid, SIGCONT);
NET_RELEASE();                  // <-- new: resume network egress
```

Because the pause duration comes from the model and is already known at this
point, the network hold is automatically the correct length. No fixed,
guessed delay (such as the earlier static 50 ms `netem` sidecar) is involved.

## 3. The mechanism: hold egress, let TCP back-pressure handle ingress

Key design choice: we hold **egress** rather than trying to block ingress.

- Holding egress stops the service's outgoing requests during the pause (it is
  paused, so it should send nothing), which is what we want.
- Holding egress also stops the service's outgoing TCP **acknowledgements**.
  With ACKs withheld, each sender's TCP window fills and the sender stops
  transmitting by flow control. Almost nothing accumulates in our receive
  buffers, so there is no burst to drain on resume, and no residual I/O.
- This uses TCP's own flow control instead of fighting it. There is no packet
  loss, so there is no retransmission timeout or congestion-control backoff to
  add noise (which a "drop everything" approach would cause).

The only residual is the data already in flight at the instant of the pause,
bounded by the bandwidth-delay product, which is small and is exactly what the
eBPF measurement should confirm shrinks to near zero.

### Primitive: the `plug` queueing discipline (`sch_plug`)

Linux provides a queueing discipline designed for precisely this "hold then
release" behaviour: `plug`. It buffers egress packets while plugged and forwards
them when released. It is controlled over a netlink socket, so toggling it is a
single fast message (microseconds), which matters because pauses fire tens of
times per second.

Setup once, at POKER startup, on the pod interface (`eth0`):

```
tc qdisc add dev eth0 root plug limit 100000
```

Then per pause event, send a netlink message to the qdisc:

- on hold (before SIGSTOP):   `TCQ_PLUG_BUFFER` via netlink (`tc ... plug block` on the CLI)
- on release (after SIGCONT): `TCQ_PLUG_RELEASE_INDEFINITE`(flush and pass through)

POKER opens one `AF_NETLINK`/`NETLINK_ROUTE` socket at startup and reuses it for
every toggle, so `NET_HOLD()`/`NET_RELEASE()` are just `send()` calls. This
avoids forking `tc` on every pause, which would be far too slow and jittery.

## 4. Why not the alternatives (kept only as comparison baselines)

- **Static `netem delay` sidecar (the earlier approach):** a fixed delay is not
  aligned with the per-event pause windows, distorts steady-state traffic, and
  only reduces the *measured residual bytes* rather than restoring prediction
  accuracy. Useful only as a "naive" comparison point.
- **`nftables`/`iptables` DROP during the window:** simple, but dropping causes
  TCP retransmission-timeout backoff (hundreds of milliseconds), which
  over-slows the service and adds variance. Kept as a fallback if `sch_plug` is
  unavailable on the cluster kernel, and as a comparison baseline.
- **Rate throttling (`tbf`/`htb`, the paper's "I/O throttling" hint):** reduces
  capacity rather than pausing. Model-faithful but requires calibrating a
  slowdown factor to a bandwidth cap. Worth evaluating as the secondary
  mechanism after the plug approach is established.

## 5. Implementation tasks

1. Confirm `sch_plug` is available on the cluster kernel:
   `tc qdisc add dev <veth> root plug limit 1000 && tc qdisc del dev <veth> root`.
2. Add a small netlink helper to POKER (`net_hold.c/.h`) exposing
   `net_pause_init(iface)`, `net_hold()`, `net_release()`.
3. Call `net_pause_init` after fork in `main()`; call `net_hold()` immediately
   before the `SIGSTOP` and `net_release()` immediately after the `SIGCONT` in
   `monitor_fifo`.
4. Make the interface name configurable (env var, default `eth0`), and add a
   build flag so the network hold can be turned on/off for A/B comparison
   against the unmodified baseline.
5. Grant the POKER container `NET_ADMIN` capability and ensure `tc` plus the
   `sch_plug` kernel module are present in the image.

## 6. Validation plan

- **Mechanistic:** re-run the eBPF residual-I/O measurement during suspension
  with the hold off vs on; expect residual receive bytes during the pause to
  fall to near zero with the hold on.
- **Outcome:** re-run the full prediction experiment (predicted vs ground-truth
  optimised throughput) for I/O-bound configurations with the hold off vs on;
  the claim is that RMSE moves from the elevated I/O-bound level back towards the
  compute-bound baseline. This RMSE comparison, not the residual-byte count, is
  the result that proves the thesis.
- **Overhead:** measure added per-pause cost and any effect on the compute-bound
  baseline (which must remain unchanged).

## 7. Open questions / risks

- `sch_plug` buffer limit sizing under high egress rates; tune `limit`.
- Behaviour with very large receive windows (more bytes in flight at pause
  start); quantify the residual and confirm it stays negligible.
- Interaction with the service mesh / proxy sidecar already present in the pod
  (which interface actually carries service traffic). Verify with the real
  deployment before finalising the interface choice.
