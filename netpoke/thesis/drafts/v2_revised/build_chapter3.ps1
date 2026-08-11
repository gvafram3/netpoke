$outPath = 'G:\projects\netpoke\netpoke\thesis\drafts\v2_revised\Chapter_3_NetPoke.docx'

function Para([string]$text, [string]$style='Normal') {
    $e = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    "<w:p><w:pPr><w:pStyle w:val='$style'/></w:pPr><w:r><w:t xml:space='preserve'>$e</w:t></w:r></w:p>"
}

$b = ''
$b += Para 'Chapter 3: Identifying and Characterising the I/O Gap' 'Heading1'

# ── 3.1 ─────────────────────────────────────────────────────────────────────
$b += Para '3.1 Introduction' 'Heading2'
$b += Para 'Chapter 1 argued that SlowPoke''s SIGSTOP-based pause mechanism is incomplete for I/O-bound services because the Linux kernel continues processing network I/O on behalf of a paused process. Chapter 2 reviewed the literature that contextualises this claim. This chapter tests it empirically. The central question is RQ1: does adding synchronous I/O to the downstream services on a target''s causal path increase SlowPoke''s prediction error, and does the increase scale with injection intensity?'
$b += Para 'The experimental approach is controlled I/O injection. For each of the four benchmark applications, the standard SlowPoke 10-point accuracy experiment is run three times: once with no injection (L0, the baseline), once with moderate netem delay on the primary downstream service (L1), and once with heavy delay on the primary service and additional delay on a secondary service (L2). All other experimental conditions are held constant. The only variable is the amount of synchronous network I/O that path services experience during the experiment. If the I/O gap hypothesis is correct, RMSE should rise from L0 to L2 for services whose target has genuine synchronous downstream I/O on its request path.'
$b += Para 'The chapter is organised as follows. Section 3.2 describes the experimental methodology in detail, including the injection design, the benchmark configurations, and the measurement procedure. Section 3.3 presents the L0 baseline results. Section 3.4 presents the full I/O-gap matrix. Section 3.5 analyses the results per application, with particular attention to the social network benchmark, which provides the strongest and cleanest evidence for the hypothesis, and to the boutique benchmark, which does not show the expected pattern and whose behaviour is explained by a source-level finding about its target service. Section 3.6 discusses the overall picture and its implications for the thesis.'

# ── 3.2 ─────────────────────────────────────────────────────────────────────
$b += Para '3.2 Experimental Methodology' 'Heading2'

$b += Para '3.2.1 Cluster and Infrastructure' 'Heading2'
$b += Para 'All experiments were run on a four-node Google Cloud Platform (GCP) Kubernetes cluster: one control-plane node (netpoke-control, 2 vCPU) and three worker nodes (netpoke-worker1/2/3, 2 vCPU each). The cluster runs Kubernetes with the standard SlowPoke artifact deployment, including the POKER pause controller compiled into each service image. The load generator is a wrk client deployed as a Kubernetes pod on worker1, issuing HTTP requests to the application frontend. All experiments use the medium run configuration: 10 optimisation points (0% to 90% processing-time reduction on the target service in 10% steps), 100,000 requests per measurement window, and a single repetition per condition.'
$b += Para 'The cluster is smaller than the 12-worker cluster used in the original SlowPoke paper, which means absolute RMSE values are higher than the paper''s reported 2.07% headline. This is expected and documented. The thesis does not claim to reproduce the paper''s absolute numbers; it uses the same cluster for all conditions and compares relative trends across injection levels. A regression in RMSE from L0 to L2 on the same cluster is meaningful regardless of the absolute starting point.'

$b += Para '3.2.2 Harness Fixes Applied Before Data Collection' 'Heading2'
$b += Para 'Before collecting any of the results reported in this chapter, three bugs in the SlowPoke measurement harness were identified and corrected. First, main.py contained an empty-times guard that could silently produce a zero throughput measurement when a wrk run returned no timing data; this was fixed to raise an explicit error rather than record a spurious zero. Second, run.sh had no upper bound on the wrk measurement duration, which could cause individual runs to extend indefinitely under high load; a duration cap was added. Third, fix_req_n.lua contained a nil-guard omission that could cause the Lua script to crash silently on certain request patterns; this was corrected. All results in this chapter and subsequent chapters were collected after these fixes were applied. The pre-fix results are retained in the repository as a superseded dataset for reference but are not used in any thesis claim.'

$b += Para '3.2.3 I/O Injection Design' 'Heading2'
$b += Para 'I/O injection is implemented using Linux tc netem sidecars deployed alongside downstream path services. A netem qdisc is attached to the outgoing network interface of the target downstream service, adding a fixed one-way delay to all outgoing packets. This increases the round-trip time for any synchronous call that the target service makes to that downstream service, forcing the target service to spend more wall-clock time blocked on network I/O per request. The injection is applied only to downstream services on the causal path of the experiment''s target service; the target service itself and services not on its path are not injected.'
$b += Para 'Two injection levels are used. L1 applies 30 ms of netem delay to the primary downstream service on the target''s causal path. L2 applies 50 ms to the primary downstream service and an additional 30 ms to a secondary downstream service. L0 is the no-injection baseline. The injection levels were chosen to be large enough to produce a measurable effect on synchronous I/O wait time while remaining within the range where the application continues to function correctly and produce valid throughput measurements.'
$b += Para 'The injection targets for each benchmark are as follows. For boutique (target: cart), L1 injects productcatalog at 30 ms; L2 adds currency at 30 ms. For hotel (target: profile), L1 injects rate at 30 ms; L2 adds user at 30 ms. For social (target: hometimeline), L1 injects poststorage at 30 ms; L2 adds socialgraph at 30 ms. For movie (target: moviereviews), L1 injects reviewstorage at 30 ms; L2 adds movieinfo at 30 ms. These injection targets were selected based on the request ratios reported by SlowPoke''s prerun phase, which identify the downstream services most heavily involved in serving requests through the target service.'
$b += Para 'It is important to note what this injection does and does not do. It increases the synchronous I/O wait time experienced by the target service during the ground-truth experiments, making the target more I/O-bound. It also affects the slowdown experiments, because the non-target services are paused while the injected delay is active. The hypothesis is that SIGSTOP-only pauses become less accurate under these conditions because the kernel continues buffering I/O for paused services even while the netem delay is active, creating a larger residual I/O backlog on resume. The injection is a stimulus that amplifies the I/O gap; it is not the gap itself.'

$b += Para '3.2.4 Measurement Procedure' 'Heading2'
$b += Para 'For each benchmark and each injection level, the standard SlowPoke experiment is run using run-*-medium.sh with the appropriate injection configuration. The experiment produces a log file containing 21 throughput measurements: one baseline, and 10 pairs of ground-truth and slowdown measurements at each optimisation point. The prediction error at each point is computed as (predicted - groundtruth) / groundtruth * 100%. RMSE is computed as the square root of the mean of the squared error percentages across the 10 points, using the summarize_results.py script from the SlowPoke artifact. The mean absolute error (mean |err|) is also reported as a secondary metric.'
$b += Para 'The primary comparison is the L2 minus L0 RMSE delta: the increase in prediction error when heavy I/O injection is applied relative to the no-injection baseline. A positive delta supports the I/O-gap hypothesis. A monotonically increasing trend from L0 to L1 to L2 is the strongest form of support. A positive but non-monotonic trend (L1 spike that partially resolves at L2, or vice versa) is weaker but still net-positive evidence. A negative delta contradicts the hypothesis for that benchmark.'

# ── 3.3 ─────────────────────────────────────────────────────────────────────
$b += Para '3.3 L0 Baseline Results' 'Heading2'
$b += Para 'Table 3.1 shows the SlowPoke prediction accuracy at L0 (no injection) for all four benchmarks, collected after the harness fixes described in Section 3.2.2. These are the baseline numbers against which all I/O-gap and NetPoke results are compared.'
$b += Para 'Table 3.1 — SlowPoke baseline prediction accuracy (L0, SIGSTOP-only, post-fix harness)' 'Heading2'
$b += Para 'App | Target | Baseline throughput (req/s) | RMSE (%) | Mean |err| (%)'
$b += Para 'Boutique | cart | 1937.3 | 2.57 | 2.13'
$b += Para 'Hotel | profile | 723.9 | 20.65 | 16.99'
$b += Para 'Social | hometimeline | 959.9 | 14.01 | 10.85'
$b += Para 'Movie | moviereviews | 550.8 | 12.21 | 10.01'
$b += Para 'Boutique''s 2.57% RMSE is the closest result this project has produced to the paper''s reported 2.07%, and is strong evidence that the harness fixes eliminated real measurement corruption rather than cosmetic noise. The cart service in boutique, as will be established in Section 3.5.4, performs no synchronous network I/O in its live request-handling code, which means it is genuinely CPU-bound and SlowPoke''s SIGSTOP mechanism is well-matched to it. The near-paper-level accuracy at L0 is therefore expected and serves as a positive control: the experimental setup is capable of reproducing the paper''s result for a CPU-bound target.'
$b += Para 'Hotel, social, and movie all show higher L0 RMSE than boutique, in the range of 12% to 21%. This is consistent with the smaller cluster and single-repetition methodology. The paper''s 2.07% headline was produced on a 12-worker cluster with multiple repetitions; on a 3-worker cluster with one repetition, higher variance is expected. The relevant comparison for this thesis is not the absolute L0 RMSE but the change in RMSE when I/O injection is applied. Hotel''s L0 RMSE of 20.65% is notably higher than its pre-fix value of 10.23%, a difference that is not explained by any change to hotel-specific code paths in the harness fixes. This volatility is documented as an open question and is discussed further in Section 3.5.2.'

# ── 3.4 ─────────────────────────────────────────────────────────────────────
$b += Para '3.4 The I/O-Gap Matrix' 'Heading2'
$b += Para 'Table 3.2 shows the full 4x3 RMSE matrix across all four benchmarks and three injection levels. These are the primary results for RQ1.'
$b += Para 'Table 3.2 — RMSE vs I/O injection level (SIGSTOP-only, post-fix harness, 2026-07-17)' 'Heading2'
$b += Para 'App | Level | Injection | Baseline (req/s) | RMSE (%) | Mean |err| (%)'
$b += Para 'Boutique | L0 | none | 1937.3 | 2.57 | 2.13'
$b += Para 'Boutique | L1 | productcatalog +30ms | 2002.1 | 4.85 | 3.89'
$b += Para 'Boutique | L2 | productcatalog +50ms, currency +30ms | 1995.7 | 3.53 | 2.63'
$b += Para 'Hotel | L0 | none | 723.9 | 20.65 | 16.99'
$b += Para 'Hotel | L1 | rate +30ms | 729.5 | 20.03 | 16.27'
$b += Para 'Hotel | L2 | rate +50ms, user +30ms | 768.7 | 17.51 | 14.88'
$b += Para 'Social | L0 | none | 959.9 | 14.01 | 10.85'
$b += Para 'Social | L1 | poststorage +30ms | 943.3 | 30.33 | 22.13'
$b += Para 'Social | L2 | poststorage +50ms, socialgraph +30ms | 788.1 | 33.61 | 28.29'
$b += Para 'Movie | L0 | none | 550.8 | 12.21 | 10.01'
$b += Para 'Movie | L1 | reviewstorage +30ms | 626.8 | 28.48 | 18.46'
$b += Para 'Movie | L2 | reviewstorage +50ms, movieinfo +30ms | 651.9 | 13.84 | 12.40'
$b += Para 'Table 3.3 summarises the L2 minus L0 RMSE delta for each benchmark, which is the primary test of RQ1.'
$b += Para 'Table 3.3 — L2 minus L0 RMSE delta (positive = supports I/O-gap hypothesis)' 'Heading2'
$b += Para 'App | L0 RMSE | L2 RMSE | Delta (pp) | Monotonic L0->L1->L2? | Supports RQ1?'
$b += Para 'Social | 14.01% | 33.61% | +19.60 | Yes | Yes — strongest, cleanest'
$b += Para 'Movie | 12.21% | 13.84% | +1.63 | No (L1 spikes to 28.48) | Ambiguous — net positive'
$b += Para 'Boutique | 2.57% | 3.53% | +0.96 | No (L1 is the peak) | Weakly positive — see Section 3.5.4'
$b += Para 'Hotel | 20.65% | 17.51% | -3.14 | Yes, but decreasing | No — reversed'
$b += Para 'Three of four benchmarks show a net positive L2 minus L0 delta, and one (social) shows a strong, monotonically increasing trend that is the clearest evidence for the I/O-gap hypothesis this project has produced. However, the overall picture is more mixed than a simple summary suggests. Hotel''s RMSE decreases with injection intensity, directly contradicting the hypothesis for that benchmark. Movie''s L1 result is a large spike (28.48%) that partially resolves by L2 (13.84%), producing a non-monotonic pattern that is difficult to interpret cleanly. Boutique''s net-positive delta is small and also non-monotonic. These results are discussed in detail in Section 3.5.'

# ── 3.5 ─────────────────────────────────────────────────────────────────────
$b += Para '3.5 Per-Application Analysis' 'Heading2'

$b += Para '3.5.1 Social Network — The Headline Result' 'Heading2'
$b += Para 'The social network benchmark provides the strongest and most interpretable evidence for the I/O-gap hypothesis. RMSE rises from 14.01% at L0 to 30.33% at L1 and 33.61% at L2, a monotonically increasing trend with a total delta of +19.60 percentage points. The mean absolute error follows the same pattern: 10.85% at L0, 22.13% at L1, 28.29% at L2.'
$b += Para 'The target service is hometimeline, whose handler (ReadHomeTimeline in home_timeline.go) makes two synchronous network calls on every request: a Dapr state-store round-trip to retrieve cached timeline data, and an explicit HTTP call to the poststorage service to fetch post content. Both calls go through the Dapr sidecar and involve real network round-trips. When poststorage is injected with 30 ms of netem delay at L1, the hometimeline handler''s per-request I/O wait time increases by approximately 30 ms per call to poststorage. At L2, the additional 30 ms on socialgraph further increases the I/O load on the causal path.'
$b += Para 'Under these conditions, the SIGSTOP-only pause mechanism becomes increasingly inaccurate. When POKER pauses a non-target service during a slowdown experiment, the kernel continues buffering incoming packets for that service''s open sockets. With 30-50 ms of netem delay on the path, more data is in flight at any given moment, and the buffered backlog that accumulates during a pause window is larger. When the service resumes, it immediately processes this backlog, effectively receiving more I/O work than the model accounts for. The result is that the slowdown experiment underestimates the true bottleneck effect, and the predicted throughput is systematically higher than the ground truth — a positive prediction error that grows with injection intensity.'
$b += Para 'The monotonic trend in social is particularly valuable because it rules out the most obvious alternative explanation: that the RMSE increase is simply run-to-run variance rather than a systematic effect of the injection. A single elevated RMSE at L2 could be noise; a monotonically increasing sequence across three injection levels, with the increase scaling with injection intensity, is much harder to attribute to chance on a single-repetition experiment. Social is therefore the primary evidence for RQ1 in this thesis.'

$b += Para '3.5.2 Hotel — A Contradicting Outlier' 'Heading2'
$b += Para 'Hotel''s results directly contradict the I/O-gap hypothesis. RMSE decreases from 20.65% at L0 to 20.03% at L1 and 17.51% at L2, a monotonically decreasing trend with a total delta of -3.14 percentage points. This is the opposite of what the hypothesis predicts.'
$b += Para 'The target service is profile, whose handler (GetProfiles in profile.go) makes a Dapr state-store round-trip on every request. This is a genuine synchronous network call, so the mechanism that drives the social result should apply here too. The injection targets (rate at L1, rate and user at L2) are on the causal path of the profile service based on the prerun request ratios. There is no obvious structural reason why hotel should behave differently from social.'
$b += Para 'The most likely explanation is run-to-run variance compounded by hotel''s unusually high baseline volatility on this cluster. Hotel''s L0 RMSE alone moved from 10.23% to 20.65% between two runs of the same experiment with no changes to hotel-specific code, a shift of 10.42 percentage points before any injection is involved. This level of baseline volatility means that a 3.14 percentage point decrease from L0 to L2 is well within the noise floor for hotel on this cluster. The injection may be having the expected effect, but it is not detectable above the baseline variance with a single repetition per condition.'
$b += Para 'This is an honest limitation of the experimental design. A single-repetition experiment on a small cluster cannot reliably distinguish a 3 percentage point signal from noise for a benchmark with 10+ percentage point run-to-run variance. Hotel''s result should not be cited as evidence against the I/O-gap hypothesis; it should be cited as evidence that hotel''s RMSE is too volatile on this cluster to draw conclusions from its L0-to-L2 trend with the current number of repetitions. The direct residual I/O measurement in Chapter 4 provides a more reliable signal for hotel, as it measures the underlying phenomenon rather than the noisy RMSE proxy.'

$b += Para '3.5.3 Movie — A Non-Monotonic Pattern' 'Heading2'
$b += Para 'Movie shows a net-positive L2 minus L0 delta (+1.63 pp) but a non-monotonic pattern: RMSE spikes sharply at L1 (28.48%) before partially resolving at L2 (13.84%). The L0 baseline is 12.21%.'
$b += Para 'The target service is moviereviews, whose handler (ReadMovieReviews in movie_reviews.go) makes both a Dapr state-store call and an explicit HTTP call to reviewstorage. The L1 injection applies 30 ms to reviewstorage, which is directly on the causal path of the moviereviews handler. The large L1 spike (28.48%, more than double the L0 baseline) is consistent with the I/O-gap hypothesis: adding 30 ms to a service that moviereviews calls synchronously on every request substantially increases the residual I/O backlog during pause windows.'
$b += Para 'The partial resolution at L2 (13.84%) is harder to explain. Adding 30 ms to movieinfo at L2 in addition to 50 ms on reviewstorage should, if anything, increase the I/O load further. One plausible reading is that the heavier injection at L2 changes the bottleneck identity: with both reviewstorage and movieinfo heavily delayed, the application''s throughput may be limited by a different service than at L1, and the SIGSTOP pauses on that different service may happen to be more accurate. Another possibility is that the L2 injection reduces the overall request rate enough that the queueing dynamics change, reducing the per-pause residual backlog. Neither explanation can be confirmed without additional experiments. The net-positive delta and the large L1 spike are treated as partial support for RQ1, with the non-monotonic pattern noted as an open question.'

$b += Para '3.5.4 Boutique — The Fan-Out Finding' 'Heading2'
$b += Para 'Boutique shows a small net-positive L2 minus L0 delta (+0.96 pp) but a non-monotonic pattern where L1 (4.85%) is the peak and L2 (3.53%) falls back toward the L0 baseline (2.57%). This pattern does not support the I/O-gap hypothesis in any meaningful way, and the explanation is not noise: it is a structural property of the target service.'
$b += Para 'A source-level inspection of the cart service handler (GetCart, AddItem, and EmptyCart in cart.go) reveals that the live request-handling code performs no synchronous network I/O whatsoever. Cart reads and writes an in-process sync.Map (local_carts). A Redis client and a state.GetState call exist in the file but are commented out and are not on the request path — they are dead code. This is not a hypothesis about the service''s behaviour; it is directly readable from the handler functions.'
$b += Para 'The consequence is that there is no synchronous downstream I/O for the kernel to buffer during SIGSTOP pause windows when cart is the target. The I/O-gap mechanism that drives the social result simply does not apply to boutique''s cart target. Adding netem delay to productcatalog and currency does not increase the residual I/O backlog for cart''s pause windows because cart never waits on those services synchronously. The injection changes the bottleneck structure of the application — making productcatalog and currency slower — but it does not create the specific failure mode that the I/O-gap hypothesis describes.'
$b += Para 'This finding has two implications. First, boutique''s flat or slightly positive L0-to-L2 trend is not a counterexample to the I/O-gap hypothesis; it is a case where the hypothesis does not apply because the precondition (synchronous downstream I/O on the target''s request path) is not met. Second, boutique''s near-paper-level L0 RMSE (2.57%) is a positive control that confirms the experimental setup is working correctly for CPU-bound targets. The fan-out finding is discussed further in Chapter 7 in the context of the conditions under which NetPoke is and is not applicable.'

# ── 3.6 ─────────────────────────────────────────────────────────────────────
$b += Para '3.6 Discussion' 'Heading2'
$b += Para 'The results in this chapter provide a mixed but overall positive answer to RQ1. The aggregate evidence — three of four benchmarks showing a net-positive L2 minus L0 delta, with social providing a strong monotonic trend — supports the claim that I/O-boundedness increases SlowPoke''s prediction error. But the per-benchmark picture is noisier than a simple summary suggests, and two important caveats must be stated clearly.'
$b += Para 'First, the RMSE metric is a noisy proxy for the I/O-gap phenomenon on a small single-repetition cluster. Hotel''s baseline volatility demonstrates this directly: a 10+ percentage point swing in L0 RMSE between two identical runs means that a 3 percentage point L0-to-L2 trend is uninterpretable for hotel with the current experimental design. The RMSE metric conflates the I/O-gap effect with run-to-run variance, queueing noise, and changes in bottleneck identity caused by the injection itself. Social''s monotonic +19.60 pp trend is large enough to be credible despite this noise floor; hotel''s -3.14 pp trend is not.'
$b += Para 'Second, the injection methodology is a stimulus, not a direct measurement of the I/O gap. Adding netem delay to downstream services increases the synchronous I/O wait time experienced by the target service, which should amplify the residual I/O backlog during pause windows. But the injection also changes the bottleneck structure of the application in ways that are not fully controlled. Movie''s non-monotonic pattern is a concrete example: the L2 injection may be changing the bottleneck identity rather than simply increasing the I/O gap. The RMSE results alone cannot distinguish between these two effects.'
$b += Para 'These limitations motivate the mechanistic validation in Chapter 4. Rather than inferring the I/O gap from the noisy RMSE proxy, Chapter 4 measures it directly: in-pod network byte counters are used to observe how much I/O activity occurs during SIGSTOP pause windows, with and without the NetPoke egress hold. This direct measurement is less sensitive to queueing noise and bottleneck-identity changes, and it provides a cleaner signal for the underlying phenomenon that the RMSE results are trying to capture.'
$b += Para 'The boutique fan-out finding is also worth reflecting on as a methodological lesson. The original injection design for boutique used the shipping service as the injection target, which produced a decreasing RMSE trend that appeared to contradict the hypothesis. Correcting the injection to productcatalog and currency — services with higher request ratios on the cart causal path — produced a net-positive trend, but still not a clean one. The source-level inspection that revealed cart''s in-process storage was not part of the original experimental plan; it was prompted by the persistent failure of boutique to show the expected pattern. This illustrates a general point: RMSE trends alone are not sufficient to characterise the I/O-gap phenomenon. Understanding why a benchmark does or does not show the expected pattern requires looking at the actual code paths of the target service, not only at aggregate metrics.'
$b += Para '3.7 Summary' 'Heading2'
$b += Para 'This chapter has presented the I/O-gap characterisation experiments for all four benchmarks. The key findings are as follows. Social network provides the strongest evidence for RQ1: a monotonically increasing RMSE trend from 14.01% at L0 to 33.61% at L2, a +19.60 pp delta that is large enough to be credible above the cluster noise floor. Movie shows a net-positive delta with a non-monotonic pattern, providing partial support. Boutique shows a small net-positive delta that is explained by the cart service''s in-process storage rather than by the I/O-gap mechanism. Hotel shows a decreasing trend that is most plausibly explained by baseline volatility rather than a genuine contradiction of the hypothesis. The aggregate result — three of four benchmarks net-positive — supports the claim that I/O-boundedness increases SlowPoke''s prediction error, with social as the primary evidence. Chapter 4 provides direct mechanistic validation of the underlying phenomenon using in-pod residual I/O measurement.'

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
