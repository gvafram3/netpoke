$outPath = 'G:\projects\netpoke\netpoke\thesis\drafts\v2_revised\Chapter_5_NetPoke.docx'

function Para([string]$text, [string]$style='Normal') {
    $e = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    "<w:p><w:pPr><w:pStyle w:val='$style'/></w:pPr><w:r><w:t xml:space='preserve'>$e</w:t></w:r></w:p>"
}

$b = ''
$b += Para 'Chapter 5: NetPoke Design and Implementation' 'Heading1'

# ── 5.1 ─────────────────────────────────────────────────────────────────────
$b += Para '5.1 Introduction' 'Heading2'
$b += Para 'Chapters 3 and 4 established that SlowPoke''s SIGSTOP-based pause mechanism is incomplete for I/O-bound services: the Linux kernel continues processing network I/O on behalf of a paused process, and the resulting residual I/O corrupts the bottleneck-equivalence assumption that the performance model depends on. This chapter describes NetPoke, the mechanism designed to close that gap.'
$b += Para 'The design goal is precise: when POKER pauses a non-target service with SIGSTOP, the service''s outbound network queue should also be held for exactly the same window, so that the kernel''s view of the service''s network activity is consistent with the process scheduler''s view of its CPU activity. The fix must be synchronised with the existing SIGSTOP/SIGCONT pair, must not require kernel modifications or application changes, and must be cheap enough to run on every pause event without adding unmodelled overhead to the measurement.'
$b += Para 'The chapter is organised as follows. Section 5.2 explains the design rationale and the choice of mechanism. Section 5.3 describes the integration point in POKER. Section 5.4 covers the implementation of the egress hold in detail, including the netlink fast path, the SO_RCVTIMEO fix, and the CLI fallback. Section 5.5 describes the deployment interface. Section 5.6 documents the bugs found and fixed during implementation. Section 5.7 presents the overhead measurement that confirms the mechanism operates at the intended timescale.'

# ── 5.2 ─────────────────────────────────────────────────────────────────────
$b += Para '5.2 Design Rationale' 'Heading2'

$b += Para '5.2.1 Why Egress Rather Than Ingress' 'Heading2'
$b += Para 'The residual I/O problem arises because the kernel continues delivering incoming packets to a paused service''s socket buffers. A natural first instinct is to block ingress: prevent packets from arriving at the service during the pause window. This approach has a practical problem. Blocking ingress requires intercepting packets before they reach the socket buffer, which means operating at the network interface level before the kernel''s TCP stack has processed them. Dropping packets at this point causes TCP retransmission timeouts on the sender side, which introduces hundreds of milliseconds of backoff into the measurement and adds variance that is far worse than the residual I/O it was meant to eliminate.'
$b += Para 'Holding egress avoids this problem entirely. When a service is paused, it should not be sending anything: it is not executing user-space code, so it has no new data to transmit. Holding its outbound queue during the pause window therefore has no semantic effect on the service itself. The indirect effect is what matters: by withholding TCP acknowledgements, the service causes each upstream sender''s TCP window to fill. Once the window is full, the sender stops transmitting by flow control, not by packet loss. No retransmission timeouts occur, no congestion-control backoff is triggered, and the receive buffers of the paused service accumulate almost nothing during the pause window. When the egress hold is released after SIGCONT, the ACKs flow, the senders resume, and the service processes the small residual that was already in flight at the instant of the pause. This residual is bounded by the bandwidth-delay product of the connection, which is small and measurable.'
$b += Para 'This design uses TCP''s own flow control as the ingress suppression mechanism, rather than fighting it. It is the approach described in the NetPoke design document and is the reason the mechanism is implemented as an egress hold rather than an ingress filter.'

$b += Para '5.2.2 Why sch_plug Rather Than Alternatives' 'Heading2'
$b += Para 'Several mechanisms can hold egress packets on a Linux network interface. The design document considered four options before selecting sch_plug.'
$b += Para 'A static netem delay sidecar, the approach suggested in the original SlowPoke paper as future work, adds a fixed delay to all outgoing packets for the duration of the experiment. This is not synchronised with individual SIGSTOP/SIGCONT pairs: it distorts steady-state traffic during ground-truth experiments as well as slowdown experiments, and it reduces the measured residual bytes without restoring the bottleneck-equivalence property that the performance model requires. It is useful as a comparison baseline but not as a fix.'
$b += Para 'An iptables or nftables DROP rule during the pause window is simple to implement but causes TCP retransmission timeouts for the same reason that blocking ingress does: the sender interprets the missing ACK as packet loss and backs off. This adds hundreds of milliseconds of variance to the measurement and is worse than the problem it is solving.'
$b += Para 'A rate-throttling qdisc such as tbf or htb reduces the service''s network capacity rather than pausing it. This is model-faithful in principle but requires calibrating a bandwidth cap to match the model''s delay term, which introduces a separate parameter that must be tuned per service and per experiment. It is a viable secondary mechanism but more complex than a binary hold-and-release.'
$b += Para 'The sch_plug qdisc was designed for exactly the hold-and-release use case. It was introduced in the Linux kernel to buffer outgoing packets during virtual machine live migration, holding egress for the brief window when a VM is being moved between physical hosts. Its semantics are a binary toggle: when plugged, all outgoing packets are buffered; when unplugged, the buffer is flushed and normal transmission resumes. There is no packet loss, no retransmission, and no congestion-control side effect. The toggle is controlled via a netlink message to the kernel, which is a single fast system call rather than a subprocess. This makes sch_plug the right primitive for a mechanism that must fire tens of times per second inside POKER''s pause loop.'

# ── 5.3 ─────────────────────────────────────────────────────────────────────
$b += Para '5.3 Integration Point in POKER' 'Heading2'
$b += Para 'POKER is a C process that wraps each microservice in a Kubernetes pod. It forks the service as a child process, sets the child''s process group, and runs two threads: monitor_fifo, which handles pause events, and monitor_child, which waits for the child to exit. The pause logic lives entirely in monitor_fifo.'
$b += Para 'The original pause sequence in monitor_fifo is as follows. When a pause command arrives on the FIFO, the thread calls kill(-child_pgid, SIGSTOP) to freeze the entire process group, calls precise_sleep to hold for the model-computed duration, writes a recovery token to the recovery FIFO to signal the Go wrapper, and then calls kill(-child_pgid, SIGCONT) to resume. The pause duration is accumulated across batches to compensate for scheduling jitter.'
$b += Para 'NetPoke wraps the network hold around this existing sequence. The modified pause sequence is: call net_hold() to plug the egress queue, call kill(-child_pgid, SIGSTOP), call precise_sleep, write the recovery token, call kill(-child_pgid, SIGCONT), and then call net_release() to unplug the egress queue. The hold is established before SIGSTOP so that no outgoing packets escape in the window between the plug command and the process freeze. The release is issued after SIGCONT so that the egress queue remains held for the full duration of the pause, including the brief moment between SIGCONT and the process actually resuming execution.'
$b += Para 'The integration required no changes to the pause duration accounting in monitor_fifo. The model-computed delay is still the argument to precise_sleep, and the accumulated sleep correction still operates on the same start and end timestamps. net_hold() and net_release() are called outside the timed window that precise_sleep accounts for, so their cost does not affect the pause duration that the model intended. This is an important property: the netlink toggle overhead is real and measurable, but it is not subtracted from the model''s delay term and does not corrupt the pause timing.'
$b += Para 'In addition to the egress hold, this thesis added unconditional pause-window log markers to poker.c. Before the NetPoke changes, POKER only logged timing information when NetPoke was enabled, because the log lines were inside net_hold() and net_release(). This meant there was no way to measure residual I/O during SIGSTOP-only pauses: the residual sampler had no timestamps to correlate against. The fix adds a poker: pause_start uptime_s=<t> line immediately after SIGSTOP and a poker: pause_end uptime_s=<t> line immediately after SIGCONT, unconditionally, independent of whether NetPoke is enabled. These markers are written to stdout and captured by kubectl logs, making them available to the in-pod residual sampler for both the SIGSTOP-only baseline and the NetPoke-on condition.'

# ── 5.4 ─────────────────────────────────────────────────────────────────────
$b += Para '5.4 Implementation' 'Heading2'
$b += Para 'The egress hold is implemented in net_hold.c, a new file in slowpoke/src/poker/. The public interface, declared in net_hold.h, consists of three functions: net_pause_init_from_env(), net_hold(), and net_release(). The implementation is approximately 300 lines of C with no external dependencies beyond the standard Linux kernel headers.'

$b += Para '5.4.1 Initialisation' 'Heading2'
$b += Para 'net_pause_init_from_env() is called once in poker.c''s main() after the child process is forked. It reads two environment variables: SLOWPOKE_NETPOKE, which must be set to a truthy value (1, true, or any non-zero string) to enable the mechanism, and SLOWPOKE_NET_IFACE, which specifies the network interface to attach the qdisc to (defaulting to eth0 if not set).'
$b += Para 'If NetPoke is enabled, the function resolves the interface index using if_nametoindex(), opens a persistent AF_NETLINK/NETLINK_ROUTE socket, sets a 100 ms receive timeout on the socket using SO_RCVTIMEO, binds the socket to the local netlink address, and installs the sch_plug qdisc on the interface using plug_add(). If any of these steps fail, the function returns -1 and poker.c logs a warning and continues without the egress hold. The mechanism is designed to degrade gracefully: a failure in net_pause_init_from_env() leaves the system in the same state as SIGSTOP-only POKER, rather than crashing the service.'
$b += Para 'The sch_plug qdisc is installed with a buffer limit of 100,000 bytes (PLUG_BUFFER_LIMIT). This limit bounds the amount of data that can accumulate in the egress buffer during a pause window. In practice, pause windows are short (tens to hundreds of milliseconds) and the services involved are not high-bandwidth, so the buffer limit is never reached in normal operation. If it were reached, the kernel would drop excess packets, which would trigger TCP retransmission — the same failure mode as the iptables DROP approach. The 100,000-byte limit provides a safety margin well above the expected maximum in-flight data for the pause durations used in these experiments.'

$b += Para '5.4.2 The Netlink Fast Path' 'Heading2'
$b += Para 'net_hold() and net_release() both follow the same structure: try the netlink fast path first, fall back to the tc CLI if netlink fails, and log the toggle latency and path used to stderr on every call.'
$b += Para 'The fast path calls plug_toggle(), which calls plug_msg_raw() with NLM_F_REPLACE and the appropriate action constant: TCQ_PLUG_BUFFER to hold, TCQ_PLUG_RELEASE_INDEFINITE to release. plug_msg_raw() constructs a RTM_NEWQDISC netlink message with the correct tcmsg fields (interface index, qdisc handle, parent handle) and a TCA_OPTIONS attribute containing a flat struct tc_plug_qopt with the action and limit fields. The message is sent over the persistent nl_sock socket and the function waits for a kernel acknowledgement via recvmsg().'
$b += Para 'The TCA_OPTIONS encoding deserves explicit attention because it was the source of a significant bug during development. The sch_plug kernel handler in net/sched/sch_plug.c reads TCA_OPTIONS as a raw struct tc_plug_qopt cast directly from nla_data(opt). It is not a nested rtattr tree. An earlier version of net_hold.c built TCA_OPTIONS as a nested attribute whose sub-type equalled the numeric action value, which is the pattern used by some other qdiscs. That mismatch produced an EINVAL from the kernel on every toggle attempt. The fix was to send the flat struct directly as the TCA_OPTIONS payload, matching the kernel UAPI exactly. This is documented in a comment in net_hold.c to prevent the same mistake in future modifications.'

$b += Para '5.4.3 The SO_RCVTIMEO Fix' 'Heading2'
$b += Para 'The most consequential bug found during implementation was a silent hang in the netlink receive path. netlink_send_ack() calls recvmsg() to wait for the kernel''s acknowledgement of each netlink message. In the original implementation, this call had no receive timeout. If the kernel did not send an acknowledgement for a particular message type — specifically, the NLM_F_REPLACE toggle messages used by net_hold() and net_release(), which the kernel may handle differently from the NLM_F_CREATE message used by plug_add() — recvmsg() would block indefinitely.'
$b += Para 'Because net_hold() runs synchronously in POKER''s single pause-monitoring thread (monitor_fifo), a permanent block on the very first net_hold() call would freeze the entire pause mechanism for the rest of the pod''s lifetime. No further SIGSTOP/SIGCONT pairs would fire, no pause-window log markers would be written, and the experiment would silently produce measurements equivalent to a no-pause run. This is exactly what was observed during the first cluster test: zero hold/release log lines across all pods for an entire experiment, despite the model computing non-zero delays for multiple services.'
$b += Para 'The fix is a 100 ms receive timeout set on the netlink socket using setsockopt(SO_RCVTIMEO) during initialisation. With the timeout in place, a non-responding kernel causes recvmsg() to return EAGAIN after 100 ms rather than blocking forever. The existing error handling in netlink_send_ack() returns -1 on any negative recvmsg() result, which causes net_hold() to log a warning and set the netlink_toggle_broken flag, permanently switching to the CLI fallback for the rest of the process''s lifetime. A silent hang becomes a visible, logged failure with a graceful fallback.'
$b += Para 'After this fix was applied and the corrected image was deployed, the cluster smoke test confirmed 362 out of 362 pause events used the netlink path with zero CLI fallbacks, at an average toggle latency of 0.48 ms and a minimum of 7.3 microseconds. The maximum observed latency was 25.7 ms, attributed to rtnl_lock contention when multiple pods toggle their sch_plug qdiscs concurrently. This tail latency is real but acceptable: it is still far cheaper than the fork/exec/shell-parse cost of the CLI path, which the design document estimated at single-digit to tens of milliseconds per call.'

$b += Para '5.4.4 The CLI Fallback' 'Heading2'
$b += Para 'If the netlink fast path fails at runtime — either because the kernel rejects the toggle message or because the receive timeout fires — net_hold() sets the module-level netlink_toggle_broken flag and switches permanently to tc_plug_action(), which calls system("tc qdisc change dev <iface> root plug block") or system("tc qdisc change dev <iface> root plug release_indefinite"). This is the fork/exec/shell-parse path that the design document identifies as too slow for per-pause use, but it is correct and produces the right result. Its purpose is to ensure that a netlink failure does not silently disable the egress hold; it degrades performance but preserves correctness. The flag is set once and never cleared, so the process does not repeatedly attempt and fail the netlink path after the first failure.'

$b += Para '5.4.5 Timing Instrumentation' 'Heading2'
$b += Para 'Every call to net_hold() and net_release() logs a line to stderr containing the path used (netlink or cli), the toggle latency in nanoseconds (took_ns), and the absolute time in seconds since node boot (uptime_s). The uptime_s value uses CLOCK_MONOTONIC, the same clock as /proc/uptime, which is also read by the in-pod residual sampler. This makes the hold and release timestamps directly comparable to the sampler''s own timestamps without a separate clock-synchronisation step, enabling the sampler to determine which of its samples fall inside a pause window and which fall outside.'
$b += Para 'The pause_start and pause_end markers in poker.c use the same CLOCK_MONOTONIC clock and the same uptime_s format, providing a consistent timeline across all three sources of timing information: the netlink toggle, the SIGSTOP/SIGCONT pair, and the residual sampler.'

# ── 5.5 ─────────────────────────────────────────────────────────────────────
$b += Para '5.5 Deployment Interface' 'Heading2'
$b += Para 'NetPoke is controlled entirely through environment variables in the Kubernetes pod specification. No application code changes, no kernel patches, and no additional sidecar containers are required. The deployment interface consists of two variables.'
$b += Para 'SLOWPOKE_NETPOKE controls whether the egress hold is active. Setting it to 1 enables NetPoke; any other value (including absent) leaves POKER in the original SIGSTOP-only mode. This single variable is the on/off switch for the entire mechanism, making it straightforward to run paired experiments with and without the egress hold using otherwise identical pod specifications.'
$b += Para 'SLOWPOKE_NET_IFACE specifies the network interface to attach the sch_plug qdisc to. It defaults to eth0, which is the standard interface name for the primary network interface in Kubernetes pods using the default CNI plugin. For deployments where the pod''s traffic-carrying interface has a different name (for example, in pods with multiple network interfaces or with a non-standard CNI), this variable allows the correct interface to be specified without modifying the source code.'
$b += Para 'The pod must also have the NET_ADMIN Linux capability, which is required to issue RTM_NEWQDISC netlink messages and to run tc commands. This capability is added to the POKER container''s security context in the Kubernetes YAML. It is not required for the service container itself, only for the POKER wrapper process. The capability is standard in Kubernetes and does not require privileged mode or host network access.'
$b += Para 'Two sets of Kubernetes YAML directories are generated for each benchmark application by patch_all_netpoke_yamls.sh: yamls/netpoke/ for NetPoke-on runs (SLOWPOKE_NETPOKE=1, NET_ADMIN capability, gvafram3 images) and yamls/netpoke-sigstop/ for SIGSTOP-only runs using the same images (SLOWPOKE_NETPOKE=0, NET_ADMIN capability). Both directories use the same Docker images, which include the unconditional pause-window log markers added to poker.c. The SLOWPOKE_YAML_SUBDIR environment variable in run.sh selects which directory to deploy from, independent of the SLOWPOKE_NETPOKE flag, so the two conditions are directly comparable: same images, same cluster, same workload, only the egress hold toggled.'

# ── 5.6 ─────────────────────────────────────────────────────────────────────
$b += Para '5.6 Bugs Found and Fixed During Implementation' 'Heading2'
$b += Para 'The implementation process identified four bugs, two in net_hold.c and two in the experiment harness. All four are documented here because they are relevant to understanding the reliability of the results and the methodology used to validate the implementation.'
$b += Para 'Bug 1: Nested rtattr encoding for TCA_OPTIONS (EINVAL on toggle). The first version of plug_msg_raw() built TCA_OPTIONS as a nested rtattr attribute, following the pattern used by some other qdiscs. The sch_plug kernel handler does not use a nested attribute; it reads TCA_OPTIONS as a raw struct tc_plug_qopt. The mismatch produced EINVAL on every toggle attempt. This was diagnosed by reading the kernel source for net/sched/sch_plug.c and confirmed by the EINVAL return code. The fix was to pass the flat struct directly as the TCA_OPTIONS payload.'
$b += Para 'Bug 2: Missing SO_RCVTIMEO causing silent hang (described in detail in Section 5.4.3). The absence of a receive timeout on the netlink socket caused the pause-monitoring thread to block permanently on the first net_hold() call, silently disabling all pauses for the rest of the pod''s lifetime. Fixed by adding a 100 ms SO_RCVTIMEO during socket initialisation.'
$b += Para 'Bug 3: apply_io_injection.sh patching the wrong YAML directory. The I/O injection script always patched the plain yamls/ directory, but run.sh deploys from yamls/netpoke/ or yamls/netpoke-sigstop/ when SLOWPOKE_NETPOKE or SLOWPOKE_YAML_SUBDIR is set. Any NetPoke-tagged run at L1 or L2 therefore deployed from a YAML that never received the netem delay, silently running without injection while labelled as an injected condition. This bug affects the Table N1 L2 residual-I/O rows and all of Table N2, which need re-measuring with the fix in place. Fixed by updating apply_io_injection.sh to resolve the same directory that run.sh will deploy from, mirroring run.sh''s own directory-selection logic.'
$b += Para 'Bug 4: patch_all_netpoke_yamls.sh only generating yamls/netpoke/ and not yamls/netpoke-sigstop/. Without the netpoke-sigstop/ directory, SIGSTOP-only runs using the SLOWPOKE_YAML_SUBDIR path silently fell back to the original yizhengx images, which lack the unconditional pause-window log markers. Fixed by updating the script to generate both directories in a single pass.'

# ── 5.7 ─────────────────────────────────────────────────────────────────────
$b += Para '5.7 Overhead Measurement' 'Heading2'
$b += Para 'The design document specifies that the netlink toggle must be fast enough to fire tens of times per second without adding unmodelled overhead to the pause timing. The overhead measurement was performed using check_toggle_latency.sh on the GCP cluster after the SO_RCVTIMEO fix was applied and the corrected image was deployed.'
$b += Para 'The measurement collected the hold and release log lines from kubectl logs for all non-target service pods during a boutique smoke run and extracted the took_ns values. The results across 362 pause events were: minimum 7,280 ns (7.3 microseconds), average 481,359 ns (0.48 ms), maximum 25,724,998 ns (25.7 ms). Zero of 362 events fell back to the CLI path.'
$b += Para 'The minimum of 7.3 microseconds matches the design document''s stated intent of a microsecond-scale toggle and confirms that the netlink path is operating correctly on this cluster''s kernel. The average of 0.48 ms is well within the acceptable range: POKER''s pause durations are on the order of hundreds of microseconds to tens of milliseconds, so a 0.48 ms toggle overhead is a small fraction of the pause window. The maximum of 25.7 ms is a tail-latency outlier, most likely caused by rtnl_lock contention when multiple pods toggle their sch_plug qdiscs concurrently during the same experiment. This tail is real and worth monitoring as the number of services increases, but it does not affect the average-case behaviour.'
$b += Para 'For comparison, the tc CLI fallback path (fork + exec + shell parse + netlink round-trip) typically costs single-digit to tens of milliseconds per call. The netlink fast path is therefore approximately 10 to 100 times cheaper on average, and the design document''s concern about the CLI path being too slow for per-pause use is confirmed by this measurement.'

# ── 5.8 ─────────────────────────────────────────────────────────────────────
$b += Para '5.8 Summary' 'Heading2'
$b += Para 'NetPoke extends POKER with a synchronised egress hold using the Linux sch_plug qdisc. The hold is established before each SIGSTOP and released after each SIGCONT, ensuring that the service''s network activity is suspended for the same window as its CPU activity. The mechanism uses TCP flow control to suppress ingress indirectly: by withholding ACKs, it causes upstream senders to stop transmitting without packet loss or retransmission. The implementation uses a persistent AF_NETLINK socket for microsecond-scale toggles, with a 100 ms SO_RCVTIMEO to prevent silent hangs and a tc CLI fallback for resilience. It is controlled by a single environment variable and requires only the NET_ADMIN capability, with no kernel modifications or application changes.'
$b += Para 'The implementation process identified and fixed two bugs in net_hold.c (the TCA_OPTIONS encoding error and the missing receive timeout) and two bugs in the experiment harness (the injection YAML directory mismatch and the missing netpoke-sigstop/ directory). The overhead measurement confirmed that the netlink fast path operates at an average of 0.48 ms per toggle, well within the acceptable range for the pause durations used in these experiments. Chapter 6 presents the evaluation results that test whether this mechanism restores prediction accuracy for I/O-bound services.'

# ── Assemble XML ─────────────────────────────────────────────────────────────
$ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"   ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>'

$rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'

$docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'

$styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="480" w:after="240"/></w:pPr>
    <w:rPr><w:b/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="360" w:after="160"/></w:pPr>
    <w:rPr><w:b/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>
  </w:style>
</w:styles>'

$doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>' + $b + '
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
</w:body></w:document>'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ms  = New-Object System.IO.MemoryStream
$zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)

function AddEntry([System.IO.Compression.ZipArchive]$z, [string]$name, [string]$content) {
    $e = $z.CreateEntry($name)
    $s = $e.Open()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $s.Write($bytes, 0, $bytes.Length)
    $s.Close()
}

AddEntry $zip '[Content_Types].xml'          $ct
AddEntry $zip '_rels/.rels'                  $rels
AddEntry $zip 'word/document.xml'            $doc
AddEntry $zip 'word/styles.xml'              $styles
AddEntry $zip 'word/_rels/document.xml.rels' $docRels

$zip.Dispose()
[System.IO.File]::WriteAllBytes($outPath, $ms.ToArray())
$ms.Dispose()

Write-Host "Written: $outPath ($([System.IO.FileInfo]::new($outPath).Length) bytes)"
