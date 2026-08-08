$outPath = 'G:\projects\netpoke\netpoke\thesis\drafts\v2_revised\Chapter_1_Revised.docx'

function Para([string]$text, [string]$style='Normal') {
    $e = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    "<w:p><w:pPr><w:pStyle w:val='$style'/></w:pPr><w:r><w:t xml:space='preserve'>$e</w:t></w:r></w:p>"
}

$b = ''
$b += Para 'Chapter 1: Introduction' 'Heading1'

$b += Para '1.1 Introduction' 'Heading2'
$b += Para 'Most large-scale cloud applications today are built as collections of small, independently deployable services rather than as a single unified program. This microservice model makes it easier to develop, deploy, and scale individual components, but it introduces a harder problem: predicting and improving the performance of the system as a whole. With dozens of services calling each other over the network, it is rarely obvious which one to optimise first, and because engineering time is finite, guessing wrong is expensive.'
$b += Para 'Throughput, the number of requests a system can handle per second, is the metric that matters most for cost efficiency and user experience, especially under sustained or bursty traffic. But scaling up an individual service does not automatically translate into a faster application overall. Services depend on each other in complicated ways, and an optimisation that looks significant in isolation can have almost no measurable effect on the end-to-end number that operators actually care about. What is missing is a principled way to ask what-if before committing engineering effort: a way to estimate, in advance, how much a given change would actually help.'
$b += Para "SlowPoke, presented by Xie et al. at NSDI 2026, is the first system to answer that question with a working prediction model rather than a rule of thumb. It estimates the throughput impact of speeding up one service by deliberately slowing down the others using SIGSTOP, the standard Unix signal for pausing a process, so that the slowed-down execution reproduces the bottleneck that a real optimisation would create. The method requires no internal knowledge of each service's resource usage and no changes to application code. Across four real-world microservice applications, the paper reports a mean prediction error of just 2.07%, a strong result for a technique that treats each service largely as a black box."
$b += Para "This thesis is about a gap in that mechanism. SIGSTOP pauses a process's CPU scheduling, but it does not pause the kernel. While a service sits frozen, the operating system continues accepting network packets on its behalf and continues handling I/O completions in the background. That leftover activity, which this thesis calls residual I/O, is invisible to the pause and surfaces the moment the process resumes. For a service that spends most of its time computing, this barely matters. For a service that spends most of its time waiting on a database query or a downstream network call, it can matter considerably."
$b += Para 'The consequence is that SlowPoke is reliable for CPU-bound services but degrades for I/O-bound ones, exactly the category that dominates modern backend systems. The original paper acknowledged this as a direction for future work. This thesis takes that direction directly: first by confirming the problem is real and measuring its size across four representative microservice benchmarks, then by designing, implementing, and evaluating a fix.'
$b += Para "The fix, called NetPoke, adds a Linux tc sch_plug egress hold to each SIGSTOP/SIGCONT pair inside SlowPoke's POKER controller. When a service is paused, its outbound network queue is also plugged, preventing in-flight packets from being delivered until the pause ends. This keeps the kernel's view of the service consistent with the process's own view, eliminating the residual I/O that corrupts measurements. The mechanism is implemented entirely in user space, requires no kernel modifications, and is controlled by a single environment variable, making it straightforward to deploy alongside existing SlowPoke setups."

$b += Para '1.2 Problem Statement' 'Heading2'
$b += Para "SlowPoke's causal profiling approach rests on a specific assumption: that pausing a non-target service with SIGSTOP produces a bottleneck-equivalent execution, one where the same resource becomes the application bottleneck as it would in the hypothetically optimised scenario. For CPU-bound services this assumption holds well. Stopping the process removes its CPU time from the queue, which is precisely what a real optimisation removing that processing time would do."
$b += Para "The assumption breaks down for synchronous I/O operations. When a service is paused while packets are in flight or while disk reads are pending, the kernel buffers those operations. The paused process cannot consume them, but the kernel continues receiving and queuing them. When the process resumes, it immediately processes the backlog of buffered I/O that accumulated during the pause window. This residual I/O was never accounted for by the performance model, because from the model's perspective the service was simply stopped."
$b += Para 'The effect is a violation of bottleneck equivalence. The execution is slowed down as intended, but the bottleneck is not preserved in the way the model assumes. The severity scales with I/O intensity: for a service making frequent blocking database queries or synchronous downstream calls, the buffered backlog can represent hundreds of milliseconds of work that the model treats as absent. The throughput predictions that result are systematically optimistic, and the error grows with the depth of the hypothetical optimisation being evaluated.'
$b += Para 'The original SlowPoke paper noted this limitation. The SIGSTOP mechanism has limited reach into the OS kernel: once a packet enters the kernel network stack, SIGSTOP cannot stop it from being processed further. The authors suggested that future work might address I/O-bound bottlenecks through sidecars or I/O throttling, but neither approach was implemented or evaluated. This leaves a concrete gap between the theoretical promise of causal profiling for microservice optimisation and its practical reliability in I/O-heavy deployments.'

$b += Para '1.3 Aim' 'Heading2'
$b += Para "The aim of this thesis is to extend SlowPoke's prediction accuracy to I/O-bound microservices by identifying the root cause of its degradation under I/O-intensive workloads, and by designing and evaluating a lightweight network-layer mitigation that restores bottleneck equivalence without modifying the kernel or the application."

$b += Para '1.4 Objectives' 'Heading2'
$b += Para 'The specific objectives of this thesis are to:'
$b += Para '1. Quantify the I/O gap. Design and run controlled experiments that measure the increase in prediction error when SlowPoke is applied to services with synchronous I/O operations, across four benchmarks and two levels of I/O injection intensity: L1 (moderate, 30 ms netem delay on one downstream service) and L2 (heavy, 50 ms on the primary downstream service and 30 ms on a secondary).'
$b += Para '2. Validate the root cause. Use in-pod eBPF instrumentation to directly observe and measure I/O activity during SIGSTOP pause windows, and confirm that the observed residual I/O correlates with prediction degradation rather than other confounding factors.'
$b += Para '3. Design and implement a network-layer mitigation. Build NetPoke: a tc sch_plug egress hold synchronised with each SIGSTOP/SIGCONT pair inside POKER, implemented in user space via a persistent AF_NETLINK socket with a 100 ms receive timeout, deployable via a single SLOWPOKE_NETPOKE environment variable in existing Kubernetes setups.'
$b += Para '4. Evaluate the mitigation. Run paired experiments comparing SIGSTOP-only and NetPoke-on conditions at L0 (no injection), L1, and L2 injection levels across all four benchmarks, measuring RMSE restoration, residual I/O reduction, and overhead.'
$b += Para '5. Characterise trade-offs and limitations. Identify the conditions under which NetPoke is effective, the overhead it introduces, and the deployment scenarios where it may not apply, including the boutique fan-out case where the target service uses in-process storage rather than real network I/O.'

$b += Para '1.5 Research Questions' 'Heading2'
$b += Para "RQ1: Does I/O-boundedness increase SlowPoke's prediction error? How much does RMSE grow when synchronous I/O delays are added to downstream services, and does the increase scale with injection intensity across different benchmark applications?"
$b += Para 'RQ2: Does residual I/O persist during SIGSTOP pause windows? Can in-pod measurement confirm that the kernel continues delivering I/O to paused services, and is the volume of residual I/O consistent with the observed prediction degradation?'
$b += Para 'RQ3: Does the sch_plug egress hold suppress residual I/O? When NetPoke is active, does the volume of I/O activity during pause windows decrease to a level consistent with the baseline CPU-bound condition?'
$b += Para 'RQ4: Does suppressing residual I/O restore prediction accuracy? Do RMSE values under NetPoke-on conditions return to levels comparable to the SIGSTOP-only baseline at L0, and what is the cost in terms of latency overhead and prediction stability?'

$b += Para '1.6 Significance of Study' 'Heading2'
$b += Para "This thesis addresses a concrete limitation in the only published system capable of what-if throughput prediction for microservice architectures. SlowPoke is a meaningful advance: it gives engineering teams a way to estimate the impact of optimisations before implementing them, without requiring invasive instrumentation or detailed knowledge of service internals. But its reliable operating envelope excludes I/O-bound services, which are the norm rather than the exception in modern cloud-native deployments. Database query services, REST API gateways, and microservices with synchronous downstream calls all fall outside the range where SlowPoke's predictions can be trusted."
$b += Para 'By extending causal profiling to I/O-bound services, this thesis broadens the class of optimisations that engineers can evaluate with confidence. Decisions about database query optimisation, caching policy, connection pool sizing, and synchronous call elimination all become amenable to what-if analysis rather than guesswork. The practical value is direct: fewer wasted engineering cycles on optimisations that do not move the end-to-end number.'
$b += Para 'The proposed fix is deliberately minimal. NetPoke adds a single kernel facility, tc sch_plug, to the existing POKER controller. It requires no changes to application code, no new sidecar containers, and no kernel patches. This minimalism matters for adoption: a fix that is hard to deploy will not be used. The approach is also general: any service whose I/O behaviour is dominated by network operations can benefit from the same mechanism, regardless of the specific microservice framework or language in use.'
$b += Para 'On a scientific level, this thesis provides the first quantitative characterisation of residual I/O as a failure mode in causal profiling for distributed systems. The eBPF-based measurement goes beyond anecdotal evidence to produce data-driven validation of the root cause, and the paired experimental design across four benchmarks and two injection levels provides a systematic basis for evaluating the fix.'

$b += Para '1.7 Justification of Study' 'Heading2'
$b += Para 'The microservice architecture has become the dominant pattern for large-scale distributed applications across cloud infrastructure, e-commerce, social media, and financial services. This pattern is operationally flexible and independently scalable, but it makes performance tuning substantially harder than in monolithic systems. An optimisation to one service can have unpredictable effects throughout the service graph, and the queueing and synchronisation dynamics that govern end-to-end throughput are difficult to reason about without empirical tools.'
$b += Para 'Current engineering practice relies on canary deployments to production or ad hoc benchmarking in pre-production environments. Both approaches are labour-intensive, and neither fully captures the resource interactions and traffic patterns of the live system. A what-if analysis tool that could predict optimisation effects before implementation would reduce both the cost and the risk of performance engineering decisions.'
$b += Para "SlowPoke is the right foundation for such a tool, but its current limitation to CPU-bound services means it cannot be applied to the majority of real-world optimisation decisions. The original paper's evaluation reported strong accuracy for CPU-bound targets and substantially higher error for I/O-bound ones, a gap the authors attributed to the pause mechanism rather than the model itself. Addressing that gap is therefore a natural and well-motivated next step, not a departure from the original work."
$b += Para 'The timing is also relevant. Recent trends in microservice design, including polyglot persistence, event-driven patterns, and synchronous service meshes, are increasing the proportion of I/O-bound bottlenecks in production systems. A prediction tool that works only for CPU-bound services is becoming less useful over time, not more. This thesis addresses that trajectory directly.'

$b += Para '1.8 Scope' 'Heading2'
$b += Para 'In scope:'
$b += Para "Controlled experiments characterising SlowPoke's prediction error under I/O injection across four microservice benchmarks: OnlineBoutique, Hotel Reservation, Social Network, and MovieReviews. Two injection levels are used: L1 (moderate) and L2 (heavy), with L0 (no injection) as the baseline."
$b += Para 'In-pod eBPF instrumentation to measure residual I/O during SIGSTOP pause windows, providing mechanistic evidence for the root cause.'
$b += Para 'Design and implementation of the NetPoke egress hold using Linux tc sch_plug, integrated into POKER via a persistent AF_NETLINK socket with a 100 ms receive timeout and a fallback to tc system calls.'
$b += Para 'Paired evaluation of SIGSTOP-only and NetPoke-on conditions at L0, L1, and L2 injection levels, measuring RMSE, residual I/O volume, and computational overhead on a three-worker GCP Kubernetes cluster.'
$b += Para 'Out of scope:'
$b += Para 'Kernel modifications or changes to SIGSTOP signal semantics. The entire NetPoke implementation operates in user space using standard kernel facilities.'
$b += Para 'Disk I/O buffering. The mechanism targets network-layer residual I/O; disk buffering during pause windows is a separate problem not addressed here.'
$b += Para 'Evaluation on microservice frameworks other than the four benchmarks listed above. The mechanism is expected to generalise, but this thesis validates it on a specific representative set.'
$b += Para 'Formal verification or theoretical analysis of bottleneck equivalence under network delay injection.'
$b += Para 'Assumptions: Services are deployed in Kubernetes, allowing tc commands to be issued from within the POKER process with NET_ADMIN capability. Pause durations are within the range where network delay injection is feasible without imposing unrealistic latency on the application. I/O operations are predominantly network-based rather than disk-based.'

$b += Para '1.9 Thesis Outline' 'Heading2'
$b += Para 'Chapter 2: Background and Related Work reviews the SlowPoke methodology in detail, covering the performance model, the SIGSTOP-based slowdown mechanism, and the original evaluation results. It also surveys related work on causal profiling, microservice performance prediction, and network-layer traffic shaping, situating this thesis within the broader literature.'
$b += Para "Chapter 3: Identifying and Characterising the I/O Gap presents the experiments that establish the problem. Controlled I/O injection at two intensity levels is applied to downstream services in each of the four benchmarks, and the resulting increase in RMSE is measured and compared against the L0 baseline. The boutique fan-out finding, that OnlineBoutique's cart service uses in-process storage rather than real network I/O, is documented here as it explains why boutique behaves differently from the other three benchmarks."
$b += Para 'Chapter 4: Mechanistic Validation Using eBPF uses in-pod instrumentation to directly observe I/O activity during SIGSTOP pause windows. The chapter provides quantitative evidence that residual I/O is present and measurable, and that its volume is consistent with the prediction degradation observed in Chapter 3.'
$b += Para 'Chapter 5: NetPoke Design and Implementation describes the egress hold mechanism in detail. It covers the integration of tc sch_plug into POKER via a persistent AF_NETLINK socket, the fallback to tc system calls when netlink is unavailable, the NET_ADMIN capability requirement, and the single-variable deployment interface.'
$b += Para 'Chapter 6: Evaluation and Results presents the paired experimental results across all four benchmarks and three injection levels. It reports RMSE under SIGSTOP-only and NetPoke-on conditions, residual I/O reduction measured by the in-pod sampler, and the computational overhead introduced by the egress hold.'
$b += Para 'Chapter 7: Discussion and Limitations examines the conditions under which NetPoke is effective, the cases where it may not apply, and the trade-offs inherent in the approach. It also discusses the implications of the boutique fan-out finding for the generalisability of the results.'
$b += Para 'Chapter 8: Conclusion summarises the contributions of the thesis, restates the significance of extending causal profiling to I/O-bound services, and identifies directions for future work.'

# ── Assemble XML parts ───────────────────────────────────────────────────────
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

# ── Write docx via ZipArchive (no BOM) ───────────────────────────────────────
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
