<#
.SYNOPSIS
    Builds review folders made only of Windows shortcuts (.lnk) that point at your real files.

.DESCRIPTION
    Nothing is copied, moved or deleted. Each review folder holds shortcuts, so deleting a
    shortcut deletes nothing. Every shortcut gets an explicit icon from imageres.dll, which
    stops File Explorer from downloading online-only cloud files just to draw thumbnails.

    Output layout under -Out:
      01 Videos over 1 GB\                 ranked, biggest first: "001 - 4.2 GB - 2024-07-04 - IMG_0101.MOV"
      02 Videos 250 MB to 1 GB\<year>\     "2023-03-18 - 640 MB - IMG_0110.MOV"
      03 Screenshots\<year>\               "2022-01-09 - Screenshot_0001.png"
      04 Exact duplicates (extra copies)\  "IMG_0101 (1).MOV - copy of IMG_0101.MOV"
      READ ME FIRST.txt

    Large libraries take a while: 5,000+ shortcuts can run longer than 10 minutes.

.PARAMETER Root
    Folder to scan.

.PARAMETER Out
    Where to build the review folders. Defaults to "$HOME\Pictures\Photo Review". It is
    excluded from the scan, and it must not be the same folder as -Root.

.PARAMETER BigThresholdGB
    Lower bound for folder 01. Default 1.

.PARAMETER MediumThresholdMB
    Lower bound for folder 02 (upper bound is BigThresholdGB). Default 250.

.PARAMETER ScreenshotExtensions
    Extensions treated as screenshots. Default .png (phone screenshots are PNG; camera photos are HEIC/JPG).

.PARAMETER SizeMap
    Optional CSV (RelativePath,SizeBytes) that overrides real sizes. Used by the demo library.

.EXAMPLE
    .\New-ReviewFolders.ps1 -Root "$HOME\Pictures\iCloud Photos\Photos"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Out = ([IO.Path]::Combine($HOME, 'Pictures', 'Photo Review')),
    [double]$BigThresholdGB = 1,
    [double]$MediumThresholdMB = 250,
    [string[]]$ScreenshotExtensions = @('.png'),
    [string]$SizeMap
)

$ErrorActionPreference = 'Stop'
. ([IO.Path]::Combine($PSScriptRoot, 'TriageCommon.ps1'))

$rootFull = [IO.Path]::GetFullPath($Root)
$outFull  = [IO.Path]::GetFullPath($Out)
if ((Get-FullPathWithSlash $rootFull) -eq (Get-FullPathWithSlash $outFull)) {
    throw "-Out must be a different folder from -Root."
}

# Explicit icons: Explorer uses these instead of reading the target file for a thumbnail.
$VideoIcon   = '%SystemRoot%\System32\imageres.dll,18'
$PictureIcon = '%SystemRoot%\System32\imageres.dll,67'

$script:Shell  = New-Object -ComObject WScript.Shell
$script:Errors = 0
$script:Made   = 0

function New-ReviewShortcut {
    param([string]$Folder, [string]$Name, [string]$Target, [string]$Icon)
    try {
        # [IO.Path]::Combine instead of Join-Path: Join-Path inside a function hit
        # positional-parameter binding errors in Windows PowerShell 5.1.
        if (-not (Test-Path -LiteralPath $Folder)) { [void](New-Item -ItemType Directory -Path $Folder -Force) }
        $safe = $Name -replace '[\\/:*?"<>|]', '_'
        if ($safe.Length -gt 150) { $safe = $safe.Substring(0, 150) }
        $path = [IO.Path]::Combine($Folder, $safe + '.lnk')
        $n = 2
        while (Test-Path -LiteralPath $path) {
            $path = [IO.Path]::Combine($Folder, ('{0} ({1}).lnk' -f $safe, $n))
            $n++
        }
        $lnk = $script:Shell.CreateShortcut($path)
        $lnk.TargetPath       = $Target
        $lnk.WorkingDirectory = [IO.Path]::GetDirectoryName($Target)
        $lnk.IconLocation     = $Icon
        $lnk.Description      = 'Shortcut only. The original file has not moved.'
        $lnk.Save()
        $script:Made++
        if (($script:Made % 250) -eq 0) { Write-Host "  ...$($script:Made) shortcuts" }
    } catch {
        $script:Errors++
        Write-Warning "Could not create shortcut for $Target : $($_.Exception.Message)"
    }
}

$map = Import-SizeMap -Path $SizeMap -Root $rootFull
Write-Host "Scanning $rootFull (metadata only)..."
$all = @(Get-MediaInventory -Root $rootFull -Exclude @($outFull) -SizeMap $map)
$vid = @($all | Where-Object { $_.IsVideo })
$big = [int64]($BigThresholdGB * 1GB)
$med = [int64]($MediumThresholdMB * 1MB)
$inv = [Globalization.CultureInfo]::InvariantCulture

# 01 Videos over the big threshold, ranked
$f01 = [IO.Path]::Combine($outFull, ('01 Videos over {0} GB' -f $BigThresholdGB))
$i = 0
foreach ($v in @($vid | Where-Object { $_.Length -gt $big } | Sort-Object Length -Descending)) {
    $i++
    $name = '{0:000} - {1} GB - {2} - {3}' -f $i, ($v.Length / 1GB).ToString('0.0', $inv), $v.Filmed.ToString('yyyy-MM-dd', $inv), $v.Name
    New-ReviewShortcut $f01 $name $v.FullName $VideoIcon
}

# 02 Medium videos, by year
$f02 = [IO.Path]::Combine($outFull, ('02 Videos {0} MB to {1} GB' -f $MediumThresholdMB, $BigThresholdGB))
$m = 0
foreach ($v in @($vid | Where-Object { $_.Length -gt $med -and $_.Length -le $big } | Sort-Object Filmed)) {
    $m++
    $name = '{0} - {1:000} MB - {2}' -f $v.Filmed.ToString('yyyy-MM-dd', $inv), [math]::Round($v.Length / 1MB), $v.Name
    New-ReviewShortcut ([IO.Path]::Combine($f02, [string]$v.Filmed.Year)) $name $v.FullName $VideoIcon
}

# 03 Screenshots, by year
$f03 = [IO.Path]::Combine($outFull, '03 Screenshots')
$shotExt = @($ScreenshotExtensions | ForEach-Object { $_.ToLowerInvariant() })
$s = 0
foreach ($p in @($all | Where-Object { $shotExt -contains $_.Extension } | Sort-Object Filmed)) {
    $s++
    $name = '{0} - {1}' -f $p.Filmed.ToString('yyyy-MM-dd', $inv), $p.Name
    New-ReviewShortcut ([IO.Path]::Combine($f03, [string]$p.Filmed.Year)) $name $p.FullName $PictureIcon
}

# 04 Exact duplicates: same base name (ignoring " (1)") + same extension + same size
$f04 = [IO.Path]::Combine($outFull, '04 Exact duplicates (extra copies)')
$d = 0
[int64]$dBytes = 0
foreach ($set in @(Get-DuplicateSets -Items $all)) {
    foreach ($x in $set.Extras) {
        $d++
        $dBytes += $x.Length
        $icon = $PictureIcon
        if ($x.IsVideo) { $icon = $VideoIcon }
        New-ReviewShortcut $f04 ('{0} - copy of {1}' -f $x.Name, $set.Keep.Name) $x.FullName $icon
    }
}

$today = (Get-Date).ToString('MMMM d, yyyy', $inv)
$dupGB = [math]::Round($dBytes / 1GB, 1)
$readme = @"
Photo and Video Review (made $today)

Everything in these folders is a SHORTCUT. Your real photos and videos have not moved.
Deleting a shortcut here deletes nothing.

01 Videos over $BigThresholdGB GB: $i videos, biggest first.
02 Videos $MediumThresholdMB MB to $BigThresholdGB GB: $m videos, by year filmed.
03 Screenshots: $s screenshots, by year.
04 Exact duplicates: $d extra copies (same name and size as another file), about $dupGB GB.

Opening a shortcut may download that one file from the cloud so it can play.

To actually remove something from a cloud photo library (for example iCloud Photos),
delete it in the Photos app on the phone, then empty Recently Deleted. Deleting from a
synced library deletes it on every device, so decide first, delete second.
"@
[void](New-Item -ItemType Directory -Path $outFull -Force)
Set-Content -LiteralPath ([IO.Path]::Combine($outFull, 'READ ME FIRST.txt')) -Value $readme -Encoding UTF8

Write-Host ("big={0} medium={1} screenshots={2} duplicates={3} duplicateGB={4} shortcuts={5} errors={6}" -f $i, $m, $s, $d, $dupGB, $script:Made, $script:Errors)
Write-Host "Review folders: $outFull"
Write-Host "Nothing was moved or deleted."
