# fix-seo-upgrade.ps1
# Fills MISSING SEO/AEO/GEO tags on the upgraded sections (blog/, books/, recommends/)
# and any page lacking canonical/og/twitter/robots/jsonld. Safe + idempotent:
#   - only ADDS tags that are absent (never overwrites existing ones)
#   - never touches discovery/, the root index.html, or new-site/
#   - derives canonical from the file path and OG/Twitter from the existing title/description
#
# Usage:
#   pwsh -File fix-seo-upgrade.ps1          # apply
#   pwsh -File fix-seo-upgrade.ps1 -WhatIf  # dry run

[CmdletBinding()]
param([switch]$WhatIf)

$base    = 'C:\Users\richa\OneDrive\Documents\dev\discovery-booktrawler-com'
$siteUrl = 'https://tomrhodes.me/'
$siteName = 'tom/rhodes'

function Decode-Entities($s) {
    if ($null -eq $s) { return '' }
    $s = $s -replace '&amp;', [char]0x0026 -replace '&lt;', [char]0x003C -replace '&gt;', [char]0x003E `
        -replace '&quot;', [char]0x0022 -replace '&#39;', [char]0x0027 -replace '&apos;', [char]0x0027 `
        -replace '&rsquo;', [char]0x0027 -replace '&lsquo;', [char]0x0027 `
        -replace '&ldquo;', [char]0x0022 -replace '&rdquo;', [char]0x0022 -replace '&mdash;', [char]0x2014 `
        -replace '&ndash;', [char]0x2013 -replace '&hellip;', [char]0x2026 -replace '&nbsp;', [char]0x0020
    $s = [regex]::Replace($s, '&#(\d+);', { param($m) [char][int]$m.Groups[1].Value })
    $s = [regex]::Replace($s, '&#x([0-9a-fA-F]+);', { param($m) [char][int]('0x' + $m.Groups[1].Value) })
    return $s
}

# Canonical URL from the page's repo-relative path (index.html -> directory).
function Canonical-Url($rel) {
    if ($rel -eq 'index.html') { return $siteUrl }
    if ($rel.EndsWith('/index.html')) {
        return $siteUrl + $rel.Substring(0, $rel.Length - 'index.html'.Length)
    }
    return $siteUrl + $rel
}

# Escape a value for safe inclusion inside an HTML attribute / JSON string.
function Attr($s) {
    return (Decode-Entities $s).Trim() -replace '"', '&quot;'
}
function JsonStr($s) {
    $t = (Decode-Entities $s).Trim() -replace '\\', '\\' -replace '"', '\"' -replace "`r", '' -replace "`n", ' '
    return '"' + $t + '"'
}

$files = Get-ChildItem -LiteralPath $base -Recurse -Filter *.html |
    Where-Object {
        $p = $_.FullName
        $p -notmatch '\\\.git\\' -and $p -notmatch '\\new-site\\' -and $p -notmatch '\\\.kilo\\' -and
        $p -notmatch '\\discovery\\' -and $p -ne (Join-Path $base 'index.html')
    } |
    Select-Object -ExpandProperty FullName

$changed = 0
$addedOg = 0; $addedTw = 0; $addedRobots = 0; $addedJson = 0; $addedCanon = 0

foreach ($f in $files) {
    $rel  = $f.Replace("$base\", "").Replace('\', '/')
    $html = Get-Content -Raw -LiteralPath $f
    $orig = $html

    $title = if ($html -match '<title>(.*?)</title>') { $Matches[1].Trim() } else { '' }
    $desc  = if ($html -match '<meta\s+name="description"\s+content="(.*?)"') { $Matches[1].Trim() } else { '' }
    $canon = Canonical-Url $rel

    $hasCanonical = $html -match 'rel="canonical"'
    $hasOg        = $html -match 'property="og:'
    $hasTwitter   = $html -match 'name="twitter:'
    $hasRobots    = $html -match 'name="robots"'
    $hasJson      = $html -match 'application/ld\+json'

    $inject = ''

    if (-not $hasCanonical) {
        $inject += '<link rel="canonical" href="' + $canon + '">' + "`n"
        $addedCanon++
    }
    if (-not $hasRobots) {
        $inject += '<meta name="robots" content="index, follow">' + "`n"
        $addedRobots++
    }
    if (-not $hasOg) {
        $ogTitle = if ($title) { Attr $title } else { $siteName }
        $ogDesc  = if ($desc)  { Attr $desc }  else { $siteName }
        $inject += '<meta property="og:type" content="website">' + "`n" +
                   '<meta property="og:site_name" content="' + $siteName + '">' + "`n" +
                   '<meta property="og:title" content="' + $ogTitle + '">' + "`n" +
                   '<meta property="og:description" content="' + $ogDesc + '">' + "`n" +
                   '<meta property="og:url" content="' + $canon + '">' + "`n" +
                   '<meta property="og:locale" content="en_US">' + "`n"
        $addedOg++
    }
    if (-not $hasTwitter) {
        $twTitle = if ($title) { Attr $title } else { $siteName }
        $twDesc  = if ($desc)  { Attr $desc }  else { $siteName }
        $inject += '<meta name="twitter:card" content="summary_large_image">' + "`n" +
                   '<meta name="twitter:title" content="' + $twTitle + '">' + "`n" +
                   '<meta name="twitter:description" content="' + $twDesc + '">' + "`n" +
                   '<meta name="twitter:url" content="' + $canon + '">' + "`n"
        $addedTw++
    }
    if (-not $hasJson) {
        $json = '<script type="application/ld+json">' + "`n" + '{' + "`n" +
                '  "@context": "https://schema.org",' + "`n" +
                '  "@type": "WebPage",' + "`n" +
                '  "name": ' + (JsonStr $title) + ',' + "`n" +
                '  "description": ' + (JsonStr $desc) + ',' + "`n" +
                '  "url": ' + (JsonStr $canon) + ',' + "`n" +
                '  "isPartOf": { "@type": "WebSite", "name": ' + (JsonStr $siteName) + ', "url": ' + (JsonStr $siteUrl) + ' }' + "`n" +
                '}' + "`n" + '</script>' + "`n"
        $inject += $json
        $addedJson++
    }

    if ($inject -ne '') {
        # Insert before </head> (after any existing tags).
        $html = $html -replace '</head>', ($inject + '</head>')
        if (-not $WhatIf) { Set-Content -LiteralPath $f -Encoding utf8 -Value $html }
        $changed++
        Write-Host "UPDATED $rel"
    }
}

Write-Host "$(if ($WhatIf) { 'DRY-RUN: ' } else { '' })Updated $changed page(s). Added -> canonical:$addedCanon robots:$addedRobots og:$addedOg twitter:$addedTw jsonld:$addedJson"
