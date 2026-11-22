<#
.SYNOPSIS
    Undoes Find-Duplicates.ps1 -StageTo by moving every staged file back where it came from.

.DESCRIPTION
    Reads the move log (OriginalLocation, NowAt, OriginalKeptAt, SizeMB, Result). For every row
    with Result = Moved, moves NowAt back to OriginalLocation. Never overwrites: if something
    already sits at the original location, that row is skipped and reported.
    Writes restore-log.csv next to the move log. Supports -WhatIf.

.PARAMETER LogPath
    The move-log.csv written by Find-Duplicates.ps1.

.EXAMPLE
    .\Restore-StagedFiles.ps1 -LogPath D:\_to_delete\move-log.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
. ([IO.Path]::Combine($PSScriptRoot, 'TriageCommon.ps1'))

if (-not (Test-Path -LiteralPath $LogPath)) { throw "Move log not found: $LogPath" }
$restoreLog = [IO.Path]::Combine([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LogPath)), 'restore-log.csv')

$ok = 0; $skip = 0
foreach ($row in @(Import-Csv -LiteralPath $LogPath | Where-Object { $_.Result -eq 'Moved' })) {
    $result = $null
    if (-not (Test-Path -LiteralPath $row.NowAt)) { $result = 'Skipped (staged file not found)' }
    elseif (Test-Path -LiteralPath $row.OriginalLocation) { $result = 'Skipped (something already at original location)' }
    elseif ($PSCmdlet.ShouldProcess($row.NowAt, "Move back to $($row.OriginalLocation)")) {
        try {
            New-ParentFolder $row.OriginalLocation
            Move-Item -LiteralPath $row.NowAt -Destination $row.OriginalLocation
            $result = 'Restored'
        } catch {
            $result = 'Failed: ' + $_.Exception.Message
        }
    } else {
        Write-Host "  would restore: $($row.OriginalLocation)"
        continue
    }
    if ($result -eq 'Restored') { $ok++ } else { $skip++ }
    [pscustomobject][ordered]@{
        StagedAt   = $row.NowAt
        RestoredTo = $row.OriginalLocation
        Result     = $result
    } | Export-Csv -LiteralPath $restoreLog -NoTypeInformation -Encoding UTF8 -Append
}

Write-Host ("Restored {0} files, skipped {1}." -f $ok, $skip)
if (Test-Path -LiteralPath $restoreLog) { Write-Host "Restore log: $restoreLog" }
