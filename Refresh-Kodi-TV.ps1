# Refresh-Kodi-TV.ps1
# Consolidate IPTV-org playlists into one Kodi M3U with one group per source.
# Windows PowerShell 5.1+ / PowerShell 7+, no extra modules required.
# Does not modify any existing Kodi configuration.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $folder 'Kodi-Organized-TV.m3u'

# The three sources configured in our Kodi conversation.
# To include another IPTV-org source, uncomment its row or supply its verified URL.
$sources = @(
  @{ Group = 'Persian TV';   Url = 'https://iptv-org.github.io/iptv/countries/ir.m3u' },
  @{ Group = 'World News';   Url = 'https://iptv-org.github.io/iptv/categories/news.m3u' },
  @{ Group = 'Sports';       Url = 'https://iptv-org.github.io/iptv/categories/sports.m3u' },
  @{ Group = 'US Live TV';   Url = 'https://iptv-org.github.io/iptv/countries/us.m3u' }
  # OPTIONAL: The worldwide index contains many thousands of channels and can slow Kodi.
  # To include it, add a comma to the US Live TV line and uncomment this line:
  # @{ Group = 'International'; Url = 'https://iptv-org.github.io/iptv/index.m3u' }
)

# Each complete entry may have Kodi/VLC option lines before its stream URL.
# Keep original metadata, options, media URLs, and tvg IDs; change only group-title.
$merged = New-Object 'System.Collections.Generic.List[string]'
$merged.Add('#EXTM3U')
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$total = 0
$successful = 0
foreach ($source in $sources) {
  $url = $source.Url
  $group = $source.Group
  Write-Host "Fetching $group ..."
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 45 -Headers @{ 'User-Agent' = 'Mozilla/5.0 KodiPlaylistOrganizer/1.0' }
    # In Windows PowerShell 5.1, M3U responses with audio/x-mpegurl can be
    # returned as byte[]; casting directly to [string] yields 'System.Byte[]'.
    if ($response.Content -is [byte[]]) {
      $content = [System.Text.Encoding]::UTF8.GetString($response.Content)
    } else {
      $content = [string]$response.Content
    }
    $content = $content.TrimStart([char[]]@([char]0xFEFF, [char]0x20, [char]0x0D, [char]0x0A, [char]0x09))
    if (-not $content.StartsWith('#EXTM3U')) {
      $preview = $content.Substring(0, [Math]::Min(75, $content.Length)).Replace("`r", ' ').Replace("`n", ' ')
      throw "Unexpected response from $url (Content-Type: $($response.Headers['Content-Type']); starts with: $preview)"
    }
    $lines = $content -split "`r?`n"
    $entry = New-Object 'System.Collections.Generic.List[string]'
    $count = 0
    foreach ($lineRaw in $lines) {
      $line = $lineRaw.TrimEnd("`r")
      if ($line.StartsWith('#EXTINF:')) {
        $entry.Clear()
        if ($line -match 'group-title="[^"]*"') {
          $line = [regex]::Replace($line, 'group-title="[^"]*"', ('group-title="' + $group + '"'))
        } else {
          $line = $line -replace '^#EXTINF:', ('#EXTINF:')
          $commaIndex = $line.IndexOf(',')
          if ($commaIndex -ge 0) {
            $line = $line.Substring(0,$commaIndex) + ' group-title="' + $group + '"' + $line.Substring($commaIndex)
          } else {
            $line += ' group-title="' + $group + '"'
          }
        }
        $entry.Add($line)
      } elseif ($entry.Count -gt 0 -and $line.StartsWith('#')) {
        $entry.Add($line)
      } elseif ($entry.Count -gt 0 -and $line.Trim().Length -gt 0) {
        # A stream URL terminates the entry. Deduplicate overlapping sources.
        $stream = $line.Trim()
        if ($seen.Add($stream)) {
          foreach ($item in $entry) { $merged.Add($item) }
          $merged.Add($stream)
          $count++
          $total++
        }
        $entry.Clear()
      }
    }
    Write-Host "  Added $count unique channels to $group"
    $successful++
  } catch {
    Write-Warning "Unable to fetch ${group}: $($_.Exception.Message)"
  }
}
if ($successful -ne $sources.Count -or $total -eq 0) {
  Write-Error 'One or more sources failed. Existing output file was NOT replaced. Check internet connectivity and source URLs.'
  exit 1
}
$temp = "$output.tmp"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($temp, $merged.ToArray(), $utf8NoBom)
Move-Item -Path $temp -Destination $output -Force
Write-Host "`nSUCCESS: $total channels across $successful source groups"
Write-Host "Playlist: $output"
Write-Host 'Next: Add it as a NEW local M3U instance in IPTV Simple Client; do not disable existing instances yet.'
