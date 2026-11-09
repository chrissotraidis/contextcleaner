# Windows validation 0.1.0

The first Windows version, checked on the Windows PC it was built for: Windows 11 Pro build 26300, a 952 GB C: drive with 42 GB free at the start, a 14.6 TB D: and a 1.8 TB E:, 125% display scaling, dark mode with a red accent. It runs on the Windows PowerShell 5.1 that comes with Windows; PowerShell 7 was not installed (the only pwsh on the machine belonged to Codex).

## What filled the drive

| Part | Size | Answer |
|---|---|---|
| Four older Windows builds of a project in `C:\src` | 79 GB | Safe to remove (newer build exists; each release's zip is on GitHub) |
| Newest build | 21 GB | Rebuildable |
| Ubuntu's WSL disk | 84 GB, then 110 GB as a Linux build ran | Not for the Recycle Bin; Look Inside showed a 27 GB build inside |
| Old Codex runtimes, pnpm caches, old Temp items | 4 GB | Safe to remove |
| Steam games | 517 GB | Not for the Recycle Bin; D: had room to move them |

Two cleanups from Free Up Space's command moved 14 items, 77.6 GB, to the Recycle Bin. The bin holds at most 49.6 GB here, so they ran as two batches with the bin emptied in between; the command's overflow warning is why. History recorded both.

## Found while testing, and fixed

| Problem | Fix |
|---|---|
| The first port needed PowerShell 7, which a fresh Windows doesn't have | Runs on Windows PowerShell 5.1; the C# part uses only .NET Framework 4.8 APIs, with Win32 file enumeration |
| A game image hardlinked into seven builds was counted in each | Big files with more than one name count as shared, named on the card, and left out of what removing a folder frees |
| A first hardlink check read the wrong structure and shrank the drive total from 883 GB to 310 GB | The structure matches BY_HANDLE_FILE_INFORMATION; a test hardlinks a 9 MB file and checks it |
| Checkboxes didn't redraw after Select All or Select None | Grids get the typed items, so their change notifications reach the window |
| A `DOCUME`1` short name, a junction on the path or brackets in a name could get past the path check | Long names, any link on the path, and plain-text comparisons; 22 path cases in the tests |
| Tracking `C:\Program Files (x86)` would have let a command move installed programs | Tracking counts only inside your home folder |
| `.ps1` files without a byte-order mark showed "Â·" for "·" | Every script is UTF-8 with BOM; a test checks |
| At 125% scaling the window was taller than the screen and hid its title bar | The window fits the work area |
| Windows PowerShell wrote an empty list as `{}` and an empty `$(if …)` as `{}`, which read back as a blank path or a bad date | Lists are saved as string arrays, every `$(if)` that feeds JSON has an else, and the date reader treats anything else as no date |
| Git's warning about a folder another account owns stopped a scan, because Windows PowerShell treats a native program's stderr as an error | Git and wsl run with errors continuing; a test calls git on a non-repository with errors set to stop |
| A quick second scan hid what grew today | Growth is measured against the newest scan at least 6 hours old |
| An empty folder had no date, so it could never be offered | The folder's own date counts |

## Checks

| Check | Result |
|---|---|
| `windows\Tests\Run-Tests.ps1` on Windows PowerShell 5.1.26100 | 81 checks, 0 failed |
| The same on PowerShell 7.6.9 | 81 checks, 0 failed |
| Full scan in the window, and `-Scan` from the command line | 27 to 49 s for 3,950 folders and about 600,000 files; the window stays responsive and shows progress; Stop works |
| Every page in dark and light mode | Overview, Free Up Space, Folders, Watchlist, Ignored, Couldn't Scan, History, Settings; Mica and the title bar follow the theme, and switching in Settings or in Windows applies at once |
| Free Up Space | Untouched for, the three chips, By kind with a tick box per group, Select all, Clear; Copy Command asks in the window for Review first items, then copies one line naming only a plan file |
| Move command | Moves an unchanged item; leaves one changed since the scan, a junction, Documents and anything already gone; does nothing an hour later; -WhatIf moves nothing; a 5,000-file 488 MB folder moved in 4.6 s and freed exactly 488 MB once removed from the bin |
| Right-click menu, Watch, Ignore, Stop Ignoring, Track, search, sort | Each saves at once and the lists follow |
| Look Inside on the Ubuntu disk | Runs in the background; listed the biggest folders inside Linux |
| Settings toggles | Scan once a day created a Task Scheduler task running Windows PowerShell with `-Scan`, next run 12:30 PM, and removed it; the Start menu shortcut used the icon and a hidden window, and was removed |

## Second parity round

Driven through UI Automation on the real data, at full width and at 1,100 px.

| Found | Fix |
|---|---|
| The window took 6.5 s to appear, mostly compiling the C# helper, finding project folders twice and reading every saved scan first | The compiled helper is cached, project folders are found once per run, and the last scan loads after the window shows: 3.0 to 3.7 s to a window, about 4 s to data |
| At 1,100 to 1,300 px the title collided with the free-space meter, Free Up Space's header overlapped, and Folders' count and sort bar broke apart | Columns, the card and the toolbar shrink with the window; below 1,150 px the sidebar collapses to icons with tooltips |
| Missing next to the Mac: several folders at once, Scan Again, Scan These Again, Remind Me Tomorrow, Its Growth Is Normal, notes, back and forward, window placement, taskbar progress, high contrast, screen-reader names | Added; each was exercised in the window (a note saved and found by search, a reminder set and cleared, three folders copied as one command, Back across three pages, a scan stopped) |
| A crash in an event handler only reached a generic log line | Every handler runs through one wrapper that logs the line that failed |
| `$Item.Snoozed.Value` was null in PowerShell, which unwraps nullable dates | Fixed and searched for elsewhere |
| PowerShell 7 read reminder dates from JSON as dates and dropped them | Both forms are read as text; tests on both versions cover it |

87 checks pass on Windows PowerShell 5.1 and PowerShell 7.6.

## Not checked

Windows 10, a non-English Windows, high-contrast themes, other display scalings, and the GitHub Actions run (it runs on the pull request). The mover test sends one fixture folder to the Recycle Bin on the runner.

