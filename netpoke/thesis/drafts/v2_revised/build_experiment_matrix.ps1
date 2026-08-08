$outPath = 'G:\projects\netpoke\netpoke\thesis\drafts\v2_revised\Experiment_Matrix.docx'

# UTF8 without BOM — required for valid Open XML
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Part([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8)
}

function Para([string]$text, [string]$style='Normal') {
    $e = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    "<w:p><w:pPr><w:pStyle w:val='$style'/></w:pPr><w:r><w:t xml:space='preserve'>$e</w:t></w:r></w:p>"
}

function Cell([string]$text, [bool]$bold=$false, [string]$bg='') {
    $shd = if ($bg) { "<w:shd w:val='clear' w:color='auto' w:fill='$bg'/>" } else { '' }
    $b   = if ($bold) { '<w:b/>' } else { '' }
    $e   = $text -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    "<w:tc><w:tcPr>$shd<w:tcW w:w='0' w:type='auto'/></w:tcPr><w:p><w:pPr><w:pStyle w:val='TableCell'/></w:pPr><w:r><w:rPr>$b</w:rPr><w:t xml:space='preserve'>$e</w:t></w:r></w:p></w:tc>"
}

function Row([string[]]$cells, [bool]$header=$false) {
    $bg = if ($header) { '4472C4' } else { '' }
    $bold = $header
    $tcs = ($cells | ForEach-Object { Cell $_ $bold $bg }) -join ''
    "<w:tr>$tcs</w:tr>"
}

# ── document body ──────────────────────────────────────────────────────────────
$body = ''

$body += Para 'NetPoke Experiment Matrix' 'Title'
$body += Para 'Evaluation runs: objectives, status, and repetitions' 'Subtitle'
$body += Para ''

$body += Para 'Overview' 'Heading1'
$body += Para 'The NetPoke evaluation consists of five distinct experiment types. Each type answers a specific research question and has been executed exactly once (single run, no repetitions). The table below maps each type to its objective, the scripts that implement it, the tables it populates, and its current status.'
$body += Para ''

# ── main matrix table ──────────────────────────────────────────────────────────
$tbl = '<w:tbl>'
$tbl += '<w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/><w:tblBorders>
  <w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>
  <w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>
  <w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>
  <w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>
  <w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>
  <w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>
</w:tblBorders></w:tblPr>'

$tbl += Row @('Type','Experiment','Script(s)','RQ / Objective','Result table','Status','Reps') $true

$tbl += Row @(
    '1',
    'SIGSTOP-only L0 — baseline reproduction',
    'run-*-medium.sh (4 apps)',
    'Reproduces SlowPoke Fig. 8 on this cluster. Establishes baseline RMSE before any I/O injection.',
    'TABLE_L0_SUMMARY.md',
    'Done (2026-07-16/17)',
    '1 of 1'
)
$tbl += Row @(
    '2',
    'SIGSTOP-only L1 + L2 — I/O-gap stimulus',
    'run_io_gap_sigstop_L1.sh / run_io_gap_sigstop_L2.sh',
    'RQ1: Does adding synchronous path I/O increase prediction error? Core "there is a problem" evidence across 4 apps x 2 injection levels.',
    'TABLE_IO_GAP_MATRIX.md',
    'Done (2026-07-17)',
    '1 of 1'
)
$tbl += Row @(
    '3',
    'NetPoke-on L2 — accuracy recovery at heavy injection',
    'run_io_gap_netpoke_L2.sh',
    'RQ4: Does NetPoke restore prediction accuracy under I/O stress? Direct paired comparison against Type 2 L2 numbers.',
    'TABLE_N2_RMSE_COMPARISON.md',
    'Done (2026-07-19)',
    '1 of 1'
)
$tbl += Row @(
    '4',
    'NetPoke-on L1 — accuracy recovery at moderate injection',
    'run_io_gap_netpoke_L1.sh',
    'RQ4 at L1 intensity. Completes the 2x2 matrix: (SIGSTOP vs NetPoke) x (L1 vs L2).',
    'TABLE_N2 (L1 rows)',
    'RUNNING (started 2026-08-08 12:05 UTC)',
    '0 of 1'
)
$tbl += Row @(
    '5',
    'NetPoke-on L0 — overhead check (no injection)',
    'run_netpoke_l0_overhead.sh',
    'Does NetPoke cost accuracy even when there is nothing to fix? Motivated by boutique regression in Type 3.',
    'TABLE_N3_L0_OVERHEAD.md',
    'Done (2026-07-20)',
    '1 of 1'
)

$tbl += '</w:tbl>'
$body += $tbl
$body += Para ''

# ── per-type detail ────────────────────────────────────────────────────────────
$body += Para 'Per-type notes' 'Heading1'

$body += Para 'Type 1 — SIGSTOP-only L0 (baseline)' 'Heading2'
$body += Para 'Parameters: 4 apps, 10 experiment points each, 1 repetition, num_req=100000, 8 threads. Each app takes ~30-45 min. Boutique RMSE 2.57% closely matches the paper''s 2.07% headline — best agreement this project has produced. Hotel RMSE (20.65%) is notably higher than the previous run (10.23%); attributed to single-repetition cluster variance rather than a regression.'

$body += Para 'Type 2 — SIGSTOP-only L1 + L2 (I/O-gap stimulus)' 'Heading2'
$body += Para 'Parameters: num_req=800, 8 threads, 10 experiment points, netem injection on downstream path services. L1: one service at 30 ms. L2: primary at 50 ms + secondary at 30 ms. Social is the strongest supporting result (+19.6 pp L0->L2, monotonic). Hotel reversed direction vs the previous run — flagged as open volatility question. Boutique shows only +0.96 pp, explained by the fan-out finding (cart uses in-process sync.Map, no real network I/O).'

$body += Para 'Type 3 — NetPoke-on L2 (accuracy recovery)' 'Heading2'
$body += Para 'Social recovers 76% of the L2 gap (33.61% -> 18.69%). Hotel and movie both improve, ending at or below their L0 baselines. Boutique gets worse (3.53% -> 10.26%) — consistent with Type 5 finding that the overhead has nothing to offset when the target has no real network I/O.'

$body += Para 'Type 4 — NetPoke-on L1 (accuracy recovery, in progress)' 'Heading2'
$body += Para 'Currently running. Boutique started 2026-08-08 12:05 UTC, first measurement confirmed at 13.2 req/s (workloads 1/21). Hotel, social, and movie follow automatically. Estimated completion: 2026-08-08 ~20:45 UTC. Logs landing in ~/slowpoke/evaluation/results/ (root, not rep1) — move to rep1/ after completion.'

$body += Para 'Type 5 — NetPoke-on L0 (overhead check)' 'Heading2'
$body += Para 'Boutique regression is not L2-specific: +6.56 pp at L0, same magnitude as Type 3''s +6.73 pp at L2. Movie is the cleanest case: flat at L0 (-0.08 pp, within noise), largest recovery at L2 (-3.61 pp in Type 3). Social shows small L0 cost (+3.34 pp) alongside large L2 benefit (-14.92 pp). Hotel improvement at L0 (-6.52 pp) should be read with the standing volatility caveat.'

$body += Para ''
$body += Para 'Repetition status' 'Heading1'
$body += Para 'No experiment type has been repeated. Every run is a unique measurement serving a distinct purpose. All tables note "single-run measurements, treat as directional." Adding repetitions for statistical confidence is a thesis scope decision not yet made.'

# ── assemble document XML ──────────────────────────────────────────────────────
$docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>' + $body + '
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
</w:body></w:document>'

$stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:jc w:val="center"/><w:spacing w:before="480" w:after="240"/></w:pPr>
    <w:rPr><w:b/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="52"/><w:szCs w:val="52"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle">
    <w:name w:val="Subtitle"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="480"/></w:pPr>
    <w:rPr><w:i/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>
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
  <w:style w:type="paragraph" w:styleId="TableCell">
    <w:name w:val="TableCell"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:after="80" w:line="240" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
  </w:style>
  <w:style w:type="table" w:styleId="TableGrid">
    <w:name w:val="Table Grid"/>
    <w:tblPr><w:tblBorders>
      <w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>
      <w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>
      <w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>
      <w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>
    </w:tblBorders></w:tblPr>
  </w:style>
</w:styles>'

# ── write zip ──────────────────────────────────────────────────────────────────
$tmpDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmpDir | Out-Null
New-Item -ItemType Directory -Path "$tmpDir\word" | Out-Null
New-Item -ItemType Directory -Path "$tmpDir\_rels" | Out-Null
New-Item -ItemType Directory -Path "$tmpDir\word\_rels" | Out-Null

Write-Part "$tmpDir\[Content_Types].xml" '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>'

Write-Part "$tmpDir\_rels\.rels" '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'

Write-Part "$tmpDir\word\_rels\document.xml.rels" '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'

Write-Part "$tmpDir\word\styles.xml" $stylesXml
Write-Part "$tmpDir\word\document.xml" $docXml

if (Test-Path $outPath) { Remove-Item $outPath }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $outPath)
Remove-Item $tmpDir -Recurse -Force
Write-Host "Written: $outPath"
