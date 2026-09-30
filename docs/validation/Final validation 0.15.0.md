# Final validation 0.15.0 (build 28)

Goal loop: [GOAL_LOOP_0.15.md](../GOAL_LOOP_0.15.md). Trigger: Chris couldn't tell which folder a card showed. Drilling in had no way back. A subfolder scan showed 1,020 KiB under its parent's name. "Keep" and "Ignored" were inconsistent. The Overview scrolled too much, the chart was unclear, and "Everything else" was unexplained.

## What changed

1. **Names.** A subfolder of a recognized folder is named for itself, for example "kartpad-release-source · project_dex_archive in Android build intermediates". Worktree folders are named for their own folder, not the repository they came from, so GitHub/kartpad-release-source is no longer labeled "kartpad-source-migration". Older saved scans are shown with today's names, and the saved files are unchanged.
   - *Finding:* the 1,020 KiB was not a scanner bug. The Scan Folder button measured the one subfolder Chris had clicked in "What's inside", and it was mislabeled with its parent's name. The parent is still 2.22 GiB, and the old and new scanners give identical results on it (2,385,649,664 bytes, 642 files).
2. **Where you are.** Every card shows the full path with ~, and an **Up to** link to the nearest known parent.
3. **Back and Forward** in the toolbar (⌘[ and ⌘]). They step through the view, filter, type and folder. Opening a folder from the Overview is one step, and clicking between rows in the same list isn't. Checked on screen: subfolder → Up → Back returns to the subfolder.
4. **Trash command on every card.** "Copy Move-to-Trash Command" covers the whole folder, except virtual machines, simulators, chat history and app libraries, which are managed in their own apps. The command is now `osascript -e 'tell application "Finder" to delete {POSIX file "…" as alias}'`. Finder moves the items to the Trash, so Put Back works and same-named items don't collide. Each path is escaped for AppleScript and the whole script for the shell. The commands were compiled with `osacompile`, never run, for paths containing quotes, backslashes, Unicode, `$(…)` and backticks.
5. **Biggest first** is the default order. Biggest unused first is the second option.
6. **Vocabulary.**
   - Your choice is **Ignore**: an Ignore button, Ignore This Folder, Stop Ignoring, "Ignored" as the status, and the Ignored view.
   - The app's answer for app libraries is **Leave it**.
   - "Keep", "Kept" and "Never suggested" no longer appear anywhere.
7. **Rates.** Where the space went has a headline rate ("about 51 GiB a day") and a rate for each place, all on one line.
8. **Less scrolling.** The chart height is fixed at 120–190 pts, the duplicate "Grew most" chips are gone, and each place is one line. On a 1243×944 window, the chart, disk map and both panels fit with only the Trash footer below the fold.
9. **Charts.** The Overview chart plots free space from zero ("Full") upward. Change per day bars point down for space lost. A folder's size chart is one continuous line; readings that failed or had a different scope no longer leave stray dots.
10. **Everything else.** Clicking it, or the matching row in Where the space went, opens a sheet that explains what it holds. **Look Inside** sizes the top level of your home folder, ~/Library and /Applications, leaving out every scanned or turned-off folder, and shows the results with Show in Finder. It's read-only, saves nothing, and never feeds any answer. On this Mac, a headless run took 109 s and found 1.57 TiB of the 1.82 TiB. The largest were the rest of ~/GitHub (396 GiB), the rest of ~/.codex (375 GiB), ~/Backups (185 GiB), ~/.ollama (135 GiB), /Applications (114 GiB), ~/.diffusionbee (71 GiB) and ~/.android (61 GiB).

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 260 checks: 28 core, 22 detail, 72 discovery/model, 91 overview, 19 planner, 28 bounded-scan |
| New tests | Trash command escaping; subfolder and project naming; ~ paths; Back returns to the Overview in one step and Forward returns to the folder; Ignored status |
| Main-thread cost | 4.9 ms CPU per scan update (180 folders) |
| Look Inside, on screen | Opened from the disk map's Everything else in the installed build. It listed 123 folders, biggest first, with sizes and Show in Finder buttons, and "1.71 TiB found in these folders, of 3.52 TiB used". Look Again and Done both work. |
| Native UI | Overview (free-space chart, get-back bar, rates, Start here), Folders with biggest first, the subfolder card with path and Up link, Up then Back, Copy Move-to-Trash Command on cards |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK; /Applications executable matches the build |
| Source | `534c863` |
| DMG SHA-256 | `7e47f5c52356f26e097ebc7bfeec19fb1065cd2dea7c9ef1a2f5a30ea9334d84` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing on the Mac was deleted, moved or trashed. The trash commands were compiled, not run.

## Limits

- Its folder buttons are announced to VoiceOver as "Move" (the icon's name) instead of "Show in Finder"; the tooltip is correct. Fix in the next release.
- A few seconds after launch, before git is read, project folders show "Checking git…" and the totals are lower.
- "Everything else" can't be split into scanned places; Look Inside shows its biggest folders instead.
