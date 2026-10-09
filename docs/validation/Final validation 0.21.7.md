# Final validation 0.21.7

Build 54. After 0.21.6, every folder read and git answer was checked for errors that read as "nothing there". Four did.

## What changed

| Before | After |
|---|---|
| `git stash list` or `git worktree list` failing (a 10-second timeout under load) gave 0 stashes or 0 worktrees | Either failing makes the repository "Backup unknown", never offered for the Trash |
| The recheck before copying a command stopped reading a folder at any error and kept the dates read so far | Any read error counts as changed; an iCloud-only part (EDEADLK) doesn't |
| sameFiles skipped folders FileManager couldn't list, and didn't compare folders | It lists each folder itself, stops at the first that can't be read, and compares folders too |
| A folder removed while a scan read it was "Part of it couldn't be read"; one removed whole looked unreadable | Skipped; a folder removed whole is gone |
| Discovery listing an iCloud-only folder, or one just removed, noted an error | An empty listing |

## Evidence

| Check | Result |
|---|---|
| Saved scans on this Mac | Every unreadable folder in 40 scans traced: 10 interrupted calls, all from scans before 0.11.1 added retries; 3 folders removed mid-scan (fixed here); 2 iCloud-only (fixed in 0.21.6). All 54 folders marked gone are gone |
| Saved cleanups | 25 cleanups: every item left out was already gone (286) or changed (49); the 4 "still in place" were in commands that expired unrun |
| Real repositories | Three repositories and three Codex worktrees read with the new code: counts of stashes, worktrees, unpushed commits and changes match git |
| Compiler | No warnings, no errors |
| Test suites | 371 checks pass, one new: copies match only when every folder was read and matches, empty ones included |
