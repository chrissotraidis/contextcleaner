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

## Third pass

A fresh install from the release zip into a folder with spaces (`My Apps\Context Cleaner 0.1.0`), a first run with an empty data folder, keyboard only, and light mode, on the real data and on demo data.

| Found | Fix |
|---|---|
| Before the first scan Overview said the Recycle Bin was empty while it held 39.2 GB, and after a scan the number stayed as the scan left it | The bin's size is asked of Windows (`SHQueryRecycleBin`, about 2 ms) each time Overview or Free Up Space shows and when you come back to the window; a test moves a fixture there and sees it grow |
| A note typed and then left within 0.7 s for another folder was saved with the next folder's text, usually erasing it; closing the window in that moment lost it | The note is kept with the folder it was typed for and saved at once when you pick another folder or close the window; checked by typing and switching in one step |
| After a stopped scan, Scan Again measured 0 B, because the stop flag was still set | Scan Again clears it, and drops its result if a full scan is stopped while it runs; checked on the real data (38.3 GB, as the full scan found) |
| List rows, the answer tiles and Free Up Space's group headers showed no keyboard focus | One focus ring, drawn only when moving with the keyboard |
| The note field used the old square Windows text box | It matches the search box, with a hint |
| Esc was swallowed even with no scan or search to clear | Esc is handled only when it does something |
| On a clean checkout the release build skipped `source-status.txt` | It writes "clean" |

Also checked: the zip unpacks to the eight app files plus LICENSE and opens in about 4 s; the welcome line, empty tiles and Scan prompt on a first run; Ctrl+2 and Ctrl+3, Tab and the arrow keys through tiles and rows, Shift+arrow to select several, Alt+Left and Alt+Right, Ctrl+F and a search that finds a folder by its note; from the folder with spaces, the Start menu shortcut opened the app and the daily task ran its scan (result 0, 18 s), and both were removed again.

88 checks pass on Windows PowerShell 5.1 and PowerShell 7.6.

## Fourth pass: parity with the Mac's rules

Every page on the real data after a fresh 89-second scan, with the Mac README and classifier side by side.

| Found | Fix |
|---|---|
| In a project folder without git, a folder named `out`, `dist`, `target`, `venv` and others counted as build output, so after 7 days it was Safe to remove even if you made it by hand. The Mac trusts those names only when git ignores the folder | `build` and `.cxx` stay output by name; any other build-like name needs the project's git to ignore it, and is otherwise Review first with the reason: not in a git repository, Git isn't installed (with `winget install Git.Git`), or git can't read it. Before, Git missing read "Tracked in git" |
| The Mac lists a big folder git ignores (Not in git, only on this Mac); Windows didn't look | A folder of 500 MB or more that a project's git ignores and isn't build output is Review first, Not in git, only on this PC. The git query took 88 to 131 ms per repository here |
| Overview said 43.2 GB and 12 folders could go with nothing lost and 12.6 GB more was Review first; Free Up Space said 42.2 GB, 9 and 2.8 GB | Overview uses Free Up Space's list and its Untouched for, so both say 42.2 GB, 9 items and 2.8 GB |
| Couldn't Scan cut its count to "3 folder…" next to Scan These Again | The count wraps |
| Before the first scan, Overview's button opened an empty Free Up Space | It says Scan Now and scans |
| The keyboard table in the Windows README broke in two on GitHub | Joined |

The new rules were checked against the real drive: a scan into a separate data folder gave the same answer and reason for all 134 folders as the scan before the change. Tests cover a build folder without git, a `dist` git ignores, an `out` it doesn't, and a Not in git folder found next to an ignored `node_modules` left to its own rule.

93 checks pass on Windows PowerShell 5.1 and PowerShell 7.6.

## Fifth pass: Move to Recycle Bin in the window

Copying a command and pasting it in a terminal was the slowest, least Windows-like step, and a pasted command once failed with a raw PowerShell error ("Cannot find path" for its plan file, which existed and read normally afterwards; not reproduced).

| Change | Checked |
|---|---|
| Free Up Space's main button and each folder's card say Move to Recycle Bin; Delete does the same. A Windows 11 style dialog lists the items with answer and size, flags Review first, warns when the Recycle Bin would overflow (the button then says Move Anyway), and Esc cancels | Opened from the button, from Delete on a selected folder and from several selected; Esc closed it and nothing moved; light and dark |
| Confirming runs the same `Move-ToRecycleBin.ps1` in a hidden process with -Yes and -Log; the dialog shows progress and a line per item, then what moved, what stayed and why, with Open Recycle Bin; History and the lists update | On a fixture project (two 110 MB builds, every other place turned off, a separate data folder): one build moved, its row left the list, the plan's log read `Moved:`, and the fixture was then removed from the Recycle Bin |
| A missing or unreadable plan says so in one line instead of a PowerShell error | Test |
| Copy as Command Instead stays in the … menu (Ctrl+Shift+C); Open Terminal left Free Up Space | Settings explains it |
| Overview opens with what you could get back and the Recycle Bin, above the chart; both cards have their button under the text | Real data and demo data |
| Free Up Space lost its explanation paragraph; the chips explain themselves in tooltips | Screenshot |

95 checks pass on Windows PowerShell 5.1 and PowerShell 7.6. The docs screenshots were retaken from demo data.

## Sixth pass: release review

Security, errors, parity with the Mac's remaining features, and speed, on the real data.

| Area | Found | Fix or result |
|---|---|---|
| Security | A copied command put paths in double quotes; pasted into PowerShell, a dollar sign or backtick in a folder name would be expanded | Paths go in single quotes, with any quote doubled; a test checks |
| Security | Every place the code starts a program, opens a link or moves anything | Fixed arguments only; Steam links take a numeric app id from Steam's manifest; git runs with hooks, fsmonitor and filters off; moves only through the checked script |
| Errors | PSScriptAnalyzer (errors and warnings) | No errors; parameters named like PowerShell's automatic $sender and $EventArgs renamed; the empty catch blocks left are deliberate best-effort reads |
| Errors | Windows PowerShell read the remembered project folders back as one object, which emptied them | Read as a list on both versions; tested on both |
| Parity | The Mac offers what has sat untouched inside a folder still in use; Windows did not | A Temp folder something writes to offers its untouched files (Remote Desktop traces after a day, anything else after 3), only they move, and the folder stays. Checked end to end in the window on a fixture: 2 old files moved, the new one stayed |
| Parity | Games said "untouched 900 days" from file dates | Steam's own last-played date, and Uninstall in Steam on the card |
| Speed | Opening: 3.8 s from start to the last scan on screen in the script, plus PowerShell starting | Project folders remembered, nothing drawn while hidden, the last scan shown before the scan history: the window shows about a second sooner |
| Speed | A scan of about 700,000 files took 70 to 88 s: 3,708 tiny Temp items became places (5 s), Plex's 89,791 folders were walked by one core (18 s), and the in-use check ran a PowerShell function 34,000 times (2 s) | Temp sized in one pass, every core works from one list of folders, a plain loop for the in-use check: 23 s in the window. The new measuring matched the old for every place but the five that changed during the comparison |

On the real drive, a scan with these changes gave the same answers as before except the ones meant to change: 68 games now say when they were last played, and the Remote Desktop trace folder is Safe to remove for its 354 old files. 101 checks pass on Windows PowerShell 5.1 and PowerShell 7.6.

## Not checked

Windows 10, a non-English Windows, high-contrast themes, other display scalings, and a Recycle Bin with thousands of items (the size query reads each one). The mover test sends one fixture folder to the Recycle Bin on the runner.

