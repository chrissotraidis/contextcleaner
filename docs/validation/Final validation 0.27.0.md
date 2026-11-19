# Final validation 0.27.0 and Windows 0.1.3

Mac build 69. Chris's 0.26 review: Everything else held folders nobody could explain (BlueWake checks, device backups), Free Up Space at 10 GiB showed an empty page, Couldn't Scan was 46 red rows with no reason given, and Simulator data was one 94 GiB Review first row. He wanted more found, and everything explained.

## Found

| Problem | Fix |
|---|---|
| Folders Codex tasks made in the home folder sat in Everything else as bare names: 16 folders, 228 GiB here. `~/Backups` (184 GiB, 158 GiB of it one KartPad backup) never showed up at all: the two latest looks couldn't size it in time, so it had no size and sank to the bottom | macOS's provenance attribute names the app that made each folder. Codex's is learned from its worktrees, scratch, private work, tasks and task outputs (here 767 folders agree on one value) and matched against visible folders in the home folder, leaving out macOS's own folders, project roots, git repositories, tool homes and anything holding a scanned place. They're scanned item by item; their card says Codex made them and what they are |
| Everything else rows had no date and, without a rule, no description | Every folder row says when it last changed and whether Codex made it; folders without a rule are described from what's inside (release check, Wine bottle, backups with count and newest date, "Mostly …"). A folder too big to size keeps its last known size, marked ≈, and its place |
| Free Up Space at 10 GiB said "Choose a smaller size above to see the 52 smaller items" over an empty list | It says what the smaller items add up to, with Show All Sizes (Mac and Windows) |
| Couldn't Scan: 46 rows, all "macOS blocked access" | All 46 (47 after this scan) are iPhone install caches inside Apple CoreDevice's container, which macOS lets only Full Disk Access read. Even a shell gets "Operation not permitted" there. One banner explains it, with their total when last read (49.04 GiB, Nov 16), that install caches are Safe to remove, Allow Access… and Stop Checking These. A blocked folder's card shows its last known size |
| Simulator data: one row, no breakdown | Each simulator's card lists its apps from Xcode's container metadata, build and data apart, with `xcrun simctl uninstall` (per app, right-click) and `xcrun simctl erase`; the Devices card totals each app across simulators |
| Two installs of one app under different identifiers read as the same name twice | Names that collide carry the identifier: NightPad was on one iPad as `local.nightpad.shell` and `com.chrissotraidis.nightpad`, 3.9 GiB of data each |
| Caches not covered | pnpm store 1.9 GiB, Bun 2.4 GiB, NuGet 3.7 GiB, Go modules and build cache 0.3 GiB, ccache 4.7 GiB |
| `~/Backups` read "Open in ContextCleaner at last scan", which kept its backups out of Free Up Space | The open-files snapshot taken at scan start leaves out Context Cleaner's own process. Its own sizing of Everything else, still running when the scan began, had been counted as an app using the folder |
| The overview kept naming `~/Backups` as the biggest place in Everything else after it was scanned | Folders scanned since the last look are left out of that sentence |

## Evidence

| Check | Result |
|---|---|
| Mac test suites | 442 checks pass, 18 new: descriptions (release check, Wine bottle, backups, "Mostly"), name and version, blocked-folder grouping, uninstall and erase commands refuse anything but a device ID and a plain bundle identifier, app totals across simulators and twins told apart by identifier, Codex folders found and others (another app's, macOS's own, tool homes, hidden, git projects) left out, Codex's mark needs three agreeing folders, classification, discovery, Free Up Space offers items inside but never the folder and never ticks a backup, a command never moves the folder whole, a simulator's apps read with build and data together, and a folder scanned since the look leaves the overview sentence. macOS stamps every folder a process makes with that process's maker, so the tests supply makers through `readProvenance` |
| Mac compiler | No warnings, no errors |
| This Mac, build 69, read-only probe | 16 Codex-made home folders found, all task output. `~/Backups` 184.35 GiB, offering kartpad 157.69 GiB and spaghettipad-modernization 17.57 GiB as backups. iPhone 18 Pro's apps read in 0.7 s: TribesPad 11.21 GiB build, GalaxyPad 7.02 GiB data, KartPad 4.64 GiB data |
| This Mac, build 69, installed | Full scan: 860 folders in 2m 53s. Free Up Space at 1 month went from 48.76 GiB (0.26) to 268.43 GiB, 71 items; Select All skips 15 backups. Ticking kartpad asked "1 item, 157.69 GiB, all Review first… Copy anyway?"; the copied command named only `/Users/chrissotraidis/Backups/kartpad` and passed `bash -n`. It was not run. The 10 GiB filter showed "6 smaller items add up to 5.22 GiB" and Show All Sizes listed them. Couldn't Scan showed the banner over the 47 rows |
| Windows, Windows PowerShell 5.1 in the Parallels VM, STA | 105 checks, 0 failed, including the window XAML loading, every control the script uses existing, and 4 new checks for Everything else descriptions |
| Not checked | The Windows window wasn't opened on a desktop, so Show All Sizes there was checked in code and XAML only. PowerShell 7 wasn't run. Context Cleaner has no Full Disk Access here, so the CoreDevice caches were not read |
