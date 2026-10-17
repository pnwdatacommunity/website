<#
.SYNOPSIS
  Converts a WordPress.com export (WXR .xml) into Hugo content for this repo.

.DESCRIPTION
  - Published posts  -> content/posts/<yyyy>-<mm>-<dd>-<slug>.md
    Front matter keeps the original date and slug, so the permalink
    /yyyy/mm/dd/slug/ matches the old oregonsql.org URL exactly.
  - Published pages  -> import/pages/<slug>.md (NOT published; review and move by hand)
  - Images under /wp-content/uploads/ (oregonsql.org, *.files.wordpress.com, i0-i3.wp.com)
    are downloaded to static/images/wp/<yyyy>/<mm>/ and links rewritten,
    so nothing still depends on WordPress.com once the plan is cancelled.
  - Gutenberg block comments (<!-- wp:... -->) are stripped. The HTML body is kept as-is.

  Works on Windows PowerShell 5.1 and PowerShell 7. Writes UTF-8 without BOM.

.EXAMPLE
  .\scripts\Convert-WordPressExport.ps1 -XmlPath "$env:USERPROFILE\Downloads\oregondatacommunity.wordpress.2026-10-17.xml" -WhatIf

.EXAMPLE
  .\scripts\Convert-WordPressExport.ps1 -XmlPath ..\export.xml -SkipImages
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$XmlPath,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SkipImages,   # keep image links pointing at WordPress (no download)
    [switch]$Force   # overwrite existing .md files
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-YamlString([string]$s) {
    # Single-quoted YAML scalar: only ' needs escaping (doubled).
    if ($null -eq $s) { return "''" }
    return "'" + ($s -replace "'", "''").Trim() + "'"
}

function Get-Text($node, [string]$xpath, $ns) {
    $n = $node.SelectSingleNode($xpath, $ns)
    if ($null -eq $n) { return '' }
    return $n.InnerText
}

$xmlFull = (Resolve-Path -LiteralPath $XmlPath).Path
[xml]$doc = [IO.File]::ReadAllText($xmlFull, [Text.Encoding]::UTF8)

$ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
$ns.AddNamespace('content', 'http://purl.org/rss/1.0/modules/content/')
$ns.AddNamespace('excerpt', 'http://wordpress.org/export/1.2/excerpt/')
$ns.AddNamespace('dc', 'http://purl.org/dc/elements/1.1/')
# The wp: namespace URI varies by WXR version (1.0/1.1/1.2); read it from the document.
$wpUri = $doc.DocumentElement.GetNamespaceOfPrefix('wp')
if (-not $wpUri) { $wpUri = 'http://wordpress.org/export/1.2/' }
$ns.AddNamespace('wp', $wpUri)

$postsDir  = Join-Path (Join-Path $RepoRoot 'content') 'posts'
$pagesDir  = Join-Path (Join-Path $RepoRoot 'import') 'pages'
$imagesDir = Join-Path (Join-Path (Join-Path $RepoRoot 'static') 'images') 'wp'
foreach ($d in @($postsDir, $pagesDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force -WhatIf:$false | Out-Null }
}

# Matches upload URLs in src/href/srcset. Group 'path' = yyyy/mm/file.ext
$imgPattern = '(?i)https?://(?:i[0-3]\.wp\.com/)?(?:[a-z0-9.-]+\.)?(?:oregonsql\.org|files\.wordpress\.com)/(?:[a-z0-9.-]+/)?wp-content/uploads/(?<path>\d{4}/\d{2}/[^"''\s?#)]+)(?:\?[^"''\s)]*)?|https?://[a-z0-9-]+\.files\.wordpress\.com/(?<path2>\d{4}/\d{2}/[^"''\s?#)]+)(?:\?[^"''\s)]*)?'

$downloaded = @{}
$stats = [ordered]@{ Posts = 0; Pages = 0; Skipped = 0; Images = 0; ImageErrors = 0 }

function Convert-Body([string]$html) {
    $html = [regex]::Replace($html, '<!--\s*/?wp:[\s\S]*?-->\r?\n?', '')
    $evaluator = {
        param($m)
        $rel = if ($m.Groups['path'].Success) { $m.Groups['path'].Value } else { $m.Groups['path2'].Value }
        $rel = [Uri]::UnescapeDataString($rel)
        if ($SkipImages) { return $m.Value }   # leave links pointing at WordPress
        $local = '/images/wp/' + ($rel -replace ' ', '%20')
        if (-not $downloaded.ContainsKey($rel)) {
            $downloaded[$rel] = $true
            $dest = Join-Path $imagesDir ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $dest)) {
                $src = ($m.Value -split '\?')[0]
                if ($PSCmdlet.ShouldProcess($src, "Download to $dest")) {
                    try {
                        $dir = Split-Path -Parent $dest
                        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                        Invoke-WebRequest -Uri $src -OutFile $dest -UseBasicParsing
                        $script:stats.Images++
                    } catch {
                        Write-Warning "Image failed: $src ($($_.Exception.Message))"
                        $script:stats.ImageErrors++
                        return $m.Value   # keep the original link rather than break it
                    }
                }
            }
        }
        return $local
    }
    return [regex]::Replace($html, $imgPattern, [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

foreach ($item in $doc.SelectNodes('//channel/item')) {
    $type   = Get-Text $item 'wp:post_type' $ns
    $status = Get-Text $item 'wp:status' $ns
    if ($status -ne 'publish' -or ($type -ne 'post' -and $type -ne 'page')) { $stats.Skipped++; continue }

    $title = Get-Text $item 'title' $ns
    $slug  = Get-Text $item 'wp:post_name' $ns
    $date  = Get-Text $item 'wp:post_date' $ns          # "2025-09-15 10:22:33" (site local time)
    $body  = Get-Text $item 'content:encoded' $ns
    $exc   = Get-Text $item 'excerpt:encoded' $ns
    $link  = Get-Text $item 'link' $ns
    if (-not $slug) { $slug = ($title.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }

    $dt = [datetime]::ParseExact($date, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)

    $tags = @()
    foreach ($c in $item.SelectNodes('category')) {
        $v = $c.InnerText.Trim()
        if ($v -and $v -ne 'Uncategorized' -and $tags -notcontains $v) { $tags += $v }
    }

    $fm = New-Object System.Text.StringBuilder
    [void]$fm.AppendLine('---')
    [void]$fm.AppendLine('title: ' + (ConvertTo-YamlString $title))
    [void]$fm.AppendLine('date: ' + $dt.ToString('yyyy-MM-ddTHH:mm:ss'))
    [void]$fm.AppendLine('slug: ' + (ConvertTo-YamlString $slug))
    if ($exc.Trim()) { [void]$fm.AppendLine('description: ' + (ConvertTo-YamlString ($exc -replace '<[^>]+>', ''))) }
    if ($tags.Count) {
        $quoted = @(); foreach ($t in $tags) { $quoted += (ConvertTo-YamlString $t) }
        [void]$fm.AppendLine('tags: [' + ($quoted -join ', ') + ']')
    }
    [void]$fm.AppendLine('wp_url: ' + (ConvertTo-YamlString $link))
    if ($type -eq 'page') { [void]$fm.AppendLine('draft: true') }
    [void]$fm.AppendLine('---')
    [void]$fm.AppendLine('')

    $content = $fm.ToString() + (Convert-Body $body).Trim() + "`n"

    if ($type -eq 'post') {
        $file = Join-Path $postsDir ('{0}-{1}.md' -f $dt.ToString('yyyy-MM-dd'), $slug)
    } else {
        $file = Join-Path $pagesDir ($slug + '.md')
    }

    if ((Test-Path -LiteralPath $file) -and -not $Force) {
        Write-Verbose "Exists, skipping (use -Force): $file"; $stats.Skipped++; continue
    }
    if ($PSCmdlet.ShouldProcess($file, "Write $type '$title'")) {
        [IO.File]::WriteAllText($file, $content, $utf8NoBom)
    }
    if ($type -eq 'post') { $stats.Posts++ } else { $stats.Pages++ }
}

[pscustomobject]$stats
Write-Host "Next: hugo server  ->  review http://localhost:1313/posts/ , then git add/commit." -ForegroundColor Cyan
