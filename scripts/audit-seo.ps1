# audit-seo.ps1
# Scans every HTML page (repo root + discovery/) and reports SEO/AEO/GEO gaps.
# Output: audit-report.csv (per page) and audit-summary.md (aggregate).

$base = 'C:\Users\richa\OneDrive\Documents\dev\discovery-tom/rhodes-com'
$outCsv = Join-Path $base 'audit-report.csv'
$outMd = Join-Path $base 'audit-summary.md'

$files = Get-ChildItem -LiteralPath $base -Recurse -Filter *.html |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    Select-Object -ExpandProperty FullName

$rows = @()
$total = 0
$cCanonical = 0; $cOg = 0; $cTwitter = 0; $cJson = 0; $cRobots = 0; $cTitle = 0; $cDesc = 0; $cH1 = 0

foreach ($f in $files) {
    $rel = $f.Replace("$base\", "").Replace('\', '/')
    $html = Get-Content -Raw -LiteralPath $f

    $title = if ($html -match '<title>(.*?)</title>') { $Matches[1].Trim() } else { '' }
    $desc = if ($html -match '<meta\s+name="description"\s+content="(.*?)"') { $Matches[1].Trim() } else { '' }
    $hasCanonical = $html -match 'rel="canonical"'
    $hasOg = $html -match 'property="og:'
    $hasTwitter = $html -match 'name="twitter:'
    $hasJson = $html -match 'application/ld\+json'
    $hasRobots = $html -match 'name="robots"'
    $hasH1 = $html -match '<h1[ >]'
    $internal = ([regex]::Matches($html, '<a\s+href="(?!https?://|mailto:|tel:|#)([^"]+)"')).Count

    $issues = @()
    if (-not $hasCanonical) { $issues += 'no-canonical' }
    if (-not $hasOg) { $issues += 'no-og' }
    if (-not $hasTwitter) { $issues += 'no-twitter' }
    if (-not $hasJson) { $issues += 'no-jsonld' }
    if (-not $hasRobots) { $issues += 'no-robots' }
    if ($title.Length -eq 0) { $issues += 'no-title' } elseif ($title.Length -lt 30 -or $title.Length -gt 65) { $issues += 'title-len' }
    if ($desc.Length -eq 0) { $issues += 'no-desc' } elseif ($desc.Length -lt 70 -or $desc.Length -gt 160) { $issues += 'desc-len' }
    if (-not $hasH1) { $issues += 'no-h1' }
    if ($internal -lt 3) { $issues += 'few-internal-links' }

    $total++
    if ($hasCanonical) { $cCanonical++ }
    if ($hasOg) { $cOg++ }
    if ($hasTwitter) { $cTwitter++ }
    if ($hasJson) { $cJson++ }
    if ($hasRobots) { $cRobots++ }
    if ($title.Length -gt 0) { $cTitle++ }
    if ($desc.Length -gt 0) { $cDesc++ }
    if ($hasH1) { $cH1++ }

    $rows += [PSCustomObject]@{
        path = $rel
        title_len = $title.Length
        desc_len = $desc.Length
        has_canonical = $hasCanonical
        has_og = $hasOg
        has_twitter = $hasTwitter
        has_jsonld = $hasJson
        has_robots = $hasRobots
        has_h1 = $hasH1
        internal_links = $internal
        issues = ($issues -join '; ')
    }
}

$rows | Export-Csv -NoTypeInformation -Path $outCsv

$pct = { param($n) if ($total -eq 0) { 0 } else { [math]::Round(100 * $n / $total, 1) } }

$md = @"
# SEO / AEO / GEO Audit Summary
Generated: $(Get-Date -Format 'u')
Pages scanned: $total

| Element | Present | Coverage |
|---|---|---|
| Canonical | $cCanonical | $(&$pct $cCanonical)% |
| Open Graph | $cOg | $(&$pct $cOg)% |
| Twitter Card | $cTwitter | $(&$pct $cTwitter)% |
| JSON-LD | $cJson | $(&$pct $cJson)% |
| Meta robots | $cRobots | $(&$pct $cRobots)% |
| Title tag | $cTitle | $(&$pct $cTitle)% |
| Meta description | $cDesc | $(&$pct $cDesc)% |
| H1 | $cH1 | $(&$pct $cH1)% |

Per-page detail in audit-report.csv
"@
Set-Content -Path $outMd -Value $md

Write-Host "Scanned $total pages. Reports: $outCsv, $outMd"
Write-Host "Canonical: $cCanonical/$total  OG: $cOg  Twitter: $cTwitter  JSON-LD: $cJson  Robots: $cRobots"
