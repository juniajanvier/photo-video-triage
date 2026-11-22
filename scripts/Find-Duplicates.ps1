<#
.SYNOPSIS
    Reports exact duplicate copies (same base name ignoring " (1)", same extension, same size).
    Optionally stages the extra copies into a holding folder with a restore log. Never deletes.

.DESCRIPTION
    Default behavior is REPORT ONLY: a CSV listing every extra copy and the original it matches.

    With -StageTo, each extra copy is MOVED (not deleted) into the staging folder, keeping its
    relative path, and one row per file is appended to a move log:
        OriginalLocation, NowAt, OriginalKeptAt, SizeMB, Result
    Restore-StagedFiles.ps1 reads that log and puts everything back.

    Safety rules built in:
      * Online-only (cloud placeholder) files are skipped unless -IncludeOnlineOnly is set,
        because moving them forces a download and may count as a removal in the cloud.
      * A file is only moved if the original it matches still exists.
      * A file whose size changed since the scan is skipped.
      * With -VerifyHash, local copies must also match the original by SHA-256.
      * Supports -WhatIf and -Confirm on every move.
      * Existing files in the staging folder are never overwritten.

    WARNING: moving a file OUT of a cloud-synced folder (iCloud Photos, OneDrive, etc.) is
    treated by the sync client as removing it from the cloud. Use -StageTo for copies that
    live outside the synced library (old exports, backups, downloads), or stage into a folder
    inside the same synced library.

.PARAMETER Root
    Folder to scan.

.PARAMETER Out
    Report CSV. Defaults to "$HOME\Desktop\duplicate-report.csv".

.PARAMETER StageTo
    Opt-in. Folder to move extra copies into. Excluded from the scan.

.PARAMETER LogPath
    Move log CSV. Defaults to "<StageTo>\move-log.csv". Rows are appended, never rewritten.

.PARAMETER VerifyHash
    Also compare SHA-256 of each local extra copy with its original before reporting it as verified.

.PARAMETER IncludeOnlineOnly
    Allow staging of online-only files. Off by default.

.PARAMETER MinSizeMB
    Ignore files smaller than this. Default 0.

.PARAMETER SizeMap
    Optional CSV (RelativePath,SizeBytes) that overrides real sizes. Used by the demo library.

.EXAMPLE
    .\Find-Duplicates.ps1 -Root D:\Media
    Report only.

.EXAMPLE
    .\Find-Duplicates.ps1 -Root D:\Media -StageTo D:\_to_delete -VerifyHash -WhatIf
    Shows what would be staged without moving anything.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Out = ([IO.Path]::Combine($HOME, 'Desktop', 'duplicate-report.csv')),
    [string]$StageTo,
    [string]$LogPath,
    [switch]$VerifyHash,
    [switch]$IncludeOnlineOnly,
    [double]$MinSizeMB = 0,
    [string]$SizeMap
)

$ErrorActionPreference = 'Stop'
. ([IO.Path]::Combine($PSScriptRoot, 'TriageCommon.ps1'))

$rootFull = [IO.Path]::GetFullPath($Root)
$staging  = -not [string]::IsNullOrEmpty($StageTo)
$exclude  = @()
if ($staging) {
    $stageFull = [IO.Path]::GetFullPath($StageTo)
    if (Test-IsUnder $rootFull $stageFull) { throw "-StageTo cannot be -Root or a parent of -Root." }
    $exclude += $stageFull
    if ([string]::IsNullOrEmpty($LogPath)) { $LogPath = [IO.Path]::Combine($stageFull, 'move-log.csv') }
}

$map = Import-SizeMap -Path $SizeMap -Root $rootFull
Write-Host "Scanning $rootFull (metadata only)..."
$minBytes = [int64]($MinSizeMB * 1MB)
$all  = @(Get-MediaInventory -Root $rootFull -Exclude $exclude -SizeMap $map | Where-Object { $_.Length -ge $minBytes })
$sets = @(Get-DuplicateSets -Items $all)

function Get-HashCheck {
    param($Extra, $Keep)
    if (-not $VerifyHash) { return 'Not checked' }
    if ($Extra.OnlineOnly -or $Keep.OnlineOnly) { return 'Skipped (online-only)' }
    $a = (Get-FileHash -LiteralPath $Extra.FullName -Algorithm SHA256).Hash
    $b = (Get-FileHash -LiteralPath $Keep.FullName  -Algorithm SHA256).Hash
    if ($a -eq $b) { return 'Match' }
    return 'Mismatch'
}

$report = New-Object System.Collections.Generic.List[object]
$g = 0
foreach ($set in $sets) {
    $g++
    foreach ($x in $set.Extras) {
        $report.Add([pscustomobject][ordered]@{
            Group          = $g
            ExtraCopy      = $x.FullName
            OriginalKeptAt = $set.Keep.FullName
            SizeMB         = [math]::Round($x.Length / 1MB, 1)
            OnlineOnly     = $(if ($x.OnlineOnly) { 'Yes' } else { 'No' })
            HashCheck      = (Get-HashCheck $x $set.Keep)
            Extra          = $x
            Keep           = $set.Keep
        })
    }
}

$wi = $WhatIfPreference; $WhatIfPreference = $false; New-ParentFolder $Out; $WhatIfPreference = $wi
$cols = 'Group', 'ExtraCopy', 'OriginalKeptAt', 'SizeMB', 'OnlineOnly', 'HashCheck'
if ($report.Count -gt 0) {
    $report | Select-Object $cols | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8 -WhatIf:$false
} else {
    ('"' + ($cols -join '","') + '"') | Set-Content -LiteralPath $Out -Encoding UTF8 -WhatIf:$false
}
$dupGB = [math]::Round((($report | ForEach-Object { $_.Extra.Length } | Measure-Object -Sum).Sum) / 1GB, 2)
Write-Host ("Found {0} extra copies in {1} duplicate sets, about {2} GB." -f $report.Count, $sets.Count, $dupGB)
Write-Host "Report: $Out"

if (-not $staging) {
    Write-Host "Report only. Nothing was moved or deleted. Add -StageTo <folder> to stage extra copies."
    return
}

# ---- Opt-in staging: move with a log, never delete ----
if (-not $WhatIfPreference) { New-ParentFolder $LogPath }
$moved = 0; $skipped = 0; $rehearsed = 0
foreach ($r in $report) {
    $x = $r.Extra
    $result = $null
    $dest = ''
    if ($r.HashCheck -eq 'Mismatch') { $result = 'Skipped (hash mismatch)' }
    elseif ($x.OnlineOnly -and -not $IncludeOnlineOnly) { $result = 'Skipped (online-only)' }
    elseif (-not (Test-Path -LiteralPath $r.Keep.FullName)) { $result = 'Skipped (original missing)' }
    elseif (-not (Test-Path -LiteralPath $x.FullName)) { $result = 'Skipped (file missing)' }
    elseif ((Get-Item -LiteralPath $x.FullName -Force).Length -ne $x.RealLength) { $result = 'Skipped (size changed)' }
    else {
        $rel  = Get-RelativePath $x.FullName $rootFull
        $dest = [IO.Path]::Combine($stageFull, $rel)
        $n = 2
        while (Test-Path -LiteralPath $dest) {
            $dir  = [IO.Path]::GetDirectoryName([IO.Path]::Combine($stageFull, $rel))
            $dest = [IO.Path]::Combine($dir, ('{0} [staged {1}]{2}' -f [IO.Path]::GetFileNameWithoutExtension($rel), $n, [IO.Path]::GetExtension($rel)))
            $n++
        }
        if ($PSCmdlet.ShouldProcess($x.FullName, "Move to $dest")) {
            try {
                New-ParentFolder $dest
                Move-Item -LiteralPath $x.FullName -Destination $dest
                $result = 'Moved'
            } catch {
                $result = 'Failed: ' + $_.Exception.Message
            }
        } else {
            $result = 'WhatIf (not moved)'
        }
    }
    if ($result -eq 'Moved') { $moved++ } elseif ($result -eq 'WhatIf (not moved)') { $rehearsed++ } else { $skipped++ }

    if ($result -ne 'WhatIf (not moved)') {
        [pscustomobject][ordered]@{
            OriginalLocation = $x.FullName
            NowAt            = $(if ($result -eq 'Moved') { $dest } else { $x.FullName })
            OriginalKeptAt   = $r.Keep.FullName
            SizeMB           = $r.SizeMB
            Result           = $result
        } | Export-Csv -LiteralPath $LogPath -NoTypeInformation -Encoding UTF8 -Append
    } else {
        Write-Host "  would move: $($x.FullName)"
    }
}

if ($rehearsed -gt 0) { Write-Host ("WhatIf: {0} files would be staged. Nothing was moved." -f $rehearsed) }
Write-Host ("Staged {0} files, skipped {1}. Nothing was deleted." -f $moved, $skipped)
if (Test-Path -LiteralPath $LogPath) {
    Write-Host "Move log: $LogPath"
    Write-Host "To undo: .\Restore-StagedFiles.ps1 -LogPath `"$LogPath`""
}
