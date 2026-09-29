# Final validation 0.9.2 (build 15)

Trigger: the user still couldn't see what was safe to delete. Three causes were found and fixed.

## What was wrong

1. **Wrong copy of the app.** Two copies were running (the new build 11 and a stuck 0.9.0), none was in /Applications, and Spotlight indexed eight older development builds. The user's screenshot still had the old Trend column. Build 15 is now installed at /Applications/Context Cleaner.app, and the other copies were quit. Quitting only ends a process; nothing was removed.
2. **The answer was easy to miss.** It sat in the last table column. The Folders page now opens with Safe to remove, Check first and Keep tiles (size, count, meaning; each one is a filter). The verdict column sits next to the folder name, and other lists are under Other lists. The Overview's right panel lists the safe folders, biggest first, each with Show in Finder, and Largest folders is one click away.
3. **Last used was almost never known, and full scans never finished.**
   - Almost every size came from the imported SpaceCheck scan, which recorded no dates, and full scans only re-measured newly discovered folders. Full scans now also re-measure every saved folder still on disk.
   - The scanner spent most of its time normalizing paths for exclusion checks and building `URL`s per file. On the 57 GiB de-probe cache (124,795 files), it took **15.6 s before and 5.1 s after**, with identical bytes, file count and last-changed date. `du -sk` takes 2.6 s.
   - Scans you start now run at normal priority (background checks stay low). The per-folder limit is 5 minutes and 5 million files (was 2 minutes and 1 million); a full scan may take 30 minutes. DerivedData, with 518k files, measured in 40 s at normal priority and 50 s at utility priority.
   - The first full scan brings up macOS dialogs for other apps' data and the Documents folder, and it waits for the answer. That is what stalled earlier scans. An orange banner now explains the wait and both choices. An earlier draft of that banner could grow the window off screen; it is capped at three lines.

Smaller fixes: the scan sheet no longer lists added folders that are gone.

## Evidence

- Preserving suites: 220 checks passed (28 core, 22 detail, 25 bounded-scan including the exclusion rules I rewrote, 19 planner, 58 discovery/model, 68 overview).
- Native UI, dark, installed build: the Overview shows the Safe to remove list with Finder buttons. The Folders tiles and the verdict next to each name render. With the permission dialog up, the window draws normally and shows the banner.
- A partial full scan with an earlier build filled real last-used dates, for example LM Studio downloads "3 months ago" and kartpad build intermediates "2 weeks ago".
- `hdiutil verify` VALID and `codesign --verify --deep --strict` OK for build 15, and the /Applications copy matches the built app.

Nothing was deleted, moved or trashed. Every earlier build folder, DMG, fixture and scan record remains.

## Limits

- The complete full scan with the new scanner hasn't finished yet. It is waiting for the user's answer to the macOS permission dialogs. Until it finishes, many rows still show yesterday's imported sizes and "Not recorded".
- Test builds are signed ad hoc, so macOS asks again after each new build.
- "Safe to remove" totals changed during this pass (138 GiB, then 70 GiB) because the earlier interrupted scan marked large caches as too large or blocked. The full scan will settle it.
