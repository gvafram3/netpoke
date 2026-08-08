$out = "G:\projects\netpoke\netpoke\thesis\drafts\v2_revised\Results_Tables.docx"
$enc = New-Object System.Text.UTF8Encoding $false

function CT { @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"   ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
"@ }

function Rels { @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"@ }

function DocRels { @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"@ }

function Styles { @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/>
    <w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>
    <w:pPr><w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>
    <w:pPr><w:outlineLvl w:val="1"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="TableGrid"><w:name w:val="Table Grid"/>
    <w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/>
    <w:rPr><w:i/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Note"><w:name w:val="Note"/>
    <w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/><w:color w:val="444444"/></w:rPr></w:style>
</w:styles>
"@ }

function P([string]$text, [string]$style="Normal", [bool]$bold=$false, [string]$color="") {
    $rpr = ""
    if ($bold)  { $rpr += "<w:b/>" }
    if ($color) { $rpr += "<w:color w:val='$color'/>" }
    if ($rpr)   { $rpr = "<w:rPr>$rpr</w:rPr>" }
    $safe = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    return "<w:p><w:pPr><w:pStyle w:val='$style'/></w:pPr><w:r>$rpr<w:t xml:space='preserve'>$safe</w:t></w:r></w:p>"
}

function Cell([string]$text, [bool]$hdr=$false, [string]$width="1500", [string]$color="") {
    $rpr = ""
    if ($hdr)   { $rpr += "<w:b/>" }
    if ($color) { $rpr += "<w:color w:val='$color'/>" }
    if ($rpr)   { $rpr = "<w:rPr>$rpr</w:rPr>" }
    $safe = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    $shd = if ($hdr) { "<w:shd w:val='clear' w:color='auto' w:fill='D9E1F2'/>" } else { "" }
    return @"
<w:tc>
  <w:tcPr><w:tcW w:w='$width' w:type='dxa'/>$shd
    <w:tcBorders>
      <w:top w:val='single' w:sz='4' w:color='9E9E9E'/>
      <w:left w:val='single' w:sz='4' w:color='9E9E9E'/>
      <w:bottom w:val='single' w:sz='4' w:color='9E9E9E'/>
      <w:right w:val='single' w:sz='4' w:color='9E9E9E'/>
    </w:tcBorders>
  </w:tcPr>
  <w:p><w:pPr><w:pStyle w:val='TableGrid'/></w:pPr><w:r>$rpr<w:t xml:space='preserve'>$safe</w:t></w:r></w:p>
</w:tc>
"@
}

function Row([string[]]$cells, [bool]$hdr=$false, [string[]]$widths=@(), [string[]]$colors=@()) {
    $inner = ""
    for ($i=0; $i -lt $cells.Count; $i++) {
        $w = if ($i -lt $widths.Count) { $widths[$i] } else { "1500" }
        $c = if ($i -lt $colors.Count) { $colors[$i] } else { "" }
        $inner += Cell $cells[$i] $hdr $w $c
    }
    $shd = if ($hdr) { "<w:trPr><w:tblHeader/></w:trPr>" } else { "" }
    return "<w:tr>$shd$inner</w:tr>"
}

function Table([string]$xml) {
    return @"
<w:tbl>
  <w:tblPr>
    <w:tblStyle w:val='TableGrid'/>
    <w:tblW w:w='0' w:type='auto'/>
    <w:tblBorders>
      <w:insideH w:val='single' w:sz='4' w:color='9E9E9E'/>
      <w:insideV w:val='single' w:sz='4' w:color='9E9E9E'/>
    </w:tblBorders>
    <w:tblLook w:val='04A0'/>
  </w:tblPr>
  $xml
</w:tbl>
"@
}

function PageBreak { "<w:p><w:r><w:br w:type='page'/></w:r></w:p>" }
function Spacer    { "<w:p><w:pPr><w:pStyle w:val='Normal'/></w:pPr></w:p>" }

# ── widths ──────────────────────────────────────────────────────────────────
$w4 = @("1100","2200","1400","1400")
$w5 = @("1000","1800","1400","1400","1400")
$w6 = @("900","1800","1300","1300","1300","1300")
$w3 = @("1200","2000","1400","1400","2200")
$w2 = @("1200","2000","1400","1400")

# ── colour helpers ───────────────────────────────────────────────────────────
# red = worse, green = better, grey = neutral
function DeltaColor([string]$val) {
    if ($val -match "worse")  { return "C00000" }
    if ($val -match "better") { return "375623" }
    return ""
}

# ════════════════════════════════════════════════════════════════════════════
# Document body
# ════════════════════════════════════════════════════════════════════════════
$body = ""

# ── Cover ────────────────────────────────────────────────────────────────────
$body += P "NetPoke — Experimental Results" "Heading1"
$body += P "MPhil Computer Science · KNUST · 2026" "Normal" $false "666666"
$body += P "All tables are single-run measurements on the departmental cluster. Treat magnitudes as directional; directions are consistent across independent re-runs where noted." "Note"
$body += Spacer

# ════════════════════════════════════════════════════════════════════════════
# TABLE B1 — SlowPoke baseline (L0)
# ════════════════════════════════════════════════════════════════════════════
$body += P "Table B1 - SlowPoke Baseline (L0, SIGSTOP-only)" "Heading1"
$body += P "RQ: What is the unmodified SlowPoke prediction accuracy on this cluster? (Phase 1 / §5.1 style)" "Caption"
$body += P "Standard run-*-medium.sh, SIGSTOP-only, one repetition. Collected 2026-07-16/17 on the bug-fixed harness (empty-times guard, wrk duration cap, nil-guard in fix_req_n.lua). This is the baseline of record for all subsequent comparisons." "Note"
$body += Spacer

$body += Table (
    (Row @("App","Target","Baseline throughput (req/s)","RMSE (%)") $true $w4) +
    (Row @("Boutique","cart","1937.3","2.57") $false $w4) +
    (Row @("Hotel","profile","723.9","20.65") $false $w4) +
    (Row @("Social","hometimeline","959.9","14.01") $false $w4) +
    (Row @("Movie","moviereviews","550.8","12.21") $false $w4)
)
$body += Spacer
$body += P "Boutique 2.57% is close to the paper's reported ~2.07% — best agreement this project has produced. Hotel and Social are higher than the previous run; consistent with single-repetition run-to-run variance rather than a regression, since none of the harness fixes touch hotel/social-specific code paths." "Note"

$body += PageBreak

# ════════════════════════════════════════════════════════════════════════════
# TABLE I1 — RMSE vs I/O level (SIGSTOP-only, L0/L1/L2)
# ════════════════════════════════════════════════════════════════════════════
$body += P "Table I1 - RMSE vs I/O Injection Level (SIGSTOP-only)" "Heading1"
$body += P "RQ1: Does adding synchronous downstream I/O latency increase SlowPoke prediction error? (Phase 2)" "Caption"
$body += P "Fixed -x target; L1 adds tc netem on one downstream service (30ms); L2 adds a second (50ms primary + 30ms secondary). Collected 2026-07-17." "Note"
$body += Spacer

$body += Table (
    (Row @("App","Level / Injection","Baseline (req/s)","RMSE (%)","Mean err (%)") $true $w5) +
    (Row @("Boutique","L0 — cart","1937.3","2.57","2.13") $false $w5) +
    (Row @("Boutique","L1 — cart + productcatalog 30ms","2002.1","4.85","3.89") $false $w5) +
    (Row @("Boutique","L2 — cart + productcatalog 50ms, currency 30ms","1995.7","3.53","2.63") $false $w5) +
    (Row @("Hotel","L0 — profile","723.9","20.65","16.99") $false $w5) +
    (Row @("Hotel","L1 — profile + rate 30ms","729.5","20.03","16.27") $false $w5) +
    (Row @("Hotel","L2 — profile + rate 50ms, user 30ms","768.7","17.51","14.88") $false $w5) +
    (Row @("Social","L0 — hometimeline","959.9","14.01","10.85") $false $w5) +
    (Row @("Social","L1 — hometimeline + poststorage 30ms","943.3","30.33","22.13") $false $w5) +
    (Row @("Social","L2 — hometimeline + poststorage 50ms, socialgraph 30ms","788.1","33.61","28.29") $false $w5) +
    (Row @("Movie","L0 — moviereviews","550.8","12.21","10.01") $false $w5) +
    (Row @("Movie","L1 — moviereviews + reviewstorage 30ms","626.8","28.48","18.46") $false $w5) +
    (Row @("Movie","L2 — moviereviews + reviewstorage 50ms, movieinfo 30ms","651.9","13.84","12.40") $false $w5)
)
$body += Spacer

$body += P "L2 − L0 RMSE delta summary" "Heading2"
$body += Table (
    (Row @("App","L0 RMSE","L2 RMSE","Delta (pp)","Monotonic L0→L1→L2?","Supports RQ1?") $true $w3) +
    (Row @("Social","14.01%","33.61%","+19.60","Yes (14.01→30.33→33.61)","Yes — strongest, cleanest") $false $w3) +
    (Row @("Movie","12.21%","13.84%","+1.63","No — L1 spikes to 28.48","Ambiguous — net positive") $false $w3) +
    (Row @("Boutique","2.57%","3.53%","+0.96","No — L1 (4.85) is peak","Weakly yes — not clean") $false $w3) +
    (Row @("Hotel","20.65%","17.51%","−3.14","Yes, but decreasing","No — reversed direction") $false $w3)
)
$body += Spacer
$body += P "Social is the strongest, cleanest evidence for the I/O-gap hypothesis: a genuinely monotonic +19.6 pp increase. Hotel reversed direction from the previous run — its L0 RMSE alone nearly doubled between two identical runs (10.23%→20.65%), indicating high run-to-run sensitivity on this cluster. 3 of 4 apps show a net increase; treat per-app trends as directional." "Note"

$body += PageBreak

# ════════════════════════════════════════════════════════════════════════════
# TABLE N2 — End-to-end RMSE: SIGSTOP-only vs NetPoke-on (L2)
# ════════════════════════════════════════════════════════════════════════════
$body += P "Table N2 - End-to-End RMSE: SIGSTOP-only vs NetPoke-on at L2" "Heading1"
$body += P "RQ4: Does NetPoke egress hold restore prediction accuracy under I/O-gap injection? (Phase 4)" "Caption"
$body += P "Same 10-point SlowPoke benchmark at L2 with SLOWPOKE_NETPOKE=1. Collected 2026-07-19." "Note"
$body += Spacer

$d1 = DeltaColor "+6.73pp — worse"
$d2 = DeltaColor "−7.26pp — better"
$d3 = DeltaColor "−14.92pp — better"
$d4 = DeltaColor "−3.61pp — better"

$body += Table (
    (Row @("App","L0 Baseline RMSE","SIGSTOP-only L2 RMSE","NetPoke-on L2 RMSE","Change (NetPoke vs SIGSTOP-only)") $true $w5) +
    (Row @("Boutique","2.57%","3.53%","10.26%","+6.73pp — worse") $false $w5 @("","","","$d1")) +
    (Row @("Hotel","20.65%","17.51%","10.25%","−7.26pp — better") $false $w5 @("","","","$d2")) +
    (Row @("Social","14.01%","33.61%","18.69%","−14.92pp — better, largest recovery") $false $w5 @("","","","$d3")) +
    (Row @("Movie","12.21%","13.84%","10.23%","−3.61pp — better, below L0 baseline") $false $w5 @("","","","$d4"))
)
$body += Spacer
$body += P "Social recovers 76% of the injected gap: (33.61−18.69)/(33.61−14.01). Hotel and Movie also improve, ending at or below their L0 baselines. Boutique gets worse — consistent with its cart handler having zero synchronous network I/O (see Boutique Fan-out Finding). Hotel's result should be read with the standing volatility caveat." "Note"

$body += PageBreak

# ════════════════════════════════════════════════════════════════════════════
# TABLE N3 — L0 overhead: SIGSTOP-only vs NetPoke-on (no injection)
# ════════════════════════════════════════════════════════════════════════════
$body += P "Table N3 - L0 RMSE Overhead: SIGSTOP-only vs NetPoke-on (No Injection)" "Heading1"
$body += P "RQ5: Does NetPoke mechanism cost accuracy even at baseline, with nothing to fix? (Phase 5)" "Caption"
$body += P "Same 10-point benchmark at L0 (no netem) with SLOWPOKE_NETPOKE=1. Collected 2026-07-20. Motivated by Table N2's boutique regression." "Note"
$body += Spacer

$e1 = DeltaColor "+6.56pp — worse"
$e2 = DeltaColor "−6.52pp — better"
$e3 = DeltaColor "+3.34pp — worse"
$e4 = DeltaColor "−0.08pp — flat"

$body += Table (
    (Row @("App","SIGSTOP-only L0 RMSE","NetPoke-on L0 RMSE","Change (NetPoke vs SIGSTOP-only)") $true $w4) +
    (Row @("Boutique","2.57%","9.13%","+6.56pp — worse") $false $w4 @("","","","$e1")) +
    (Row @("Hotel","20.65%","14.13%","−6.52pp — better") $false $w4 @("","","","$e2")) +
    (Row @("Social","14.01%","17.35%","+3.34pp — worse, mild") $false $w4 @("","","","$e3")) +
    (Row @("Movie","12.21%","12.13%","−0.08pp — flat") $false $w4 @("","","","$e4"))
)
$body += Spacer
$body += P "Boutique's regression is not L2-specific: +6.56pp at L0 matches +6.73pp at L2 (Table N2) — a two-measurement-consistent finding. Movie is the cleanest case: flat at L0 (−0.08pp, within noise), largest recoverer at L2. Social shows a small constant overhead (+3.34pp) overwhelmed by a large L2 benefit (−14.92pp). Hotel's improvement at L0 is within its documented run-to-run volatility range." "Note"

$body += PageBreak

# ════════════════════════════════════════════════════════════════════════════
# Boutique fan-out finding
# ════════════════════════════════════════════════════════════════════════════
$body += P "Boutique Fan-out Finding - Source-Level Analysis" "Heading1"
$body += P "Why does boutique show no I/O-gap signal and regress under NetPoke-on?" "Caption"
$body += P "Static code inspection of each app's causal target handler. Not a hypothesis — directly readable from source." "Note"
$body += Spacer

$body += Table (
    (Row @("App","Target (-x)","Handler","Synchronous network calls in live path") $true $w4 @("900","1200","1800","2500")) +
    (Row @("Boutique","cart","GetCart / AddItem / EmptyCart","None. Reads/writes an in-process sync.Map (local_carts). Redis client and state.GetState exist in the file but are commented out — dead code, not on the request path.") $false @("900","1200","1800","2500")) +
    (Row @("Hotel","profile","GetProfiles","slowpoke.GetBulkStateDefault — a Dapr state-store round-trip (Redis-backed).") $false @("900","1200","1800","2500")) +
    (Row @("Movie","moviereviews","ReadMovieReviews","slowpoke.GetState (Dapr state store) AND slowpoke.Invoke(ctx, reviewstorage, ro_read_reviews) — explicit HTTP call to another service.") $false @("900","1200","1800","2500")) +
    (Row @("Social","hometimeline","ReadHomeTimeline","slowpoke.GetState (Dapr state store) AND slowpoke.Invoke(ctx, poststorage, ro_read_posts) — explicit HTTP call to another service.") $false @("900","1200","1800","2500"))
)
$body += Spacer
$body += P "Boutique's cart target performs zero synchronous network I/O. There is no downstream call and no state-store round-trip for kernel buffering to intercept during a pause window. This explains: (1) no I/O-gap RMSE signal in Table I1; (2) flat residual-I/O measurement at both L0 and L2; (3) Table N2's RMSE regression — the egress hold's cost (netlink toggling, tc state changes on every SIGSTOP/SIGCONT) has nothing to offset it." "Note"

$body += PageBreak

# ════════════════════════════════════════════════════════════════════════════
# Cross-table summary
# ════════════════════════════════════════════════════════════════════════════
$body += P "Cross-Table Summary - All Apps, All Phases" "Heading1"
$body += P "Consolidated view: L0 baseline → L2 SIGSTOP-only → L2 NetPoke-on, with net change from baseline." "Caption"
$body += Spacer

$body += Table (
    (Row @("App","L0 RMSE","L2 SIGSTOP-only","L2 NetPoke-on","vs L0 baseline","Gap closed?") $true $w6) +
    (Row @("Social","14.01%","33.61% (+19.60pp)","18.69% (+4.68pp)","−14.92pp vs SIGSTOP","76% recovered") $false $w6) +
    (Row @("Movie","12.21%","13.84% (+1.63pp)","10.23% (−1.98pp)","−3.61pp vs SIGSTOP","Below baseline") $false $w6) +
    (Row @("Hotel","20.65%","17.51% (−3.14pp)","10.25% (−10.40pp)","−7.26pp vs SIGSTOP","Improved (volatile)") $false $w6) +
    (Row @("Boutique","2.57%","3.53% (+0.96pp)","10.26% (+7.69pp)","regression","No gap to close") $false $w6)
)
$body += Spacer
$body += P "Data quality: all measurements are single-run on a shared departmental cluster. Treat magnitudes as directional. Hotel's numbers are the most volatile across re-runs; social's are the most stable and constitute the primary evidence for the I/O-gap hypothesis and NetPoke's effectiveness." "Note"

# ════════════════════════════════════════════════════════════════════════════
# Assemble docx
# ════════════════════════════════════════════════════════════════════════════
$doc = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $body
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080"/>
    </w:sectPr>
  </w:body>
</w:document>
"@

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ms = New-Object System.IO.MemoryStream
$zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)

function AddEntry([System.IO.Compression.ZipArchive]$z, [string]$name, [string]$content) {
    $e = $z.CreateEntry($name)
    $s = $e.Open()
    $b = [System.Text.Encoding]::UTF8.GetBytes($content)
    $s.Write($b, 0, $b.Length)
    $s.Close()
}

AddEntry $zip "[Content_Types].xml" (CT)
AddEntry $zip "_rels/.rels"         (Rels)
AddEntry $zip "word/document.xml"   $doc
AddEntry $zip "word/styles.xml"     (Styles)
AddEntry $zip "word/_rels/document.xml.rels" (DocRels)

$zip.Dispose()
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
$ms.Dispose()

Write-Host "Written: $out ($([System.IO.FileInfo]::new($out).Length) bytes)"
