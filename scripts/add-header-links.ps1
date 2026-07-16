# add-header-links.ps1
# Applies the two homepage header improvements (logo + "tom/rhodes" wordmark, and a
# "Discovery" link) to every other page that has a header, across the upgraded site.
#   - blog/** and books/**  : "logo" template (root-relative or ../ / ../.. links)
#   - recommends/**        : currently render NO header; inject a real one
#   - discovery/**         : "brand" template; add a Home link so it can navigate out
# Idempotent: skips files that already contain the wordmark or the Discovery link.
#
# Usage:
#   pwsh -File add-header-links.ps1
#   pwsh -File add-header-links.ps1 -WhatIf

[CmdletBinding()]
param([switch]$WhatIf)

$base = 'C:\Users\richa\OneDrive\Documents\dev\discovery-booktrawler-com'
$siteUrl = 'https://tomrhodes.me/'

# Wordmark span styled inline so we don't have to edit each file's <style> block.
$wordmark = '<span class="logo-wordmark" style="font-family:''Cormorant Garamond'',''Inter'',serif;font-size:1.5rem;font-weight:600;letter-spacing:.02em;color:#f4f1ea;line-height:1;">tom/rhodes</span>'

$files = Get-ChildItem -LiteralPath $base -Recurse -Filter *.html |
    Where-Object { $_.FullName -notmatch '\\new-site\\' -and $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\\.kilo\\' -and $_.FullName -ne (Join-Path $base 'index.html') } |
    Select-Object -ExpandProperty FullName

$changed = 0
$cLogo = 0; $cBrand = 0; $cRec = 0

foreach ($f in $files) {
    $rel  = $f.Replace("$base\", "").Replace('\', '/')
    $html = Get-Content -Raw -LiteralPath $f
    $orig = $html
    $wasChanged = $false

    # ---------- CASE 1: "logo" template (blog + books) ----------
    if ($html -match 'class="logo"') {
        if ($html -notmatch 'logo-wordmark') {
            # Inject the wordmark inside the logo <a> (after any existing <img> or text).
            $html = [regex]::Replace($html,
                '(?s)(<a[^>]*class="logo"[^>]*>)(.*?)(</a>)',
                {
                    param($m)
                    if ($m.Groups[2].Value -match 'logo-wordmark') { return $m.Value }
                    return $m.Groups[1].Value + $m.Groups[2].Value + $wordmark + $m.Groups[3].Value
                })
            $cLogo++
            $wasChanged = $true
        }
        if ($html -notmatch 'href="/discovery/"') {
            if ($html -match '<div class="nav-links">') {
                # Append a Discovery link inside the existing nav-links container.
                $html = [regex]::Replace($html,
                    '(?s)(<div class="nav-links">)(.*?)(</div>)',
                    {
                        param($m)
                        if ($m.Groups[2].Value -match 'href="/discovery/"') { return $m.Value }
                        return $m.Groups[1].Value + $m.Groups[2].Value + '<a href="/discovery/">Discovery</a>' + $m.Groups[3].Value
                    })
            }
            else {
                # No nav-links container: append a Discovery link right after the logo <a> (inside <nav>).
                $html = [regex]::Replace($html,
                    '(?s)(<a[^>]*class="logo"[^>]*>.*?</a>)',
                    {
                        param($m)
                        if ($m.Value -match 'href="/discovery/"') { return $m.Value }
                        return $m.Value + '<a href="/discovery/">Discovery</a>'
                    })
            }
            $cLogo++
            $wasChanged = $true
        }
    }

    # ---------- CASE 2: "brand" template (discovery) ----------
    elseif ($html -match 'class="brand"') {
        if ($html -notmatch 'href="/discovery/"' -and $html -notmatch 'href="\./"') {
            # Add a Home (tom/rhodes) link so discovery pages can navigate to the main site.
            $html = [regex]::Replace($html,
                '(?s)(<a class="brand"[^>]*>.*?</a>)(<nav>)',
                {
                    param($m)
                    return $m.Groups[1].Value + '<a href="/">Home</a>' + $m.Groups[2].Value
                })
            $cBrand++
            $wasChanged = $true
        }
    }

    # ---------- CASE 1b: books landing pages with a bare logo <a> (no class="logo") ----------
    elseif ($rel -like 'books/*' -and $html -match '(?s)<a href="\.\./\.\./"><img[^>]*logo\.png') {
        if ($html -notmatch 'logo-wordmark') {
            $html = [regex]::Replace($html,
                '(?s)(<a href="\.\./\.\./"><img[^>]*logo\.png[^>]*></a>)',
                {
                    param($m)
                    return $m.Groups[1].Value + $wordmark
                })
            $cLogo++
            $wasChanged = $true
        }
        if ($html -notmatch 'href="/discovery/"') {
            if ($html -match '<div class="nav-links">') {
                $html = [regex]::Replace($html,
                    '(?s)(<div class="nav-links">)(.*?)(</div>)',
                    {
                        param($m)
                        if ($m.Groups[2].Value -match 'href="/discovery/"') { return $m.Value }
                        return $m.Groups[1].Value + $m.Groups[2].Value + '<a href="/discovery/">Discovery</a>' + $m.Groups[3].Value
                    })
            }
            else {
                $html = [regex]::Replace($html,
                    '(?s)(<a href="\.\./\.\./"><img[^>]*logo\.png[^>]*></a>)',
                    {
                        param($m)
                        if ($m.Value -match 'href="/discovery/"') { return $m.Value }
                        return $m.Value + '<a href="/discovery/">Discovery</a>'
                    })
            }
            $cLogo++
            $wasChanged = $true
        }
    }

    # ---------- CASE 3: recommends ----------
    elseif ($rel -like 'recommends/*') {
        # Detect the rendered header element (not the CSS rule .sg-header-inner).
        $hasHeaderEl = $html -match '<header[^>]*class="sg-header"' -or $html -match 'class="sg-header-inner"'
        if (-not $hasHeaderEl) {
            # recommends/index.html: no header element at all -> inject a full sticky header.
            $header = '<header class="sg-header"><div class="sg-header-inner" style="display:flex;align-items:center;justify-content:space-between;gap:1rem;">' +
                      '<a href="/" class="logo" style="display:flex;align-items:center;gap:.6rem;text-decoration:none;">' +
                      '<img src="/images/logo.png" alt="tom/rhodes" style="height:36px;width:auto;border-radius:6px;">' +
                      $wordmark +
                      '</a>' +
                      '<nav style="display:flex;gap:1.25rem;"><a href="/discovery/">Discovery</a><a href="/blog/">Blog</a><a href="/#books">Books</a></nav>' +
                      '</div></header>'
            $html = $html -replace '(?s)(<body>)', "`$1`n$header"
            $cRec++
            $wasChanged = $true
        }
        elseif ($html -notmatch 'logo-wordmark') {
            # recommends/books/*.html: header exists but lacks logo/wordmark + Discovery link.
            # Add the wordmark right after the opening <div class="sg-header-inner">.
            $html = [regex]::Replace($html,
                '(?s)(<div class="sg-header-inner">)',
                {
                    param($m)
                    return $m.Groups[1].Value + '<a href="/" class="logo" style="display:flex;align-items:center;gap:.6rem;text-decoration:none;">' +
                           '<img src="/images/logo.png" alt="tom/rhodes" style="height:32px;width:auto;border-radius:6px;">' + $wordmark + '</a>'
                })
            # Add a Discovery link after the existing "All Lists" link.
            if ($html -notmatch 'href="/discovery/"') {
                $html = [regex]::Replace($html,
                    '(?s)(<a class="sg-nav-link" href="\.\./index\.html">.*?</a>)',
                    { param($m) return $m.Groups[1].Value + '<a class="sg-nav-link" href="/discovery/">Discovery</a><a class="sg-nav-link" href="/">Home</a>' })
            }
            $cRec++
            $wasChanged = $true
        }
    }

    if ($wasChanged) {
        if (-not $WhatIf) { Set-Content -LiteralPath $f -Encoding utf8 -Value $html }
        $changed++
    }
}

Write-Host "$(if ($WhatIf){'DRY-RUN: '}else{''})Updated $changed page(s). logo-template:$cLogo brand-template:$cBrand recommends:$cRec"
