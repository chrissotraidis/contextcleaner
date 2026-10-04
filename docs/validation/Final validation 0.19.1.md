# Final validation 0.19.1

Build 45.

## What changed

- Copying a Clean worktree re-reads it with git and applies the same test as its answer (`RepoBackup.keepsEverything`); a worktree that fails is left out as changed since the scan, and git's fresh answer replaces the old one so the row updates.
- "Everything else" wording for ~/.codex and ~/.codex/worktrees.

## Evidence

| Check | Result |
|---|---|
| Test suites | All suites pass, including real-git checks: a fresh worktree with only build output is clean; an ignored `ref/` matching the main checkout is a copy; a new file inside it, or an untracked file, makes the worktree hold something unique; and the copy-time test agrees with the listed answer in every case |
| End to end, demo build, disposable disk image | Real git: a main checkout with four worktrees (clean and 10 days idle, clean and 30 hours idle with a copied `ref/`, one with an uncommitted file, one wrapped one folder down) and three temporary items. A real scan listed: clean-old Safe, clean-recent and wrapped Rebuildable, the dirty one only by its build folder, the 5-day trace Safe, the 30-hour temporary folder Might hold work, the item written just before the scan not at all |
| Copy-time check | After the scan, one file was added two folders deep in clean-recent's ignored `ref/` (its top-level entries unchanged). Select All, Copy: "Copied 5 of 6", clean-recent left out. With 0.19.1, the row then changed to its build folder |
| Running the command | zsh moved all 5; git listed only the remaining worktrees; every branch kept; the uncommitted file and the new file untouched |
| Rows leaving the list | A listed folder moved by hand, outside any command, left Free up space within 12 seconds |

## Limits

- The exact-copy check compares names and sizes, not contents.
- Nothing on this Mac's disk was moved; moves happened on a disposable disk image.
