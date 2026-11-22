<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/brand/banner-dark.svg">
  <img src=".github/brand/banner-light.svg" width="100%" alt="Photo & Video Triage: Triage a huge photo and video library without moving or deleting a single file.">
</picture>

<img src="https://img.shields.io/badge/status-live-7CC142?style=for-the-badge&labelColor=2A1A0E&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI0M0NjM3QSIgZD0iTTEyIDFsMi42IDguNEwyMyAxMmwtOC40IDIuNkwxMiAyM2wtMi42LTguNEwxIDEybDguNC0yLjZ6Ii8+PC9zdmc+" alt="Status: live">

<img src="https://img.shields.io/badge/PowerShell-2A1A0E?style=for-the-badge&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iIzUzOTFGRSIgZD0iTTQuNiAzaDE4LjJjLjggMCAxLjMuNyAxLjEgMS40bC0zLjQgMTUuMmMtLjIuOC0uOSAxLjQtMS43IDEuNEguNmMtLjggMC0xLjMtLjctMS4xLTEuNEwzIDQuNEMzLjEgMy42IDMuOCAzIDQuNiAzeiIvPjxwYXRoIGZpbGw9IiNGREY4RjQiIGQ9Ik02LjIgNy4ybDYuMiA0LjYtNy42IDUgLjktMS42IDQuNi0zLjItNC41LTMuMnpNMTIgMTUuNmg1LjJsLS40IDEuNmgtNS4yeiIvPjwvc3ZnPg==" alt="PowerShell">
<img src="https://img.shields.io/badge/Windows-2A1A0E?style=for-the-badge&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iIzNDQThGMiIgZD0iTTEgMy41bDktMS4yVjExSDF6TTExLjIgMi4xTDIzIC41VjExSDExLjJ6TTEgMTIuMmg5djguN2wtOS0xLjN6TTExLjIgMTIuMkgyM3YxMS4zbC0xMS44LTEuNnoiLz48L3N2Zz4=" alt="Windows">
<img src="https://img.shields.io/badge/Claude-2A1A0E?style=for-the-badge&logo=claude&logoColor=D97757" alt="Claude">

<br>

</div>

Safety-first PowerShell tools for sorting out a huge cloud-synced photo and video library on Windows, without moving or deleting a single file until a person has decided.

Designed and product-managed by Junia Janvier, built in partnership with Claude (Anthropic).

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## The problem

A Windows 11 PC running iCloud for Windows was syncing well over a terabyte of photos and videos. Most of the library was "online-only": the files show up in File Explorer, but the bytes live in the cloud until something opens them.

That setup creates three traps:

1. **Deleting is global.** Removing a file from the synced iCloud Photos folder deletes it from iCloud and from every device. There is no "just this PC."
2. **Looking is expensive.** File Explorer generates thumbnails by reading files, so simply browsing a folder of online-only videos can start downloading hundreds of gigabytes.
3. **The big wins are hidden.** A handful of long videos and a pile of duplicate copies were taking up a large share of the space, but nothing in the default tools surfaces them by size, by day or by duplicate.

The goal was a triage workflow that answers "what is taking up the space, and what should go?" while guaranteeing that nothing changes until a human makes the call in the Photos app.

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## Safety principles

**Nothing moves, nothing deletes.** Every script follows these rules:

| Principle | How it is enforced |
|---|---|
| Read metadata, never content | Scans use names, sizes, timestamps and attributes only. No file is opened, so no cloud download is triggered. |
| Review through shortcuts, never copies | Review folders contain Windows `.lnk` shortcuts. Deleting a shortcut deletes nothing. |
| No delete operation anywhere | There is no delete call in this repo. Final deletion happens in the Photos app, by a person. |
| Staging is opt-in and reversible | `Find-Duplicates.ps1` is report-only by default. With `-StageTo` it moves extra copies into a holding folder, writes a move log, and `Restore-StagedFiles.ps1` puts everything back. |
| Online-only files are protected | Staging skips cloud placeholders unless `-IncludeOnlineOnly` is set. |
| Rehearse first | Every move supports `-WhatIf` and `-Confirm`. A demo library lets anyone run the full pipeline on fake files. |

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## What it produces

| Script | Output |
|---|---|
| `scripts/Find-BigVideos.ps1` | CSV of every video over a threshold (default 1 GB): rank, file name, filmed date, time, size in GB, an empty `Decision` column, and an online-only flag. Ready to import as a Google Sheet. |
| `scripts/New-ReviewFolders.ps1` | A review folder tree made only of shortcuts, plus a `READ ME FIRST.txt`. |
| `scripts/Find-Duplicates.ps1` | Duplicate report CSV. Optional staging with a move log. |
| `scripts/Restore-StagedFiles.ps1` | Moves staged files back using the move log, and writes a restore log. |
| `docs/google-sheet-setup.md` | Step-by-step review sheet: Decision dropdown, pink and green rows, a "By day" rollup with `QUERY`, and running totals. |

Review folder layout (all names are generic examples):

```
Photo Review\
  READ ME FIRST.txt
  01 Videos over 1 GB\
    001 - 8.6 GB - 2024-11-28 - VID_0201.MP4.lnk
    002 - 4.2 GB - 2024-07-04 - IMG_0101.MOV.lnk
  02 Videos 250 MB to 1 GB\
    2023\2023-08-02 - 310 MB - IMG_0111.MOV.lnk
  03 Screenshots\
    2024\2024-09-01 - Screenshot_0003.png.lnk
  04 Exact duplicates (extra copies)\
    IMG_0101 (1).MOV - copy of IMG_0101.MOV.lnk
```

Every shortcut carries an explicit icon from `imageres.dll`, so File Explorer draws a generic video or picture icon instead of downloading the file to render a thumbnail.

The duplicate move log has one row per file:

| OriginalLocation | NowAt | OriginalKeptAt | SizeMB | Result |
|---|---|---|---|---|
| `...\Old Phone Backup\IMG_0101 (1).MOV` | `...\_staged\Old Phone Backup\IMG_0101 (1).MOV` | `...\Camera Roll\2024\IMG_0101.MOV` | 4300.8 | Moved |

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## How to run

Requirements: Windows 10 or 11, Windows PowerShell 5.1 (built in) or PowerShell 7.

### Try the demo first

The demo builds a fake library of 20 tiny placeholder files, records pretend sizes (up to 8.6 GB) in a CSV, and runs every script against it, including staging and restoring.

```powershell
cd photo-video-triage
powershell -ExecutionPolicy Bypass -File .\samples\Invoke-Demo.ps1
```

Expected summary lines:

```
Found 7 videos over 1 GB, 24.3 GB in total.
big=7 medium=5 screenshots=3 duplicates=4 duplicateGB=7.1 shortcuts=19 errors=0
Found 4 extra copies in 4 duplicate sets, about 7.13 GB.
Staged 4 files, skipped 0. Nothing was deleted.
Restored 4 files, skipped 0.
Files back in the library: 20
```

The demo also includes a same-name file with a different size, which is correctly left out of the duplicate list.

### Run on a real library

Point `-Root` at the folder to triage. For iCloud for Windows this is usually under `$HOME\Pictures\iCloud Photos\Photos`; check the iCloud app for the actual location.

```powershell
$root = "$HOME\Pictures\iCloud Photos\Photos"

# 1. Big videos to a CSV for the review sheet
.\scripts\Find-BigVideos.ps1 -Root $root -Out "$HOME\Desktop\videos-over-1-GB.csv"

# 2. Shortcut-only review folders
.\scripts\New-ReviewFolders.ps1 -Root $root -Out "$HOME\Pictures\Photo Review"

# 3. Duplicate report (report only)
.\scripts\Find-Duplicates.ps1 -Root $root -Out "$HOME\Desktop\duplicate-report.csv"
```

Thresholds are parameters: `-MinSizeGB` on `Find-BigVideos.ps1`; `-BigThresholdGB`, `-MediumThresholdMB` and `-ScreenshotExtensions` on `New-ReviewFolders.ps1`; `-MinSizeMB` on `Find-Duplicates.ps1`.

Large libraries take time. Building 5,000+ shortcuts can run longer than 10 minutes; progress prints every 250 shortcuts.

### Optional: stage duplicate copies

Use this for extra copies that live **outside** the synced library, such as old phone backups, exports or download folders. Moving a file out of a synced folder counts as removing it from the cloud.

```powershell
# Rehearse
.\scripts\Find-Duplicates.ps1 -Root D:\OldBackups -StageTo D:\_to_delete -VerifyHash -WhatIf

# Stage for real (move + log)
.\scripts\Find-Duplicates.ps1 -Root D:\OldBackups -StageTo D:\_to_delete -VerifyHash

# Changed your mind? Put everything back
.\scripts\Restore-StagedFiles.ps1 -LogPath D:\_to_delete\move-log.csv
```

Empty the staging folder by hand only after reviewing the move log.

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## Design decisions

| Decision | Why |
|---|---|
| Shortcuts instead of copies or moves | Copies would double storage and force downloads. Moves inside a synced library ripple to every device. Shortcuts cost a few hundred bytes and change nothing. |
| Explicit `IconLocation` on every shortcut | Without it, Explorer asks the target for a thumbnail, which downloads online-only videos just to draw an icon. |
| Metadata-only scanning | Reading size and timestamps from the file system never opens a file, so a full scan of a cloud library downloads nothing. |
| "Filmed on" = earlier of created and modified | Copies often reset the created date to the day of the copy. The earlier timestamp is a better guess at when the clip was filmed. |
| Duplicate = same base name (ignoring ` (1)`) + extension + byte size | Cheap, metadata-only, and catches the common case of re-imported or re-downloaded copies. `-VerifyHash` adds a SHA-256 check for files that are on disk. |
| Report-only by default, staging opt-in | The safe path should be the default path. Staging requires a deliberate flag and writes a log a person can audit. |
| Move log written row by row | Each row is appended right after its move, so an interrupted run still leaves an accurate record for `Restore-StagedFiles.ps1`. |
| Never overwrite on stage or restore | Name collisions get a `[staged 2]` suffix on stage and are skipped on restore, so no file can silently replace another. |
| Decisions live in a Google Sheet | A shared sheet with a dropdown lets more than one person weigh in, and the "By day" rollup shows which events hold the most gigabytes. |
| ISO dates (`yyyy-MM-dd`) inside file and shortcut names | They sort correctly in File Explorer. Human-facing text such as the README in the review folder uses month names. |
| `[IO.Path]::Combine` instead of `Join-Path` | `Join-Path` inside a helper function hit positional-parameter binding errors in Windows PowerShell 5.1. |
| Windows PowerShell 5.1 compatible | Runs on any Windows 10 or 11 machine with nothing to install. No ternaries or null-coalescing operators. |
| Demo with a size map instead of large dummy files | The demo shows multi-gigabyte behavior with a few kilobytes on disk. |

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## Repository layout

```
photo-video-triage/
  README.md
  LICENSE
  .gitignore
  docs/
    google-sheet-setup.md
  samples/
    New-DemoLibrary.ps1
    Invoke-Demo.ps1
  scripts/
    TriageCommon.ps1
    Find-BigVideos.ps1
    New-ReviewFolders.ps1
    Find-Duplicates.ps1
    Restore-StagedFiles.ps1
```

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

## License

MIT. See [LICENSE](LICENSE).

<p align="center"><img src=".github/brand/divider.svg" width="100%" alt=""></p>

<p align="center">
  <a href="https://juniajanvier.com"><img src=".github/brand/footer.svg" width="520" alt="Junia Janvier · The Education Alchemist · Providence, RI"></a>
</p>
