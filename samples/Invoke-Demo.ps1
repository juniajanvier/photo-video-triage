<#
.SYNOPSIS
    Runs the whole pipeline end to end against a fake library. Safe to run anywhere.

.DESCRIPTION
    1. Builds a placeholder library (New-DemoLibrary.ps1)
    2. Find-BigVideos.ps1        -> big-videos.csv
    3. New-ReviewFolders.ps1     -> review\ (shortcuts only)
    4. Find-Duplicates.ps1       -> duplicate-report.csv (report only)
    5. Find-Duplicates.ps1 -StageTo -VerifyHash -> _staged\ + move-log.csv
    6. Restore-StagedFiles.ps1   -> everything moved back, restore-log.csv

.PARAMETER Path
    Empty or new folder for the demo. Defaults to "$env:TEMP\photo-video-triage-demo-<timestamp>".
#>
[CmdletBinding()]
param(
    [string]$Path = ([IO.Path]::Combine($env:TEMP, ('photo-video-triage-demo-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))))
)

$ErrorActionPreference = 'Stop'
$scripts = [IO.Path]::Combine([IO.Path]::GetDirectoryName($PSScriptRoot), 'scripts')
$full    = [IO.Path]::GetFullPath($Path)
$lib     = [IO.Path]::Combine($full, 'library')
$sizes   = [IO.Path]::Combine($full, 'demo-sizes.csv')

function Write-Step { param([string]$Text) Write-Host ''; Write-Host "=== $Text ===" -ForegroundColor Cyan }

Write-Step '1. Build placeholder library'
& ([IO.Path]::Combine($PSScriptRoot, 'New-DemoLibrary.ps1')) -Path $full

Write-Step '2. Videos over 1 GB -> CSV'
& ([IO.Path]::Combine($scripts, 'Find-BigVideos.ps1')) -Root $lib -SizeMap $sizes -Out ([IO.Path]::Combine($full, 'big-videos.csv'))
Import-Csv ([IO.Path]::Combine($full, 'big-videos.csv')) | Select-Object '#', 'File name', 'Filmed on', 'Time', 'Size (GB)' | Format-Table -AutoSize | Out-Host

Write-Step '3. Review folders (shortcuts only)'
& ([IO.Path]::Combine($scripts, 'New-ReviewFolders.ps1')) -Root $lib -SizeMap $sizes -Out ([IO.Path]::Combine($full, 'review'))
Get-ChildItem -LiteralPath ([IO.Path]::Combine($full, 'review')) -Recurse -File |
    ForEach-Object { $_.FullName.Substring($full.Length + 1) } | Out-Host

Write-Step '4. Duplicate report (report only, the default)'
& ([IO.Path]::Combine($scripts, 'Find-Duplicates.ps1')) -Root $lib -SizeMap $sizes -Out ([IO.Path]::Combine($full, 'duplicate-report.csv'))

Write-Step '5. Opt-in staging with hash check (move + log, no delete)'
$stage = [IO.Path]::Combine($full, '_staged')
& ([IO.Path]::Combine($scripts, 'Find-Duplicates.ps1')) -Root $lib -SizeMap $sizes -Out ([IO.Path]::Combine($full, 'duplicate-report-verified.csv')) -StageTo $stage -VerifyHash
Import-Csv ([IO.Path]::Combine($stage, 'move-log.csv')) | Select-Object @{ n = 'From'; e = { $_.OriginalLocation.Substring($lib.Length + 1) } }, SizeMB, Result | Format-Table -AutoSize | Out-Host

Write-Step '6. Restore everything from the move log'
& ([IO.Path]::Combine($scripts, 'Restore-StagedFiles.ps1')) -LogPath ([IO.Path]::Combine($stage, 'move-log.csv'))
$count = @(Get-ChildItem -LiteralPath $lib -Recurse -File).Count
Write-Host "Files back in the library: $count"

Write-Host ''
Write-Host "Demo output: $full"
Write-Host 'Nothing was deleted. The demo folder is yours to inspect and remove by hand when done.'
