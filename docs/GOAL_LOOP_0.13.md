# Goal loop 0.13: calmer, clearer, faster

Trigger (Sep 30): the Overview works, but it feels cluttered and slow.

- "Where the space went" rows don't let you move between places.
- The chart could be more interactive.
- "Start here" is busy.
- The same colors mean different things.
- Scan History is a wall of folder sizes.
- "Kept" names itself.
- There are two Scan buttons.
- The "Your call" copy is sloppy and repeats itself.

## Rule that overrides everything

Context Cleaner never deletes, moves, trashes, empties, prunes or resets anything. It reads sizes, dates and git state, and it only copies commands for the user to run. Tests use fixtures only.

## Goals

1. **One color system.** Each color means one thing everywhere: the disk map, tiles, badges, the chart, and "where it went".
   - Green: safe or freed.
   - Soft green: old items.
   - Cyan: rebuildable.
   - Orange: your call.
   - Gray: keep.
   - Purple: ignored by you.
   - Blue: used space and growth.
   - Red: scan failures only.
2. **Where the space went, interactive.** Rows are selectable. Selecting one shows its biggest folders inline, each one click to open. It follows the chart's range (24 hours, 7 days, 30 days).
3. **Chart.** Pointing shows the reading in the headline area (time, free, used), and dragging compares. The range is shared with "where it went".
4. **Start here, calmer.** Five rows, one line of explanation, no per-row Finder buttons (right-click has Show in Finder), and the Trash note moves to a single footer line.
5. **One Scan button.** The toolbar's **Scan Folders…** is the only scan entry. The status line becomes information only.
6. **Scan History you can read.** Each scan shows what changed: the biggest growth and shrinkage with signed, colored amounts, and the count of unchanged folders. It doesn't list every folder.
7. **"Kept" becomes "Ignored".** It covers folders you keep out of suggestions and folders you don't scan. Empty tiles hide, and the side panel stops calling unscanned folders "scanned".
8. **Copy pass.** One sentence says what a folder is, one says what removing costs, and "How to remove it" is one action. No repeated "last changed" lines. The Your call rules are rewritten.
9. **Speed.** Measure the running app with `sample` while switching views and scanning. Remove the hot spots, and keep scan updates at 10 ms or less.
10. **Quality gates.** Clean compile with no warnings, all preserving suites plus new tests, a native UI check in dark and light, README and screenshots updated, a validation record, a signed DMG, a GitHub release, and remote parity. The SpaceCheck history hash stays unchanged.
