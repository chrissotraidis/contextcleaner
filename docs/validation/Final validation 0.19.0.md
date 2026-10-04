# Final validation 0.19.0

Build 44.

## What changed

- **Whole Codex worktrees.** `~/.codex/worktrees/*` and `~/.codex/tasks/*` are measured whole, plus the build, generated and work folders of the repository inside, including worktrees wrapped as `name/repo/.git`. Git (read-only) decides a worktree's answer: Rebuildable or Safe (after 7 days) only with nothing uncommitted or untracked, its commits on a branch of its repository or pushed, no other worktree depending on it, and no ignored item except build output, caches, or exact copies of the main checkout's (same files, same sizes). The Trash command runs `git worktree prune` for those repositories after the moves, and Copy re-runs `git status` on each clean worktree first.
- **Temporary folder.** `$TMPDIR` is a scanned place. Its items are listed as Safe after 3 days untouched, Might hold work before; items an app holds open are left out, and macOS's private items inside are skipped.
- **No downloads while reading.** The app turns off materialization of dataless (cloud) files and autofs triggers for its own process.
- **~/Documents/Codex** is measured folder by folder; an older whole size of it is set aside.
- **Biggest items kept.** Each measured folder keeps its 512 biggest top-level items (was: first 512 by name).
- **Counting.** "You can get back" credits each byte to the innermost scanned folder. "Where the space went" counts removed folders as freed in their own place when the range reaches now, and a folder first measured after a past range no longer hides the folders inside it.
- **Stale rows.** Listed and ticked paths are checked every 10 seconds and when the app becomes active; gone ones leave the list.

## Evidence

| Check | Result |
|---|---|
| Test suites | 323 checks pass (Core 28, Detail 36, ScanLimit 28, Planner 19, Discovery 74, Overview 138) |
| Trash command with prune, disposable disk image, zsh | Moved two worktrees (one name with a space and an apostrophe); `git worktree list` then showed only the main checkout; both branches kept |
| Real data, read-only harness | 157 worktree, task and temporary folders measured in 34 s; git read for 99 of 106 worktree folders in 9 s more. At 1 day untouched: 175 items, 269.81 GiB (Safe 37.98, Rebuildable 146.02, Might hold work 85.82) |
| Real app, full scan | 423 folders in 3 min 46 s (previous full scan: 10 min 15 s, with ~/Documents/Codex stalled and unmeasured); 414 measured, 9 gone, none limited or unreadable. At 1 day untouched: 188 items, 303.26 GiB (Safe 37.98, Rebuildable 148.53, Might hold work 116.75) |
| Real app, copy | Ticked one clean worktree and one temporary trace: "Copied all 2"; the command passed `zsh -n` and `bash -n` and ended with `git worktree prune` for that worktree's repository. It was not run. |
| Ignored items in worktrees | Of 35 clean worktrees holding ignored items git doesn't keep, 2 became clean through the exact-copy check; the rest hold inputs that differ from the main checkout's and stay Might hold work |

## Limits

- A worktree's answer comes from the git read after a scan; until it finishes (about a minute here), worktrees say "Checking git…" and aren't listed whole.
- The exact-copy check compares names and sizes, not contents.
- Nothing on this Mac's disk was moved during this work; moves happened on a disposable disk image.

## Follow-up

An end-to-end check found that the git recheck before copying covered uncommitted and untracked files but not new files inside ignored folders. Fixed in 0.19.1; see its validation record.
