# Final validation 0.22.2

Build 58. A scan on a Mac with about 600 known folders and hundreds of Codex worktrees reported 258 folders as "Part of it couldn't be read". 255 failed with EMFILE, "Too many open files"; the other 3 were time limits.

## Cause

`runGit` read git's output through a Pipe, and scheduled two timeout timers that captured the Process strongly for 10 and 12 seconds. The Process kept its Pipe, so both ends stayed open until the timers fired. Backup checks run git about 20 times per checkout, in parallel, so open pipes climbed into the hundreds; the running app was seen holding 780. Folder reads then failed with EMFILE, and so did saving the look inside Everything else.

## What changed

| Before | After |
|---|---|
| Pipes stayed open until the timeout timers fired | `readAll` closes the read end once git's output is read, and the timers hold the Process weakly. lsof and simctl reads close their pipes the same way |
| The app ran with the default limit on open files | At launch the soft limit is raised to 4,096 (within the hard limit) |
| The automatic look inside Everything else could start during a scan | It waits until no scan is running |
| Repeated terminal prompts were unexplained | Settings › Terminal says Full Disk Access for the terminal stops them |

## Evidence

| Check | Result |
|---|---|
| 200 git reads from background threads, as the app makes them | Before: 402 pipes open right after, 14 still open 14 s later. After: 2 and 2, the same as before the reads |
| 50 git reads and an lsof capture | Before: 103 pipes. After: 2 |
| Regression check | 60 git reads at once leave no pipe open (ScanLimit tests) |
| Compiler | No warnings, no errors |
| Test suites | 382 checks pass, 1 new |
