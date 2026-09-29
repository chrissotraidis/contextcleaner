# Final validation 0.13.0 (build 26)

Goal loop: [GOAL_LOOP_0.13.md](../GOAL_LOOP_0.13.md). Trigger: Chris found the Overview cluttered and slow. Specifically:

- "Where the space went" couldn't be clicked into.
- Colors meant different things in different places.
- Scan History was a wall of sizes.
- "Kept" named itself.
- There were two Scan buttons.
- The Your call copy was sloppy.

## What changed

1. **One color system** (see the comments in `extension Color`):
   - Green: safe or freed. Soft green: old items. Cyan: rebuildable. Orange: your call and warnings. Gray: keep. Purple: ignored.
   - Blue: used space and growth. Growth moved from orange to blue so orange only means "needs you".
   - Red: a scan couldn't read something.
2. **Where the space went** lists places that grew and shrank; click one to see up to five folders, each opening its card. It follows the chart's range, a clicked day, or a dragged span. The chart's disk change and the panel's total now agree (48.58 GiB for the week on this Mac).
3. **Chart.** Pointing labels the reading at the point. Clicking selects that day (or hour), and dragging selects a span. **Show All** clears the selection.
4. **Start here** shows five rows per tab, colored by answer, with no per-row buttons. Right-click still shows Show in Finder. The Trash note is one footer line.
5. **One Scan button.** The Overview's Scan Again button is gone; Scan Folders… in the toolbar is the one entry point.
6. **Scan History.** Each entry shows the net change on its row. Opened, it lists grew most, shrank most, and anything unreadable, and each folder opens its card. The first scan of a place lists its biggest folders.
7. **Kept → Ignored.** The tiles show "Never suggested" and "Not scanned" only when they're non-empty, and the side panel counts folders correctly.
8. **Copy.** Reasons no longer repeat "last changed" (the card shows it once). Recovery copies now read "Codex copied this before a risky change. Once that work is safely in the project, you don't need it." Scratch `work` folders, project files, installs, caches and VMs all have one-sentence reasons.
9. **Lighter.** Older scans drop their per-folder child listings from memory; only each folder's last two are kept, for the "what's inside" comparison. Saved files are unchanged. The Overview is split into separate views, so hovering the disk map no longer redraws the chart or the lists.

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 255 checks: 28 core, 22 detail, 69 discovery/model, 89 overview, 19 planner, 28 bounded-scan |
| New test | "Where it went" for a span that ended in the past uses the last scan before the span ended |
| Main-thread cost | 8.9 ms mean per scan update (180 folders) measured on a quiet machine before release. At release time Xcode's linker was using 10 cores (load average 250–830), and the unchanged 0.12 benchmark binary read 10.6 ms against 11.1 ms for 0.13. Re-measure on an idle machine to confirm the 10 ms gate. |
| Running app | Sampling view switches showed the main thread idle. Load takes 0.5 s for 21 scans (34 MB). |
| Native UI | Overview with Codex worktrees expanded, Scan History expanded, Ignored view |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK; /Applications executable matches the build |
| Source | `98b0b81` |
| DMG SHA-256 | `2cf5e33a6a1461b7980a5ac020925e9b2b9ff3536bd8772dde36429a792a0b0e` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing on the Mac was deleted, moved or trashed.

## Limits

- The 10 ms gate needs an idle-machine re-measure (see above).
- "Outside scanned folders" can't be split further; it's everything the app doesn't cover.
- For a few seconds after launch, before git has been read, some project folders show "Checking git…" and the totals are lower.
