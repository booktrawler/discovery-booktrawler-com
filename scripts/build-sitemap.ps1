# build-sitemap.ps1
# Regenerates the root sitemap.xml with the canonical domain tomrhodes.me.
# Index.html files are listed as their directory URL (trailing slash).
# The repo-root gag index.html is intentionally excluded (it redirects to /discovery/).

$base = 'C:\Users\richa\OneDrive\Documents\dev\discovery-booktrawler-com'
$sitemap = Join-Path $base 'sitemap.xml'
$siteUrl = 'https://tomrhodes.me/'

# Walk the whole repo for HTML pages, excluding non-public paths.
$excludeDirs = @('new-site', '.git', '.kilo')
$files = Get-ChildItem -LiteralPath $base -Recurse -Filter *.html |
    Where-Object {
        $rel = $_.FullName.Replace("$base\", "").Replace('\', '/')
        -not ($excludeDirs | Where-Object { $rel -like "$_/*" -or $rel -eq $_ })
    } |
    Select-Object -ExpandProperty FullName |
    ForEach-Object { $_.Replace("$base\", "").Replace('\', '/') } |
    Sort-Object

$xml = New-Object System.Xml.XmlDocument
$decl = $xml.CreateXmlDeclaration('1.0', 'UTF-8', $null)
[void]$xml.AppendChild($decl)
$urlset = $xml.CreateElement('urlset')
[void]$urlset.SetAttribute('xmlns', 'http://www.sitemaps.org/schemas/sitemap/0.9')
[void]$xml.AppendChild($urlset)

function Add-Url($u) {
    $url = $xml.CreateElement('url')
    $loc = $xml.CreateElement('loc')
    $loc.InnerText = $u
    [void]$url.AppendChild($loc)
    [void]$urlset.AppendChild($url)
}

foreach ($f in $files) {
    if ($f -eq 'index.html') {
        Add-Url $siteUrl
        continue
    }
    if ($f.EndsWith('/index.html')) {
        $dir = $f.Substring(0, $f.Length - 'index.html'.Length)
        Add-Url ($siteUrl + $dir)
        continue
    }
    Add-Url ($siteUrl + $f)
}

$xml.Save($sitemap)
Write-Host "Wrote $($urlset.ChildNodes.Count) URLs to $sitemap"
