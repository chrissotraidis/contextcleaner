# Context Cleaner 0.9.0 validation

2026-09-29. Final package built from commit `618d005`. Nothing on this Mac was deleted, trashed, moved, pruned, reset or cleaned. Earlier builds, DMGs, test fixtures and scan history remain.

## Automated checks

All six preserving suites passed: **185 checks** (Core 28, Detail 22, ScanLimit 25, Planner 19, Discovery 52, Overview 39). New checks cover:

- Calendar‑aligned 24‑hour, 7‑day and 30‑day windows, stable across redraws.
- A zoomed vertical axis that always reaches capacity, and starts at zero for a half‑empty disk.
- Merging scan, hourly and live readings, with the live reading winning a duplicate timestamp.
- Gaps breaking the line; readings outside the window left out.
- Span change and per‑hour or per‑day buckets that leave empty periods empty.
- What grew: nested folders counted once, shrinking folders left out, and no baseline older than a day before the span.
- Sparklines ignoring stopped scans.
- Scan results telling an unreadable folder apart from a stopped scan, with singular and plural wording.
- Hourly capacity readings: stored as new files, at most one per 55 minutes, reloaded unchanged after restart, and shown on the chart.

Fixtures and logs are kept in the task's `work/cc-090-tests-*` folders.

## Native checks

Before and after screenshots are kept locally in the task's `work/cc-090-screens` folder and are not in the repository. On the final and checkpoint builds with the real saved history:

- **Chart:** 7‑day view with weekday labels and a capacity ceiling. Hovering shows a reading. Dragging selects a span and shows its change; Clear Selection resets it. Change per day and per hour bars show orange for more used and green for freed. Hourly readings accumulated from 12 to 18 during the session.
- **Overview:** The full‑height window shows no scrolling and the chart grows with the window. The compact 1103 × 752 window scrolls slightly, as expected.
- **Toolbar:** Scan Folders… becomes Stop Scan while scanning, and Export Report… is separate. View › Appearance switches Light and Dark.
- **Scan bar:** Shows "Scanning N of M", "Reading sizes only" and Stop, then a result line with Show Problems and Show Growing.
- **Couldn't Scan:** Tested with a genuinely locked test folder. It showed a red badge (read aloud as "Couldn't Scan, 1 folder"), "No permission to read it" with Show in Finder, and Allow Access… opening the help sheet with Open Privacy Settings. When empty it is quiet, with no red.
- **Folders:** Trend column, "1 scan" placeholder, a list summary with nothing selected, and no sideways scrolling.
- **Inspector:** What's inside, Details, the day‑and‑hour axis, and "No change in 6m 59s".
- **Scan History:** Grouped under Today, Yesterday and dated days, with a red warning icon for unreadable scans.
- **Settings:** General, Scanning with Advanced, and Coverage with accessible group headers and switches. Coverage fits one screen when collapsed.
- **Sheets:** The scan sheet names apps by group and friendly folder names. The report sheet and the Tags and notes sheet use the new wording.

### Bugs found and fixed during the loop

- An unreadable folder was reported as "Stopped after 0 of 1 folders". It now reads "1 folder couldn't be read" with a red icon.
- VoiceOver read the Couldn't Scan sidebar row as just "1".
- Coverage group arrows weren't exposed to accessibility because a switch sat inside the disclosure label.
- A truncated chart headline, sideways‑scrolling tables, a truncated Show in Finder button, and a repeated "Sep 28" axis.
- File‑permission blocks were described as macOS privacy blocks, with an unhelpful Full Disk Access fix.

### Environment finding

A locked test folder inside `~/Documents` (synced by iCloud Drive) was unlocked by the system about three seconds after being locked, with Context Cleaner idle. The same test in `/tmp` and in the app's development folder stayed locked, and the app's source contains no permission‑changing calls. The Couldn't Scan test therefore used the unsynced folder.

## Package

| Item | Value |
|---|---|
| DMG | `Context Cleaner 0.9.0 Final/Context-Cleaner-0.9.0.dmg` |
| DMG SHA‑256 | `1d8359db491ff5e9bb492980c539cfd4a5ef5a37000f3c1d1fa5cf30a8377355` |
| Executable SHA‑256 (launched = packaged) | `1fa30cc071d9d403b4ae99b5d0626b7d84ea99580bc4923fba735d2bbe0437b3` |
| Checks | `hdiutil verify` VALID · `codesign --verify --deep --strict` OK · version 0.9.0 |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

The build's source status lists two untracked scratch images, `docs/images/space-used.png` and `space-used-chart.png`. They were mis‑cropped attempts, are unused and uncommitted, and were left in place.

## Limits

- The "someone new understands the week in five seconds" test was not run with a new user. The headline states the change in words.
- Exact 1480 × 920 layout was checked by measurement, because automation couldn't resize the window. The non‑chart content measured about 530 points, leaving about 80 points spare at the default size.
- Scan Subfolders, Stop Checking and Try Again fixes weren't exercised natively; they need a folder too large, missing or failing. Each calls an already‑tested model path. Moving or deleting a folder to create those cases was ruled out.
- Hourly readings are recorded only while the app is open. Growth before recording started is unknown. Per‑day bars compare against the last reading before the day began.
- Folder paths suggest which app uses a folder; they don't prove which program wrote it. Folder sizes aren't guaranteed recoverable space.
- The DMG is ad‑hoc signed, not notarized.

