<#
.SYNOPSIS
    Creates a small fake photo and video library for a safe demo of the triage scripts.

.DESCRIPTION
    Every file is a tiny text placeholder (a few bytes). The sizes the scripts should pretend
    the files have (for example 4.2 GB) are recorded in demo-sizes.csv, which every script
    accepts through -SizeMap. Creation and modified dates are set so the "filmed on" logic
    and year folders have something to work with.

    All file names are generic examples, not from any real library.

    Layout:
      <Path>\library\Camera Roll\2022, 2023, 2024
      <Path>\library\Old Phone Backup          (exact duplicate copies)
      <Path>\library\Exports
      <Path>\demo-sizes.csv

.PARAMETER Path
    Empty or new folder to create the demo in. Defaults to "$env:TEMP\photo-video-triage-demo".
#>
[CmdletBinding()]
param(
    [string]$Path = ([IO.Path]::Combine($env:TEMP, 'photo-video-triage-demo'))
)

$ErrorActionPreference = 'Stop'
$full = [IO.Path]::GetFullPath($Path)
if ((Test-Path -LiteralPath $full) -and @(Get-ChildItem -LiteralPath $full -Force).Count -gt 0) {
    throw "Folder is not empty: $full. Pick a new or empty folder (this script never deletes anything)."
}
$lib = [IO.Path]::Combine($full, 'library')
[void](New-Item -ItemType Directory -Path $lib -Force)

$MB = 1MB; $GB = 1GB
# RelativePath, pretend size in bytes, filmed date/time, content seed (same seed = identical bytes)
$spec = @(
    # Videos over 1 GB
    @('Camera Roll\2024\IMG_0101.MOV',      [int64](4.2 * $GB), '2024-07-04 18:32', 'v0101'),
    @('Camera Roll\2024\IMG_0102.MOV',      [int64](1.6 * $GB), '2024-07-04 20:05', 'v0102'),
    @('Camera Roll\2024\VID_0201.MP4',      [int64](8.6 * $GB), '2024-11-28 15:10', 'v0201'),
    @('Camera Roll\2023\IMG_0103.MOV',      [int64](2.3 * $GB), '2023-12-25 09:41', 'v0103'),
    @('Camera Roll\2022\IMG_0104.MOV',      [int64](1.1 * $GB), '2022-05-14 13:00', 'v0104'),
    # Videos 250 MB to 1 GB
    @('Camera Roll\2024\IMG_0110.MOV',      [int64](640 * $MB), '2024-03-18 11:20', 'v0110'),
    @('Camera Roll\2023\IMG_0111.MOV',      [int64](310 * $MB), '2023-08-02 17:45', 'v0111'),
    @('Camera Roll\2022\IMG_0112.MP4',      [int64](955 * $MB), '2022-10-31 19:15', 'v0112'),
    # Small videos (ignored by the size folders)
    @('Camera Roll\2024\IMG_0120.MOV',      [int64](45 * $MB),  '2024-02-14 08:00', 'v0120'),
    # Photos
    @('Camera Roll\2024\IMG_0001.HEIC',     [int64](3 * $MB),   '2024-07-04 18:30', 'p0001'),
    @('Camera Roll\2024\IMG_0002.HEIC',     [int64](2 * $MB),   '2024-07-04 18:31', 'p0002'),
    @('Camera Roll\2023\IMG_0003.JPG',      [int64](4 * $MB),   '2023-06-10 12:00', 'p0003'),
    # Screenshots
    @('Camera Roll\2022\Screenshot_0001.png', [int64](900KB),   '2022-01-09 10:05', 's0001'),
    @('Camera Roll\2023\Screenshot_0002.png', [int64](1.2 * $MB), '2023-04-22 21:30', 's0002'),
    @('Camera Roll\2024\Screenshot_0003.png', [int64](800KB),   '2024-09-01 07:55', 's0003'),
    # Exact duplicates: same base name (ignoring " (1)") and same size as an original
    @('Old Phone Backup\IMG_0101 (1).MOV',  [int64](4.2 * $GB), '2024-07-04 18:32', 'v0101'),
    @('Old Phone Backup\IMG_0103.MOV',      [int64](2.3 * $GB), '2023-12-25 09:41', 'v0103'),
    @('Old Phone Backup\IMG_0001 (1).HEIC', [int64](3 * $MB),   '2024-07-04 18:30', 'p0001'),
    @('Exports\IMG_0110 (2).MOV',           [int64](640 * $MB), '2024-03-18 11:20', 'v0110'),
    # Same name, DIFFERENT size: must NOT be reported as a duplicate
    @('Exports\IMG_0102 (1).MOV',           [int64](900 * $MB), '2024-07-05 09:00', 'v0102-trimmed')
)

$inv  = [Globalization.CultureInfo]::InvariantCulture
$rows = New-Object System.Collections.Generic.List[object]
foreach ($s in $spec) {
    $file = [IO.Path]::Combine($lib, $s[0])
    $dir  = [IO.Path]::GetDirectoryName($file)
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    [IO.File]::WriteAllText($file, "demo placeholder $($s[3])")
    $when = [datetime]::ParseExact($s[2], 'yyyy-MM-dd HH:mm', $inv)
    [IO.File]::SetCreationTime($file, $when)
    [IO.File]::SetLastWriteTime($file, $when)
    $rows.Add([pscustomobject][ordered]@{ RelativePath = $s[0]; SizeBytes = $s[1] })
}
$sizes = [IO.Path]::Combine($full, 'demo-sizes.csv')
$rows | Export-Csv -LiteralPath $sizes -NoTypeInformation -Encoding UTF8

Write-Host "Demo library: $lib  ($($spec.Count) placeholder files)"
Write-Host "Size map:     $sizes"
