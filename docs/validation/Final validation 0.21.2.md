# Final validation 0.21.2

Build 49, from source 2c70069. A second security and reliability pass, after [0.21.1](Final%20validation%200.21.1.md).

## Found and fixed

| Problem in 0.21.1 | How it was shown | Fix |
|---|---|---|
| The copy-time check for changes read only a folder's own date and what's directly inside, so writes deeper down went unnoticed | Reading the code; a test writes a file three levels down after the scan | Reads the whole folder in batches, like a scan, within 200,000 entries or 4 seconds; Finder's .DS_Store doesn't count |
| Projects from Everything else had no date to compare and no git recheck when copied | Reading the code | Their newest change is passed in, and git's backed-up test runs again before copying |
| An item with no date from the scan skipped the change check | Reading the code | Counts as changed |
| If the open-files snapshot failed, the open check was silently skipped | Reading the code | Nothing is copied; the footer says open files couldn't be checked |
| `git worktree prune` ran in whatever folder a worktree's .git file named | Reading the code | Only a real repository inside your home folder, with fsmonitor and hooks off |
| Every scan saved every open file in every folder: 10 MB a scan, 126 MB after ten days, all read at each launch | Measured on this Mac: 88% of a scan file, 20,726 entries for one simulator folder | Saved as one line per app and item inside. Older scans are compacted as they load, in parallel; files on disk are unchanged |

## Evidence

| Check | Result |
|---|---|
| Test suites | 365 checks pass: Core 30, Detail 46, ScanLimit 28, Planner 21, Discovery 80, Overview 160. New: untouched folder ready; a .DS_Store deep down isn't a change; a file written three levels down is; no date means changed; 5,000 open files compact to 12 lines; the prune step |
| List files | A NUL-separated list with spaces, quotes and newlines is read item for item by zsh and bash |
| Loading this Mac's 37 saved scans | 0.85 s in all; open-file lines held in memory 427,478 → 57,535 |
| Demo app, hardened runtime | Select All under Nothing lost, then Copy: 5 of 7 copied, 2 left out as changed deep inside (the shallow check had passed one of them). The command parses in zsh and bash. Clipboard restored |
| Real app | Installed, launched, all 37 scans loaded, Free Up Space filled; no command copied, nothing moved |

## Limits

- A command checks for open files when you copy, not when you run it. It works for an hour.
- Not notarized; no open-source license has been chosen.
