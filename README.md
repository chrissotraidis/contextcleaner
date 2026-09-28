# Context Cleaner

**See what's filling your Mac, and when. Then decide for yourself.**

Context Cleaner is a native macOS app that shows how full your disk is, how that changed this week, and which folders are taking the space. It covers the places apps quietly pile up data: AI tools, Xcode and simulators, package caches, game libraries and your downloads.

**It never deletes files.** There's no cleanup, Trash, uninstall or reset button anywhere. You decide what to do, in Finder.

## Start here

1. Choose **Scan Folders…** (⌘R). The sheet lists the apps and paths it will read. Choose **Start Scan**; a bar under the title shows progress, and you can stop at any time.
2. On **Overview**, read the headline above the chart, for example "+24 GiB more space used". Then look at **What's taking space** and **Largest folders**.
3. Click any category or folder to open it in **Folders**. The panel on the right says what the folder is, how its size has changed, and offers **Scan Folder** and **Show in Finder**.
4. Add folders you care about to your **Watchlist**. Optional daily or weekly checks are in **Context Cleaner › Settings…** (⌘,). They run only while the app is open and are off by default.

## How to read the chart

![Space used chart](docs/images/space-used.png)

- **The blue area is used space.** It rises when your disk fills up. The dashed line at the top is your disk's capacity, and the gray band between them is free space.
- **The headline is the change** for the range you picked: 24 hours, 7 days or 30 days.
- **Point at the chart** to see the exact reading at that moment. **Drag across it** to see the change between two times, plus the scanned folders that grew most in that span. Click **Clear Selection** to go back.
- **Change per day** switches to bars: orange means more space used, green means space was freed.
- **Where readings come from:** Context Cleaner notes your disk space every hour while it's open, and at every scan. Gaps in the line are times when the app wasn't running. Nothing is filled in or guessed.

## The five views

| View | What it answers |
|---|---|
| **Overview** | How full is my disk, how did that change, and what's taking the space? |
| **Folders** | How big is each folder, is it growing, and what is it? Select several with ⌘‑click or ⇧‑click to add their sizes. |
| **Watchlist** | Which folders am I keeping an eye on? |
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

Apple Silicon, macOS 14 or newer. Built with Xcode 27.0. Builds are ad‑hoc signed and **not notarized** for public distribution.

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
