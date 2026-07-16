# build-templates.ps1
# Reassembles every site page from shared partials (templates/head.html,
# templates/header.html, templates/footer.html) + a single consolidated
# /style.css, extracting each page's per-page <head> meta and <body> content.
#
# Source of truth = the live tree (blog/, books/, recommends/, discovery/).
# Output          = new-site/  (the work-in-progress mirror) by default.
#                   Use -Live to also write the live tree in place.
#
# Idempotent: every run re-reads the live source and rewrites output, so it is
# safe to run repeatedly. Pages that fail boundary detection are reported and
# skipped (never partially written).
#
# Usage:
#   pwsh -File build-templates.ps1            # dry run (reports counts)
#   pwsh -File build-templates.ps1 -WhatIf    # same, explicit
#   pwsh -File build-templates.ps1 -Apply     # write into new-site/
#   pwsh -File build-templates.ps1 -Apply -Live  # also rewrite the live tree

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Apply,
    [switch]$Live
)

$ErrorActionPreference = 'Stop'

$base   = 'C:\Users\richa\OneDrive\Documents\dev\discovery-booktrawler-com'

$tplHead   = Join-Path $base 'templates/head.html'
$tplHeader = Join-Path $base 'templates/header.html'
$tplFooter = Join-Path $base 'templates/footer.html'

if (-not (Test-Path $tplHead) -or -not (Test-Path $tplHeader) -or -not (Test-Path $tplFooter)) {
    throw "Missing template partial(s) in $base/templates/"
}

$headTpl   = Get-Content -Raw -LiteralPath $tplHead
$headerTpl = Get-Content -Raw -LiteralPath $tplHeader
$footerTpl = Get-Content -Raw -LiteralPath $tplFooter

# Sections whose pages carry a secondary (in-section) nav we must preserve.
$sectionNavSections = @('discovery')

function Resolve-RootPrefix($relPath) {
    # relPath is like "blog/index.html" or "discovery/fiction/x.html"
    $depth = ($relPath -split '/').Count - 1   # number of slashes = folders deep
    if ($depth -le 0) { return './' }
    $prefix = ''
    for ($i = 0; $i -lt $depth; $i++) { $prefix += '../' }
    return $prefix
}

function Extract-SectionNav($html) {
    # Pull the secondary category nav out of a discovery <header class="site-header">.
    $m = [regex]::Match($html, '(?s)<header class="site-header">.*?<nav>(.*?)</nav>')
    if (-not $m.Success) { return $null }
    $inner = $m.Groups[1].Value
    $links = [regex]::Matches($inner, '(?s)<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>') |
        ForEach-Object { $href = $_.Groups[1].Value; $text = $_.Groups[2].Value.Trim(); "<a href=`"$href`">$text</a>" }
    if ($links.Count -eq 0) { return $null }
    return "<div class=""section-nav"">$($links -join '')</div>"
}

function Extract-HeadMeta($html) {
    $m = [regex]::Match($html, '(?s)<head>(.*?)</head>')
    if (-not $m.Success) { return $null }
    $inner = $m.Groups[1].Value
    # Page-specific meta tags (kept in head).
    $keep = [regex]::Matches($inner, '(?s)(<title>.*?</title>|<meta name="description"[^>]*>|<link rel="canonical"[^>]*>|<meta name="robots"[^>]*>|<meta property="og:[^"]*"[^>]*>|<meta name="twitter:[^"]*"[^>]*>|<script type="application/ld\+json">.*?</script>)')
    $meta = $keep | ForEach-Object { $_.Value.Trim() }
    # Page-specific inline <style> blocks (component styles unique to this page).
    $styles = [regex]::Matches($inner, '(?s)<style>.*?</style>') | ForEach-Object { $_.Value.Trim() }
    $extra = $styles -join "`n"
    if ($meta.Count -eq 0) { return $null }
    return [PSCustomObject]@{ Meta = ($meta -join "`n"); Style = $extra }
}

function Extract-BodyContent($html) {
    $m = [regex]::Match($html, '(?s)<body>(.*?)</body>')
    if (-not $m.Success) { return $null }
    $body = $m.Groups[1].Value

    # Remove the ORIGINAL chrome header. Blog uses a top-level <nav>; discovery uses
    # <header class="site-header">; recommends (via prior add-header-links.ps1) uses an
    # inline-styled <header class="sg-header">. Keep only <header class="page-header"> (content).
    $body = [regex]::Replace($body, '(?s)<nav>.*?</nav>', '')
    $body = [regex]::Replace($body, '(?s)<header class="site-header">.*?</header>', '')
    # Remove any other chrome <header> that is NOT the content page-header band,
    # regardless of leading whitespace or inline style attributes.
    $body = [regex]::Replace($body, '(?s)<header(?![^>]*class="page-header")[^>]*>.*?</header>', '')

    # Remove the ORIGINAL chrome footer. Discovery uses <footer class="site-footer">;
    # blog/books/recommends use a bare <footer>. Keep <footer class="eeat"> (discovery
    # CONTENT, sits inside <main>) and <footer class="site-footer"> (added by template).
    $body = [regex]::Replace($body, '(?s)<footer(?![^>]*class="(eeat|site-footer)")[^>]*>.*?</footer>', '')

    return $body.Trim()
}

# ---- gather source pages ----
$sourceRoots = @('blog', 'books', 'recommends', 'discovery')
$files = @()
foreach ($sec in $sourceRoots) {
    $dir = Join-Path $base $sec
    if (Test-Path $dir) {
        $files += Get-ChildItem -LiteralPath $dir -Recurse -Filter *.html |
            Select-Object -ExpandProperty FullName
    }
}
# Also the site root index.html (it defines its own hero; templatize its chrome too).
$rootIndex = Join-Path $base 'index.html'
if (Test-Path $rootIndex) { $files += $rootIndex }

$ok = 0; $fail = 0; $written = 0
$failures = @()

foreach ($f in $files) {
    $rel  = $f.Replace("$base\", "").Replace('\', '/')
    $html = Get-Content -Raw -LiteralPath $f

    $rootPrefix = Resolve-RootPrefix $rel
    $logoSrc    = $rootPrefix + 'images/logo.png'
    $styleHref  = '/style.css'

    $headMeta = Extract-HeadMeta $html
    $content  = Extract-BodyContent $html

    if ($null -eq $headMeta -or [string]::IsNullOrWhiteSpace($headMeta.Meta) -or [string]::IsNullOrWhiteSpace($content)) {
        $fail++; $failures += $rel; continue
    }

    $sectionNav = ''
    $top = ($rel -split '/')[0]
    if ($sectionNavSections -contains $top) {
        $sn = Extract-SectionNav $html
        if ($sn) { $sectionNav = $sn }
    }

    $head = $headTpl.Replace('__ROOT__', $rootPrefix).Replace('__STYLE_HREF__', $styleHref)
    $head = [regex]::Replace($head, '<!--__PAGE_META__-->', $headMeta.Meta)
    $head = [regex]::Replace($head, '<!--__PAGE_STYLE__-->', $headMeta.Style)

    $header = $headerTpl.Replace('__ROOT__', $rootPrefix).Replace('__LOGO_SRC__', $logoSrc)
    $header = [regex]::Replace($header, '<!--__SECTION_NAV__-->', $sectionNav)

    $footer = $footerTpl.Replace('__ROOT__', $rootPrefix)

    $out = "<!DOCTYPE html>`n<html lang=`"en`">`n" + $head + "`n<body>`n" + $header + "`n" + $content + "`n" + $footer + "`n</body>`n</html>`n"

    $ok++

    $targets = @()
    if ($Apply) {
        $targets += Join-Path $base ('new-site/' + $rel)
        if ($Live) { $targets += $f }
    }

    if ($targets.Count -eq 0) { continue }

    foreach ($t in $targets) {
        $tdir = Split-Path $t
        if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Force -Path $tdir | Out-Null }
        if (-not $WhatIf) {
            Set-Content -LiteralPath $t -Encoding utf8 -Value $out
            $written++
        }
    }
}

Write-Host "$(if($WhatIf){'[WHATIF] '}elseif(-not $Apply){'[DRY-RUN] '}else{''})Processed $ok page(s); extracted meta+content OK. Skipped $fail (boundary failures)."
if ($Apply -and -not $WhatIf) { Write-Host "Wrote $written file(s) (apply=$(if($Live){'new-site + live'}else{'new-site only'}))." }
if ($failures.Count -gt 0) { Write-Host "FAILURES:"; $failures | ForEach-Object { Write-Host "  - $_" } }
