# Context Cleaner

**See what's filling your Mac, and when. Then decide for yourself.**

Context Cleaner is a native macOS app that shows how full your disk is, how that changed this week, and which folders are taking the space. It covers the places apps quietly pile up data: AI tools, Xcode and simulators, package caches, virtual machines, game libraries and your downloads.

**It never deletes files.** There's no cleanup, Trash, uninstall or reset button anywhere. You decide what to do, in Finder.

## Start here

1. Choose **Scan Folders…** (⌘R). The sheet lists the apps and paths it will read. Choose **Start Scan**; a bar under the title shows progress, and you can stop at any time.
2. On **Overview**, read the headline above the chart, for example "+24 GiB more space used". The disk map below it splits your whole disk into Safe to remove, Check first, Keep, Kept by you, Everything else and Free; point at a color for details and click it to list those folders. **How long it's sat unused** shows where idle space is.
3. Click any part of the map or any folder to open it in **Folders**, where big folders you haven't used lately come first. The panel on the right says what the folder is, how its size has changed, and offers **Scan Folder** and **Show in Finder**.
4. Add folders you care about to your **Watchlist**. Optional daily or weekly checks are in **Context Cleaner › Settings…** (⌘,). They run only while the app is open and are off by default.

## Can I remove it?

Every folder gets a plain answer, with the reason and how to do it yourself:

- **Safe to remove** (green): tools recreate it, and it hasn't been used lately. Package caches, Xcode build data, install caches, old build output, and test devices you haven't opened in 30 days.
- **Check first** (orange): might be fine; the folder's card says exactly what to look at.
- **Keep** (gray): app libraries and history. Remove things from inside their own app instead.

The Folders page opens with the answer: **Safe to remove**, **Check first** and **Keep**, each with a total you can click to list those folders. Every row shows its answer next to its name, its size and when it was **last used**. "Not recorded" means the size came from an older scan that didn't note when files last changed; a full scan fills it in, because it re-measures every saved folder. The Overview's **Safe to remove** panel lists the biggest safe folders with a Finder button for each.

The first full scan may bring up macOS dialogs asking whether Context Cleaner can read data from other apps (for example iPhone install caches) or your Documents folder. The scan waits for your answer and says so in an orange banner. Allow includes those folders; Don't Allow skips them. Either way it only reads sizes.

Test devices get special care. Each one is listed by its real name ("iPhone 17 Pro · iOS 26.5") with its size and last use taken from Xcode right now, so no scan is needed and the numbers are never stale. The whole Simulator folder is never offered for removal; its card says how many devices are idle and how much they use, and you remove single devices in Xcode › Window › Devices and Simulators or with the copied `xcrun simctl delete` command.

**Is it still in use?** For project folders in GitHub repositories and Codex worktrees, the answer also reads git, read-only: the last commit, whether the branch is merged into main, uncommitted changes, and whether the worktree is still registered. For example: "Worktree kartpad-stabilization-20260918: last commit 3 days ago · merged into main · 1 uncommitted change." Recent activity means Check first. A worktree that's merged, clean and quiet for two weeks says it looks finished and offers `git worktree remove`, which git refuses if anything is uncommitted. "Last used" is the newest of the folder's file changes and its last commit.

**Keep it out of the way.** Right-click any folder, or use the **Keep** button, to choose **Keep, Never Suggest**, for example your OpenEmu or CrossOver libraries. Kept folders leave every suggestion and move to the **Kept** view, which shows their total and share of your disk next to folders you turned off. **Stop Keeping** brings a folder back.

**Virtual machines** (Parallels, Docker Desktop's disk, UTM) are measured too. They're never called safe, because removing one deletes a whole computer; the card points to the app's own tools, such as `docker system df` to see what Docker can reclaim.

Folders that no longer exist leave every list and total, including Couldn't Scan. The Overview shows how much looks safe to remove, and **Review Safe Folders** lists them. Context Cleaner never deletes anything; it tells you where, why and how.

## How to read the chart

![Space used chart](docs/images/overview-chart.png)

- **The blue area is used space.** It rises when your disk fills up. The dashed line at the top is your disk's capacity; the gap between them is your free space. The dot on the right is today.
- **The headline is the change** for the range you picked: 24 hours, 7 days or 30 days. If readings began partway through that range, the chart starts at the first reading and says so, instead of drawing empty days.
- **Point at the chart** to see the exact reading at that moment. **Drag across it** to see the change between two times, plus the scanned folders that grew most in that span. Click **Clear Selection** to go back.
- **Change per day** switches to bars: orange means more space used, green means space was freed.
- **Where readings come from:** Context Cleaner notes your disk space every hour while it's open, and at every scan. Gaps in the line are times when the app wasn't running. Nothing is filled in or guessed.

## The six views

| View | What it answers |
|---|---|
| **Overview** | How full is my disk, how did that change, and what's taking the space? |
| **Folders** | Can I remove it, how big is it, when did I last use it, and what is it? Big unused folders come first; **Order** changes that. Select several with ⌘‑click or ⇧‑click to add their sizes. |
| **Watchlist** | Which folders am I keeping an eye on? |
| **Kept** | Which folders did I choose to keep or not scan, and how much of my disk is that? |
| **Couldn't Scan** | Which folders couldn't be read, and what's the fix? Each row gives a plain reason and one button. Folders that simply haven't been scanned yet aren't listed here. |
| **Scan History** | What did each scan check, and what did it find? Grouped by day. |

**Export Report…** (⇧⌘E) previews a Markdown file of the folders shown, with the week's change at the top, before you save it. It stays on your Mac.

**Settings** has three short tabs. General covers appearance and scheduled checks. Scanning explains what a scan does, with limits under Advanced. Coverage lists every place the app looks, grouped as AI tools, developer tools, games and emulators, downloads, and your folders, with a switch for each.

## What the numbers mean

- **Disk space** comes from macOS for the volume holding your home folder.
- **Folder sizes** come from the latest scan of each folder. A folder inside another is counted once in totals. Sizes can come from different days, and scanned folders never add up to all your used space.
- **Growth** needs two comparable scans. Nothing before the first scan is known, and a folder's location suggests which app uses it without proving which app wrote to it.
- **Removing a folder may free less than its size**, because APFS shares storage between files. Caches can usually be rebuilt, but that takes time. App libraries, test devices, recovery copies and project folders can hold the only copy of your work.

## Privacy and preservation

Scans read folder sizes and dates only; they never open, change or delete files. Scans, preferences and hourly disk readings are saved as new files under `~/Library/Application Support/Context Cleaner`. Nothing is rewritten or pruned. Earlier SpaceCheck history stays untouched.

## Build and run

Apple Silicon, macOS 14 or newer. Built with Xcode 27.0. Builds are **not notarized** for public distribution. The script signs with your Apple Development or Developer ID identity when one is in your keychain, so macOS remembers your privacy answers (other apps' data, Documents) across updates; otherwise it signs ad‑hoc and macOS asks again after each build. Set `CC_SIGN_IDENTITY` to pick an identity, or `-` for ad‑hoc.

```sh
bash build-version.sh /absolute/path/to/new-build-output
```

The script refuses an existing destination and writes the DMG, its checksum, the source revision and status, and the icon it used. Build stages stay under `~/Library/Application Support/Context Cleaner Development/Builds/<UUID>`; nothing is cleaned automatically.

## Development

```sh
bash test-preserving.sh /absolute/path/to/new-test-output
```

Six suites cover preservation, folder contents, scan limits, planning, discovery and model state, and the Overview's numbers: chart ranges and gaps, span changes, per‑day bars, what grew, hourly readings and scan results. Every fixture and log is kept.

[Design and copy rules](docs/DESIGN.md) · [0.9 goal loop](docs/GOAL_LOOP_0.9.0.md) · [0.9 validation and limits](docs/validation/Final%20validation%200.9.0.md)
