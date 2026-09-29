# Final validation 0.11.0 (build 23)

Trigger: Chris asked for Coverage sorted by size, a clearer scan sheet and Scanning settings, a chart that says what it shows, a correct percentage (it read 100% with 18 GiB free), the last-scan line at the top, and no more "safe" labels on caches he used that day. He also wanted help inside folders he's still using, clearer menu copy, and an export that's worth having.

## What changed

1. **Recently used isn't safe.** Package caches, DerivedData and install caches used in the last 7 days are Check first ("still relying on it"). On this Mac the Gradle cache and the dev.kartpad.app install cache, both used today, left the safe list. Project folders stay at Check first ("Checking git…") until git activity has been read after launch. Before this, the Overview briefly showed 98 GiB as safe; the real figure is 16.8 GiB.
2. **Unused inside busy folders.** In a Check-first folder whose tool rebuilds its contents, top-level items over 50 MiB that haven't changed in 30+ days are listed when they total at least 1 GiB, with Show in Finder and **Copy Move-to-Trash Command** (`mv -n … ~/.Trash/`, copied, never run). On this Mac there are 3.54 GiB of these in 2 folders. One example is npx: 2.2 GiB in 5 installs last changed 3–10 months ago. There's a filter under **More lists** and a row on the Overview.
3. **A short reason under every badge**, for example "Uncommitted work", "May be the only copy", "Active project" or "2.2 GiB unused inside". Process names are shown as app names (prl_vm_app is Parallels Desktop).
4. **Chart in free space.** The headline reads "145.55 GiB less free space" and the subtitle "free space 251.56 GiB → 106.01 GiB". A green Free band sits under the capacity line, the label reads "106.01 GiB free now", and there's a legend. The percentage never rounds up to 100% while space is free, and disk shares under 1% read "under 1%".
5. **Status line at the top of the Overview**: "Sizes from the full scan 3 hours ago · 164 scanned · 48 not scanned yet · 15 growing", followed by **Scan Again…**.
6. **Scan sheet**: places sorted biggest first with sizes and bars, counting only places that are turned on (Games & emulators is 71 GiB with OpenEmu and CrossOver off, not 623 GiB). It also shows when the last full scan ran and how long it took, and has a "What happens" section. The buttons are **Change Places…**, **Watchlist Only (6)** and **Start Full Scan**.
7. **Settings › Scanning**: three action rows (Full scan, Watchlist, New folders), each saying what it does and when it last ran, plus a macOS permission row with **Open Full Disk Access**. **Coverage** is biggest first at both the group and the entry level.
8. **Menus.** The sort menu is "Sort: Biggest unused first", with Where to start / Other orders. The right-click menu offers Scan Again · Always Keep This Folder · Watch for Growth · Its Growth Is Normal · Remind Me Tomorrow · Tags & Notes… · Stop Scanning This Folder.
9. **Export Cleanup List…** (⇧⌘E) is a Markdown checklist: Safe, Unused inside (with the command), Check first, Keep.
10. **Trash reminder.** The Overview says that things in the Trash keep using space until it's emptied, and offers **Open Trash**. It shows the Trash's size only when macOS allows reading it, which needs Full Disk Access.

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 249 checks: 28 core, 22 detail, 69 discovery/model, 83 overview, 19 planner, 28 bounded-scan (`work/cc-011-tests-final`) |
| New tests | A cache used recently is Check first; an idle npm cache is Safe with "Unused for 10 days"; DerivedData stale items; trash command quoting; percentage text; friendly app names; a project build folder held until git is read |
| Main-thread cost | 9.4 ms mean, 16.2 ms max per scan update on current real data (180 folders). On the older data set that 0.10.0 measured at 10.0 ms, it's now 7.7 ms. The gate is at most 10 ms mean. Before the caching fix, 0.11 measured 19.5 ms. |
| Native UI | Overview (status line, free band, "unused inside" and Trash rows) in dark and light; Folders short reasons, sort menu, More lists › Unused inside; npx inspector with its item list; right-click menu; scan sheet; Settings › Scanning and Coverage; export preview |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK (Apple Development, team TEAMID); /Applications executable SHA-256 matches the build (`161a28af…`) |
| Source | `6e22edc` |
| DMG SHA-256 | `eea813cd34c6c9e33ab58500ffd03ba308c2d5cdf185ab903803ec81a831b5cf` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing was deleted, moved or trashed. Earlier builds, DMGs, fixtures and scan records remain. The move-to-Trash command was only rendered and copied in tests; it was never run.

## Limits

- The Trash's size can't be read without Full Disk Access (macOS returns "Operation not permitted"). The Overview shows the reminder without a size until access is granted.
- "Unused inside" looks one level deep and uses modification dates. A tool that reads old files without changing them would still show them as unused.
- The state-changing controls (Start Full Scan, Watch, Keep, Stop Scanning) were shown but not clicked in this pass, to leave Chris's settings and history as they were. The model tests cover them.
- Unnotarized builds ask for App Data access again after relaunch; Full Disk Access avoids that.
