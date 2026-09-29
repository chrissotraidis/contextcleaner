# Goal loop 0.12: what you can get back

Trigger (Sep 30): free space fell 185 GiB since Sunday, but the Overview offered 11 GiB as safe. 1.2 TiB sat under "Check first", which named no action, and the copy was too long. Chris is removing things by hand every day and can't find what's left.

The app's own saved scans show the gap. Inside Codex worktree and project `build`, `generated` and `work` folders, **335 GiB of subfolders haven't changed in 7+ days** (574 GiB at 3+ days). They're dated experiment builds such as `evening-20260921` (33 GiB) and `ios73` … `ios89` (6 GiB each). The app judges each 116 GiB parent folder as a whole, so it misses all of them.

## Rule that overrides everything

Context Cleaner never deletes, moves, trashes, empties, prunes or resets anything. It reads sizes, dates and git state, and it only copies commands for the user to run. Tests use fixtures only. No build, test or check touches the user's data.

## Goals

1. **Answers ranked by what removing costs.** Replace Safe / Check first / Keep with four short answers:
   - **Safe to remove**: nothing is lost.
   - **Rebuildable**: build output or a cache you still use; removing it means waiting for a rebuild.
   - **Your call**: may hold the only copy (recovery copies, scratch folders, VMs, uncommitted work).
   - **Keep**.

   Project `build`, `generated`, `intermediates` and `.cxx` folders that git ignores are Rebuildable, even in active projects. Every row gets a reason of four words or fewer.
2. **Old experiments inside folders.** List subfolders unchanged for 7+ days in project build, generated and work folders, and 30+ days in caches. Each gets its date, size, Show in Finder, and a copied move-to-Trash command. Whole-folder answers (recovery copies) are excluded.
3. **Overview, rebuilt around two questions:**
   - **What can I get back?** One bar and four rows (Safe, Old experiments, Rebuildable, Your call), each clickable, with the biggest items.
   - **Where did the space go?** The chart range's change, split into scanned folders that grew (grouped by place, such as Codex worktrees or Simulator), folders created in that time, and space outside scanned folders.

   Remove the panels these replace, so the page scrolls less.
4. **Git knows what's ignored.** Read, read-only, whether a project folder is ignored by git. Show "Not in git" as evidence.
5. **Plain, short copy everywhere.** One sentence for what it is, one for the answer, one evidence line, one action. Cut repeated wording.
6. **Quality gates:** clean compile with no warnings, all preserving suites plus new tests, scan-update cost at most 10 ms mean, a native UI check in dark and light, README and screenshots updated, validation record, signed DMG, GitHub release, remote parity.

## Acceptance on this Mac

- The Overview's "What you can get back" names at least 250 GiB, each part backed by dates or git evidence, where 0.11 showed 11 GiB.
- The kartpad-stabilization `build` card lists its dated experiment folders with dates and sizes.
- The 185 GiB change is split so that most of it is named: folders that grew, new folders, or outside scanned folders.
- Nothing on the Mac is deleted or moved. The legacy SpaceCheck history hash is unchanged.
