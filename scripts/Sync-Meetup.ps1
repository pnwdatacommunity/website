<#
.SYNOPSIS
  Pulls upcoming events from Meetup's public iCal feeds into data/meetup.json.

.DESCRIPTION
  Meetup's GraphQL API is a Meetup Pro feature, but every group publishes a public
  iCalendar feed at https://www.meetup.com/<group>/events/ical/ that needs no key.
  The deploy workflow runs this before every build, including the daily one, so
  anything scheduled on Meetup appears on the site within a day with no commit.

  Events also listed in data/meetings.yaml are shown once: the YAML entry wins, so
  use the YAML to override a title or link. If Meetup can't be reached, the script
  warns and leaves any existing data/meetup.json in place; the build never fails on it.

  Works on Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
  .\scripts\Sync-Meetup.ps1          # then: hugo server
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    # urlname = the part after meetup.com/ ; host = label shown on the site.
    [object[]]$Groups = @(
        @{ urlname = 'oregonsql';               host = 'Oregon Data Community' },
        @{ urlname = 'portland-azure-user-group'; host = 'Portland Azure Data User Group' }
    )
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-PacificZone {
    foreach ($id in 'America/Los_Angeles', 'Pacific Standard Time') {
        try { return [TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
    }
    throw 'Could not find the Pacific time zone.'
}

function ConvertFrom-IcsText([string]$s) {
    # RFC 5545 escapes: \n \, \; \\
    return ($s -replace '\\[nN]', "`n" -replace '\\,', ',' -replace '\\;', ';' -replace '\\\\', '\').Trim()
}

function ConvertFrom-IcsDate([string]$params, [string]$value, [TimeZoneInfo]$defaultZone) {
    $fmt = if ($value.Length -gt 8) { 'yyyyMMddTHHmmss' } else { 'yyyyMMdd' }
    $raw = $value.TrimEnd('Z')
    $dt = [datetime]::ParseExact($raw, $fmt, [Globalization.CultureInfo]::InvariantCulture)
    if ($value.EndsWith('Z')) {
        return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::new([datetime]::SpecifyKind($dt, 'Utc')), $defaultZone)
    }
    $zone = $defaultZone
    if ($params -match 'TZID=([^;:]+)') {
        foreach ($id in $Matches[1], 'Pacific Standard Time') {
            try { $zone = [TimeZoneInfo]::FindSystemTimeZoneById($id); break } catch { }
        }
    }
    return [DateTimeOffset]::new($dt, $zone.GetUtcOffset($dt))
}

function Get-MeetupEvents([string]$urlname, [string]$hostName, [TimeZoneInfo]$zone, [int]$rank) {
    $url = "https://www.meetup.com/$urlname/events/ical/"
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'pnwdatacommunity-website (+https://github.com/pnwdatacommunity/website)' }
    $text = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
    if ($text -notmatch 'BEGIN:VCALENDAR') { throw "Not an iCalendar feed: $url" }

    # Unfold continuation lines (CRLF followed by a space or tab).
    $text = [regex]::Replace($text, '\r?\n[ \t]', '')
    $events = @()
    foreach ($block in [regex]::Matches($text, '(?s)BEGIN:VEVENT(.*?)END:VEVENT')) {
        $props = @{}
        foreach ($line in ($block.Groups[1].Value -split '\r?\n')) {
            if ($line -match '^([A-Z-]+)((?:;[^:]*)?):(.*)$') {
                if (-not $props.ContainsKey($Matches[1])) { $props[$Matches[1]] = @($Matches[2], $Matches[3]) }
            }
        }
        if (-not $props.ContainsKey('DTSTART') -or -not $props.ContainsKey('SUMMARY')) { continue }
        $start = ConvertFrom-IcsDate $props['DTSTART'][0] $props['DTSTART'][1] $zone
        $desc  = if ($props.ContainsKey('DESCRIPTION')) { ConvertFrom-IcsText $props['DESCRIPTION'][1] } else { '' }
        # Meetup prefixes the description with the group name; drop that line.
        $desc  = ($desc -replace ('^' + [regex]::Escape($hostName) + '\s*'), '') -replace '^\s+', ''
        $summary = if ($desc.Length -gt 220) { $desc.Substring(0, 220).TrimEnd() + '…' } else { $desc }
        $events += [ordered]@{
            date    = $start.ToString("yyyy-MM-dd'T'HH:mm:sszzz", [Globalization.CultureInfo]::InvariantCulture)
            title   = ConvertFrom-IcsText $props['SUMMARY'][1]
            url     = if ($props.ContainsKey('URL')) { $props['URL'][1].Trim() } else { "https://www.meetup.com/$urlname/" }
            host    = $hostName
            format  = if ($props.ContainsKey('LOCATION') -and $props['LOCATION'][1].Trim()) { ConvertFrom-IcsText $props['LOCATION'][1] } else { '' }
            summary = $summary
            source  = 'meetup'
            _utc    = $start.UtcTicks
            _rank   = $rank
        }
    }
    return ,$events
}

$zone = Get-PacificZone
$all = @()
$failed = 0
$rank = 0
foreach ($g in $Groups) {
    $rank++
    try {
        $found = Get-MeetupEvents $g.urlname $g.host $zone $rank
        Write-Host ("{0,-28} {1} upcoming" -f $g.urlname, @($found).Count)
        $all += $found
    } catch {
        Write-Warning "Meetup feed for '$($g.urlname)' failed: $($_.Exception.Message)"
        $failed++
    }
}

$out = Join-Path (Join-Path $RepoRoot 'data') 'meetup.json'
if ($failed -eq @($Groups).Count) {
    Write-Warning "No feed could be read; leaving $out unchanged."
    return
}
$doc = [ordered]@{
    fetched = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    # By start time; when two groups list the same event, the first group in -Groups comes first
    # (the site shows each start time once, keeping the first entry it sees).
    events  = @($all | Sort-Object { $_._utc }, { $_._rank } | ForEach-Object { $_.Remove('_utc'); $_.Remove('_rank'); $_ })
}
$json = ConvertTo-Json -InputObject $doc -Depth 4
[IO.File]::WriteAllText($out, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $(@($all).Count) events to $out"
