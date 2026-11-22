<#
.SYNOPSIS
    Lists every video above a size threshold (default 1 GB) into a CSV ready for a Google Sheet.

.DESCRIPTION
    Read-only. Scans -Root using file-system metadata only (no file is opened, so online-only
    cloud files are not downloaded). Writes one row per video with the filmed date, time and
    size, plus an empty Decision column for the review sheet described in docs/google-sheet-setup.md.

    Columns: #, File name, Filmed on, Time, Size (GB), Decision, Online only, Folder

.PARAMETER Root
    Folder to scan, for example "$HOME\Pictures\iCloud Photos\Photos".

.PARAMETER Out
    CSV to write. Defaults to "$HOME\Desktop\videos-over-1-GB.csv".

.PARAMETER MinSizeGB
    Size threshold in GB. Default 1.

.PARAMETER SizeMap
    Optional CSV (RelativePath,SizeBytes) that overrides real sizes. Used by the demo library.

.EXAMPLE
    .\Find-BigVideos.ps1 -Root "$HOME\Pictures\iCloud Photos\Photos"

.EXAMPLE
    .\Find-BigVideos.ps1 -Root D:\Media -Out D:\Reports\big.csv -MinSizeGB 2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Out = ([IO.Path]::Combine($HOME, 'Desktop', 'videos-over-1-GB.csv')),
    [double]$MinSizeGB = 1,
    [string]$SizeMap
)

$ErrorActionPreference = 'Stop'
. ([IO.Path]::Combine($PSScriptRoot, 'TriageCommon.ps1'))

$map = Import-SizeMap -Path $SizeMap -Root $Root
$min = [int64]($MinSizeGB * 1GB)

Write-Host "Scanning $Root (metadata only)..."
$videos = @(Get-MediaInventory -Root $Root -SizeMap $map |
    Where-Object { $_.IsVideo -and $_.Length -gt $min } |
    Sort-Object Length -Descending)

$culture = [Globalization.CultureInfo]::InvariantCulture
$i = 0
$rows = foreach ($v in $videos) {
    $i++
    [pscustomobject][ordered]@{
        '#'           = $i
        'File name'   = $v.Name
        'Filmed on'   = $v.Filmed.ToString('yyyy-MM-dd', $culture)
        'Time'        = $v.Filmed.ToString('h:mm tt', $culture)
        'Size (GB)'   = [math]::Round($v.Length / 1GB, 2)
        'Decision'    = ''
        'Online only' = $(if ($v.OnlineOnly) { 'Yes' } else { 'No' })
        'Folder'      = $v.Directory
    }
}

New-ParentFolder $Out
if ($rows) {
    $rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
} else {
    '"#","File name","Filmed on","Time","Size (GB)","Decision","Online only","Folder"' |
        Set-Content -LiteralPath $Out -Encoding UTF8
}

$totalGB = [math]::Round((($videos | Measure-Object Length -Sum).Sum) / 1GB, 1)
Write-Host ("Found {0} videos over {1} GB, {2} GB in total." -f $videos.Count, $MinSizeGB, $totalGB)
Write-Host "CSV: $Out"
Write-Host "Nothing was moved or deleted."
