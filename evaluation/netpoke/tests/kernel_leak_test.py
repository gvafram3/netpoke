#!/usr/bin/env python3
"""
Does the network keep talking while the CPU is frozen -- and does a real sch_plug stop it?

Run as root:   sudo ./topo_leak.sh && sudo SCEN=sender HOLD=0 python3 kernel_leak_test.py
                                       sudo SCEN=sender HOLD=1 python3 kernel_leak_test.py
Method: record each SIGSTOP window; timestamp every packet leaving the "pod" (AF_PACKET on the host side
of the veth); leak% = traffic in a paused window / traffic in an equally long running window.
HOLD=1 wraps every freeze exactly like NetPoke:  plug block -> SIGSTOP -> sleep -> SIGCONT -> release_indefinite

Env: SCEN=sender|receiver|idle  HOLD=0|1  PAUSE_MS=50  CYCLES=12  LIMIT=<plug limit bytes, default 8000000>
Exit code 3 = sch_plug unavailable (HOLD=1 only).
"""
import socket, struct, subprocess, sys, os, time, signal, threading, statistics, re

SCEN = os.environ.get("SCEN", "sender"); HOLD = os.environ.get("HOLD", "0") == "1"
PAUSE_MS = int(os.environ.get("PAUSE_MS", "50")); RUN_MS = int(os.environ.get("RUN_MS", "200"))
CYCLES = int(os.environ.get("CYCLES", "12")); LIMIT = int(os.environ.get("LIMIT", "8000000"))
PUSH_INT = float(os.environ.get("PUSH_INT", "0.003"))
GUARD = 0.003; POD_IP = "10.0.0.2"; DEV = "veth1"
NS = ["ip", "netns", "exec", "ns1"]

def tc(*a, check=True):
    r = subprocess.run(NS + ["tc"] + list(a), capture_output=True, text=True)
    if check and r.returncode:
        return None, (r.stderr or r.stdout).strip()
    return r.stdout, None

def qstats():
    out, _ = tc("-s", "qdisc", "show", "dev", DEV, check=False)
    m = re.search(r"dropped (\d+)", out or ""); b = re.search(r"backlog (\S+)", out or "")
    return (int(m.group(1)) if m else None, b.group(1) if b else None)

if HOLD:
    out, err = tc("qdisc", "replace", "dev", DEV, "root", "handle", "1:", "plug", "limit", str(LIMIT))
    if err:
        print(f"sch_plug NOT AVAILABLE here: {err}\n(needs the sch_plug kernel module + root; run cluster/04_day0_checks.sh)"); sys.exit(3)
    # gotcha #1: a fresh plug qdisc starts BLOCKED. Release it or the pod is a black hole.
    _, err = tc("qdisc", "change", "dev", DEV, "root", "plug", "release_indefinite")
    if err: print("could not release plug:", err); sys.exit(3)

PODSRC = r'''
import socket, sys, time
mode = sys.argv[1]
if mode == "sender":
    s = socket.create_connection(("10.0.0.1", 9200)); buf = b"x" * 65536
    while True: s.sendall(buf)
elif mode == "receiver":
    l = socket.socket(); l.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    l.bind(("10.0.0.2", 9201)); l.listen(1); c, _ = l.accept()
    while True:
        c.recv(4096); t = time.perf_counter()
        while time.perf_counter() - t < 0.001: pass
else: time.sleep(1000)
'''
pkts = []; stop_sniff = False; peer_stop = False

def sniffer():
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)); s.bind(("veth0", 0)); s.settimeout(0.05)
    while not stop_sniff:
        try: f = s.recv(70000)
        except socket.timeout: continue
        t = time.time()
        if len(f) < 54 or f[12:14] != b"\x08\x00" or f[23] != 6 or socket.inet_ntoa(f[26:30]) != POD_IP: continue
        ihl = (f[14] & 15) * 4; tot = struct.unpack("!H", f[16:18])[0]; doff = (f[14 + ihl + 12] >> 4) * 4
        pay = max(tot - ihl - doff, 0); pkts.append((t, pay > 0, pay))

def sink_slow():
    l = socket.socket(); l.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); l.bind(("10.0.0.1", 9200)); l.listen(1)
    c, _ = l.accept()
    while not peer_stop: c.recv(65536); time.sleep(0.003)

def pusher():
    time.sleep(0.5); c = socket.create_connection(("10.0.0.2", 9201)); c.setblocking(False)
    nxt = time.perf_counter()
    while not peer_stop:
        if time.perf_counter() >= nxt:
            nxt += PUSH_INT
            try: c.send(b"y" * 4096)
            except BlockingIOError: pass
        else: time.sleep(0.0003)

if SCEN == "sender": threading.Thread(target=sink_slow, daemon=True).start()
if SCEN == "receiver": threading.Thread(target=pusher, daemon=True).start()
threading.Thread(target=sniffer, daemon=True).start()
pod = subprocess.Popen(NS + ["python3", "-u", "-c", PODSRC, SCEN], preexec_fn=os.setsid); pgid = os.getpgid(pod.pid)
time.sleep(1.5)

wins = []
for _ in range(CYCLES):
    time.sleep(RUN_MS / 1000); r0 = time.time(); time.sleep(PAUSE_MS / 1000); r1 = time.time(); time.sleep(0.02)
    if HOLD: tc("qdisc", "change", "dev", DEV, "root", "plug", "block")            # net_hold()
    os.killpg(pgid, signal.SIGSTOP); p0 = time.time(); time.sleep(PAUSE_MS / 1000); p1 = time.time()
    os.killpg(pgid, signal.SIGCONT)
    if HOLD: tc("qdisc", "change", "dev", DEV, "root", "plug", "release_indefinite")  # net_release()
    wins.append(((r0, r1), (p0, p1)))
drops, backlog = qstats() if HOLD else (None, None)
stop_sniff = True; peer_stop = True; time.sleep(0.2)
try: os.killpg(pgid, signal.SIGCONT); os.killpg(pgid, signal.SIGKILL)
except Exception: pass

def tally(w, shift=0.0, length=None):
    a = w[0] + GUARD + shift; b = (w[1] - GUARD) if length is None else a + length
    n = d = by = 0
    for t, isd, pl in pkts:
        if a <= t <= b: n += 1; by += pl; d += isd
    return n, d, by
run = [tally(r) for r, _ in wins]; pau = [tally(p) for _, p in wins]
burst = [tally((p[1], p[1]), shift=-GUARD, length=0.010) for _, p in wins]   # first 10 ms after SIGCONT/release
m = lambda xs, i: statistics.mean(x[i] for x in xs)
print(f"\nscenario={SCEN} hold={'ON (real sch_plug)' if HOLD else 'off (SIGSTOP only)'} pause={PAUSE_MS}ms cycles={CYCLES}")
print(f"{'':30}{'RUNNING':>10}{'PAUSED':>10}{'first 10ms after resume':>26}")
print(f"{'packets / window':30}{m(run,0):10.1f}{m(pau,0):10.1f}{m(burst,0):26.1f}")
print(f"{'payload kB / window':30}{m(run,2)/1e3:10.1f}{m(pau,2)/1e3:10.1f}{m(burst,2)/1e3:26.1f}")
base = m(run, 0)
if base > 0:
    leak = 100 * m(pau, 0) / base
    print(f"LEAK (packets)  = {leak:.1f}% of running rate   [0% = perfect hold]")
else:
    print(f"LEAK: not applicable - the service sent nothing while running, so there is nothing to compare "
          f"(paused window: {m(pau,0):.1f} packets; 0 means nothing leaked)")
if HOLD: print(f"plug qdisc after run: dropped={drops} backlog={backlog}   [dropped must be 0]")
print("RESULT scen=%s hold=%d pause_ms=%d cycles=%d run_pkts=%.1f paused_pkts=%.1f burst_pkts=%.1f run_kb=%.1f paused_kb=%.1f leak_pct=%s dropped=%s" % (
    SCEN, int(HOLD), PAUSE_MS, CYCLES, m(run, 0), m(pau, 0), m(burst, 0), m(run, 2) / 1e3, m(pau, 2) / 1e3,
    ("%.1f" % (100 * m(pau, 0) / base)) if base > 0 else "NA", drops if (HOLD and drops is not None) else "NA"))
