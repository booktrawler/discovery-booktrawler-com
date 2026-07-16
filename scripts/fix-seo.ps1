# fix-seo.ps1
# Injects SEO / AEO / GEO tags into every HTML page (repo root + discovery/).
#   - canonical, meta robots
#   - Open Graph + Twitter cards
#   - JSON-LD @graph: Organization, WebSite, BreadcrumbList, ItemList/Book, FAQPage
#
# Idempotent / re-runnable: any previously injected block (marked with
# <!-- seo-injected -->) is stripped and rebuilt, so improvements apply on re-run.
#
# Usage:
#   pwsh -File fix-seo.ps1            # apply for real
#   pwsh -File fix-seo.ps1 -WhatIf    # dry run, write nothing

[CmdletBinding()]
param([switch]$WhatIf)

$base    = 'C:\Users\richa\OneDrive\Documents\dev\discovery-tom/rhodes-com'
$siteUrl = 'https://tomrhodes.me/'
$flag    = '<!-- seo-injected -->'

function Decode-Entities($s) {
    if ($null -eq $s) { return '' }
    $s = $s -replace '&amp;', [char]0x0026 -replace '&lt;', [char]0x003C -replace '&gt;', [char]0x003E `
        -replace '&quot;', [char]0x0022 -replace '&#39;', [char]0x0027 -replace '&apos;', [char]0x0027 `
        -replace '&#x27;', [char]0x0027 -replace '&rsquo;', [char]0x0027 -replace '&lsquo;', [char]0x0027 `
        -replace '&ldquo;', [char]0x0022 -replace '&rdquo;', [char]0x0022 -replace '&mdash;', [char]0x2014 `
        -replace '&ndash;', [char]0x2013 -replace '&hellip;', [char]0x2026 -replace '&nbsp;', [char]0x0020
    $s = [regex]::Replace($s, '&#(\d+);', { param($m) [char][int]$m.Groups[1].Value })
    $s = [regex]::Replace($s, '&#x([0-9a-fA-F]+);', { param($m) [char][int]('0x' + $m.Groups[1].Value) })
    return $s
}
function J($s) {
    $s = Decode-Entities $s
    $s = $s -replace '\\', '\\' -replace '"', '\"' -replace "`r", '' -replace "`n", ' '
    return '"' + $s.Trim() + '"'
}
function StripTags($s) {
    return [regex]::Replace($s, '<[^>]+>', '').Trim()
}
function Friendly($seg) {
    switch ($seg) {
        'ya'             { return 'Young Adult' }
        'nonfiction'     { return 'Nonfiction' }
        'fiction'        { return 'Fiction' }
        'kids'           { return 'Kids' }
        'journeys'       { return 'Reading Journeys' }
        'if-you-loved'   { return 'If You Loved' }
        'where-to-start' { return 'Where to Start' }
        default {
            $seg = $seg -replace '-', ' '
            $words = $seg.Split(' ') | ForEach-Object { if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } else { $_ } }
            return ($words -join ' ')
        }
    }
}

function Canonical-Url($rel) {
    if ($rel -eq 'index.html') { return $siteUrl + 'discovery/' }
    if ($rel.EndsWith('/index.html')) {
        return $siteUrl + $rel.Substring(0, $rel.Length - 'index.html'.Length)
    }
    return $siteUrl + $rel
}

# Parse real FAQ Q&As from an existing <section class="faq"> when present.
function Get-FaqJson($html) {
    $m = [regex]::Match($html, '(?s)<section class="faq">.*?</section>')
    if (-not $m.Success) { return '' }
    $faqHtml = $m.Value
    $dt = [regex]::Matches($faqHtml, '(?s)<dt>(.*?)</dt>')
    $dd = [regex]::Matches($faqHtml, '(?s)<dd>(.*?)</dd>')
    $n = [Math]::Min($dt.Count, $dd.Count)
    if ($n -eq 0) { return '' }
    $qas = @()
    for ($i = 0; $i -lt $n; $i++) {
        $q = StripTags $dt[$i].Groups[1].Value
        $a = StripTags $dd[$i].Groups[1].Value
        if (-not $q -or -not $a) { continue }
        $qas += '{ "@type": "Question", "name": ' + (J $q) + ', "acceptedAnswer": { "@type": "Answer", "text": ' + (J $a) + ' } }'
    }
    if ($qas.Count -eq 0) { return '' }
    return ',{ "@type": "FAQPage", "@id": "' + $canon + '#faq", "mainEntity": [ ' + ($qas -join ', ') + ' ] }'
}

$files = Get-ChildItem -LiteralPath $base -Recurse -Filter *.html |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    Select-Object -ExpandProperty FullName

$changed  = 0
$faqCount = 0

foreach ($f in $files) {
    $rel  = $f.Replace("$base\", "").Replace('\', '/')
    $html = Get-Content -Raw -LiteralPath $f

    # Strip any previously injected block so improvements always apply.
    $html = [regex]::Replace($html, '(?s)<!-- seo-injected -->.*?(?=</head>)', '')

    $title = if ($html -match '<title>(.*?)</title>') { $Matches[1].Trim() } else { 'tom/rhodes Discovery' }
    $desc  = if ($html -match '<meta\s+name="description"\s+content="(.*?)"') { $Matches[1].Trim() } else { '' }

    # Root gag page: canonical to real home + redirect only.
    if ($rel -eq 'index.html') {
        $block = "$flag`n" +
            '<link rel="canonical" href="' + $siteUrl + 'discovery/">' + "`n" +
            '<meta http-equiv="refresh" content="0;url=/discovery/">' + "`n"
        $new = $html -replace '</head>', ($block + '</head>')
        if (-not $WhatIf) { Set-Content -LiteralPath $f -Encoding utf8 -Value $new }
        $changed++
        continue
    }

    $canon = Canonical-Url $rel

    # ---- BreadcrumbList ----
    $segs = $rel.Split('/')
    $crumbs = @()
    $crumbs += '{ "@type": "ListItem", "position": 1, "name": "Home", "item": "' + $siteUrl + 'discovery/" }'
    $acc = 'discovery'
    for ($i = 1; $i -lt ($segs.Count - 1); $i++) {
        $acc += '/' + $segs[$i]
        $pos = $i + 1
        $crumbs += '{ "@type": "ListItem", "position": ' + $pos + ', "name": ' + (J (Friendly $segs[$i])) + ', "item": "' + $siteUrl + $acc + '/" }'
    }
    $lastPos = $segs.Count
    if (-not $rel.EndsWith('/index.html')) {
        $pageName = if ($title) { $title } else { (Friendly $segs[-1].Replace('.html','')) }
        $crumbs += '{ "@type": "ListItem", "position": ' + $lastPos + ', "name": ' + (J $pageName) + ', "item": "' + $canon + '" }'
    }

    # ---- ItemList / Book (multi-line aware) ----
    $bookJson = ''
    $bookBlocks = [regex]::Matches($html, '(?s)<li class="book">.*?</li>')
    if ($bookBlocks.Count -gt 0) {
        $items = @()
        $pos = 0
        foreach ($b in $bookBlocks) {
            $pos++
            $h3  = if ($b.Value -match '(?s)<h3>(.*?)</h3>') { $Matches[1] } else { '' }
            $h3  = [regex]::Replace($h3, '(?s)<span[^>]*>.*?</span>', '')
            $name = if ($h3) { StripTags $h3 } else { '' }
            $auth = if ($b.Value -match '(?s)<p class="byline">(.*?)</p>') { StripTags $Matches[1] } else { '' }
            if (-not $name) { continue }
            $obj = '{ "@type": "ListItem", "position": ' + $pos + ', "item": { "@type": "Book", "name": ' + (J $name)
            if ($auth) { $obj += ', "author": { "@type": "Person", "name": ' + (J $auth) + ' }' }
            $obj += ' } }'
            $items += $obj
        }
        if ($items.Count -gt 0) {
            $bookJson = ',{ "@type": "ItemList", "@id": "' + $canon + '#booklist", "itemListElement": [ ' + ($items -join ', ') + ' ] }'
        }
    }

    # ---- FAQPage from real markup (falls back to none rather than inventing facts) ----
    $faqJson = Get-FaqJson $html
    if ($faqJson) { $faqCount++ }

    $graph =
        '{ "@context": "https://schema.org", "@graph": [ ' +
        '{ "@type": "Organization", "@id": "' + $siteUrl + '#organization", "name": "tom/rhodes Discovery", "url": "' + $siteUrl + '", ' +
            '"description": "Curated, opinionated reading guides across fiction, nonfiction, kids, young adult, and themed reading journeys." }, ' +
        '{ "@type": "WebSite", "@id": "' + $siteUrl + '#website", "name": "tom/rhodes Discovery", "url": "' + $siteUrl + '", "publisher": { "@id": "' + $siteUrl + '#organization" } }, ' +
        '{ "@type": "BreadcrumbList", "@id": "' + $canon + '#breadcrumb", "itemListElement": [ ' + ($crumbs -join ', ') + ' ] }' +
        $bookJson + $faqJson +
        ' ] }'

    $block = "$flag`n" +
        '<link rel="canonical" href="' + $canon + '">' + "`n" +
        '<meta name="robots" content="index,follow">' + "`n" +
        '<meta property="og:type" content="website">' + "`n" +
        '<meta property="og:site_name" content="tom/rhodes Discovery">' + "`n" +
        '<meta property="og:title" content="' + $title + '">' + "`n" +
        '<meta property="og:description" content="' + $desc + '">' + "`n" +
        '<meta property="og:url" content="' + $canon + '">' + "`n" +
        '<meta property="og:locale" content="en_US">' + "`n" +
        '<meta name="twitter:card" content="summary_large_image">' + "`n" +
        '<meta name="twitter:title" content="' + $title + '">' + "`n" +
        '<meta name="twitter:description" content="' + $desc + '">' + "`n" +
        '<meta name="twitter:url" content="' + $canon + '">' + "`n" +
        '<script type="application/ld+json">' + "`n" + $graph + "`n" + '</script>' + "`n"

    $new = $html -replace '</head>', ($block + '</head>')
    if (-not $WhatIf) { Set-Content -LiteralPath $f -Encoding utf8 -Value $new }
    $changed++
}

Write-Host "$(if ($WhatIf) { 'DRY-RUN: ' } else { '' })Updated $changed page(s). FAQPage (from real markup) on $faqCount page(s)."
