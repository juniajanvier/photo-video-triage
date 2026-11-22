# TriageCommon.ps1
# Shared helpers for the photo-video-triage scripts. Dot-source this file; do not run it directly.
# Windows PowerShell 5.1 compatible. Read-only: nothing in this file moves, renames or deletes files.

$script:VideoExtensions = @('.mov', '.mp4', '.m4v', '.avi', '.3gp', '.mkv', '.mts', '.wmv')
$script:SkipExtensions  = @('.lnk', '.ini', '.db', '.tmp')

# Windows file attribute bits that mean "the bytes are in the cloud, not on this disk".
# Reading the file (hashing, thumbnailing, copying) would force a download.
$script:AttrOffline             = 0x1000
$script:AttrRecallOnOpen        = 0x40000
$script:AttrRecallOnDataAccess  = 0x400000

function Import-SizeMap {
    <#
    Loads an optional CSV of RelativePath,SizeBytes so the demo library can pretend
    tiny placeholder files are multi-gigabyte videos. Paths are relative to -Root.
    Returns a hashtable keyed by lower-case full path.
    #>
    param(
        [string]$Path,
        [string]$Root
    )
    $map = @{}
    if ([string]::IsNullOrEmpty($Path)) { return $map }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Size map not found: $Path" }
    $rootFull = [IO.Path]::GetFullPath($Root)
    foreach ($row in (Import-Csv -LiteralPath $Path)) {
        $full = [IO.Path]::GetFullPath([IO.Path]::Combine($rootFull, $row.RelativePath))
        $map[$full.ToLowerInvariant()] = [int64]$row.SizeBytes
    }
    return $map
}

function Get-FullPathWithSlash {
    param([string]$Path)
    return ([IO.Path]::GetFullPath($Path).TrimEnd('\') + '\')
}

function Test-IsUnder {
    param([string]$Path, [string]$Parent)
    $p = Get-FullPathWithSlash $Path
    $q = Get-FullPathWithSlash $Parent
    return $p.StartsWith($q, [StringComparison]::OrdinalIgnoreCase)
}

function Get-MediaInventory {
    <#
    Lists every file under -Root once and returns lightweight objects.
    Uses only file-system metadata (name, size, timestamps, attributes), so it never
    opens a file and never triggers a cloud download.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string[]]$Exclude = @(),
        [hashtable]$SizeMap = @{}
    )
    $rootFull = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "Root folder not found: $rootFull" }
    $excl = @($Exclude | Where-Object { -not [string]::IsNullOrEmpty($_) } | ForEach-Object { Get-FullPathWithSlash $_ })

    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $f = $_
        $skip = $script:SkipExtensions -contains $f.Extension.ToLowerInvariant()
        if (-not $skip) {
            foreach ($e in $excl) {
                if ($f.FullName.StartsWith($e, [StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break }
            }
        }
        if (-not $skip) {
            $len = [int64]$f.Length
            $key = $f.FullName.ToLowerInvariant()
            if ($SizeMap.ContainsKey($key)) { $len = [int64]$SizeMap[$key] }

            # "Filmed" = the earlier of created and modified. Copies often reset the created
            # time to the copy date while keeping the original modified time.
            $filmed = $f.CreationTime
            if ($f.LastWriteTime -lt $filmed) { $filmed = $f.LastWriteTime }

            $attr = [int64]$f.Attributes
            $online = (($attr -band $script:AttrOffline) -ne 0) -or
                      (($attr -band $script:AttrRecallOnOpen) -ne 0) -or
                      (($attr -band $script:AttrRecallOnDataAccess) -ne 0)

            $ext = $f.Extension.ToLowerInvariant()
            [pscustomobject]@{
                FullName     = $f.FullName
                Name         = $f.Name
                BaseName     = $f.BaseName
                Extension    = $ext
                Directory    = $f.DirectoryName
                Length       = $len
                RealLength   = [int64]$f.Length
                Filmed       = $filmed
                OnlineOnly   = $online
                IsVideo      = ($script:VideoExtensions -contains $ext)
            }
        }
    }
}

function Get-DuplicateSets {
    <#
    Groups files that share the same base name (ignoring a trailing " (1)", " (2)" ...),
    the same extension and the same byte size. The copy with the shortest name (then the
    oldest, then alphabetical path) is treated as the original to keep.
    #>
    param([object[]]$Items)
    $Items | Where-Object { $_.Length -gt 0 } |
        Group-Object { ($_.BaseName -replace '\s*\(\d+\)$', '').ToLowerInvariant() + $_.Extension + '|' + $_.Length } |
        Where-Object { $_.Count -gt 1 } |
        ForEach-Object {
            $g = @($_.Group | Sort-Object @{ Expression = { $_.BaseName.Length } }, Filmed, FullName)
            [pscustomobject]@{
                Key    = $_.Name
                Keep   = $g[0]
                Extras = @($g | Select-Object -Skip 1)
            }
        }
}

function Get-RelativePath {
    param([string]$Path, [string]$Root)
    $r = Get-FullPathWithSlash $Root
    $p = [IO.Path]::GetFullPath($Path)
    if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $p.Substring($r.Length) }
    return [IO.Path]::GetFileName($p)
}

function New-ParentFolder {
    param([string]$FilePath)
    $dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($FilePath))
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
}
