# Final validation 0.17.0

Build 36, from the 0.17 goal loop (docs/GOAL_LOOP_0.17.md). Built on Sep 30, 2026.

## What changed

- **Free up space** replaces the four Start here tabs, and it sits right under the chart.
  - It lists safe folders, plus folders nothing has changed for the chosen time (12 hours, 1 day, 3 days or 1 week) that no app has open: build output and caches, Codex scratch, scratch work folders, recovery copies (3 days or older), Android emulators, and untouched items inside folders still in use.
  - It's sorted by size, each folder counts once, and kept, ignored and removed folders never appear.
  - Each row shows the cost (Safe to remove, Rebuildable, Your call), why it's listed, how long it's been untouched, and where it lives.
- **Tick and copy.** Ticked rows show a running total, and one command covers all of them.
- **Trash command:**
  - AppleScript moves each item through Finder on its own, inside `try`, so a missing path doesn't stop the rest. It prints "Moved N of M items to the Trash".
  - The app watches the paths every 2 seconds for up to 30 minutes. A footer line goes from "Copied" to "N of M moved" to "Moved to the Trash … Empty the Trash to get the space back".
  - Every Copy Move-to-Trash button in the app goes through this path.
- **Ages in hours** under a day: "20 hours ago". A scratch folder's card now explains what scratch is. Rescanning a removed folder says "That folder is gone now".

## Evidence

| Check | Result |
|---|---|
| Test suites | 294 checks pass (Overview 117, incl. suggestion rules, quiet times, the new command text and the gone-folder message) |
| Suggestions on this Mac (copy of saved scans) | 1 day: 226 items, 560 GiB, built in 2 ms. 12 hours: 751 GiB. 3 days: 348 GiB. 1 week: 161 GiB |
| Trash command | Compiles with `osacompile` for paths with quotes, apostrophes and backslashes. The same script with `delete` replaced by `get name of` ran on one real fixture folder and one missing path: "Moved 1 of 2", the missing path skipped, the fixture untouched |
| On screen | Free up space under the chart, captions, quiet-time picker, ticking two rows shows "2 ticked · 117.9 GiB" and enables the copy button (unticked afterwards; no command was copied) |
| Legacy history | SpaceCheck import SHA-256 unchanged: e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4 |
| Package | Signed app verified with `codesign --verify --deep --strict`, DMG checksum VALID, installed in /Applications |

## Limits

- "Untouched" is the newest file change a scan saw. A folder a task will use again tomorrow can still look quiet. Codex scratch and work folders stay "Your call" for that reason.
- The watcher confirms a folder left its place; without Full Disk Access it can't read the Trash itself.
- Nothing was deleted, moved or trashed during this work.

