<p align="center">
  <img src="docs/images/icon.png" alt="Context Cleaner app icon, a blue C" width="128" height="128">
</p>

<h1 align="center">Context Cleaner</h1>

<p align="center">
  <strong>Find the hundreds of gigabytes your AI tools, Xcode and caches quietly pile up on your Mac.</strong><br>
  A native macOS app that shows what's filling your disk, whether you still use it, and how to remove it yourself. It never deletes a thing.
</p>

<p align="center">
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-0A84FF?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-0A84FF?logo=apple">
  <img alt="Built with SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-FF9F0A?logo=swift&amp;logoColor=white">
  <img alt="Never deletes files" src="https://img.shields.io/badge/deletes%20files-never-30D158">
  <img alt="Version 0.13.0" src="https://img.shields.io/badge/version-0.13.0-5E5CE6">
  <img alt="Preview, not notarized" src="https://img.shields.io/badge/status-preview%2C%20not%20notarized-FFD60A">
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#can-i-remove-it">Can I remove it?</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#what-it-looks-at">What it looks at</a> ·
  <a href="#frequently-asked-questions">FAQ</a> ·
  <a href="#build-from-source">Build it</a>
</p>

![Context Cleaner's Overview: a free-space chart, You can get back about 614 GiB split into safe, old builds and rebuildable, where the week's space went, and a Start here list](docs/images/overview-dark.png)

> [!IMPORTANT]
> **Context Cleaner never deletes, moves or empties anything.** It measures folders, explains them and tells you how to remove them yourself, in Finder or with a command you copy and run. There's no clean button, on purpose.
>
> **Preview build.** The DMG is signed but not notarized, so macOS asks you to confirm the first time you open it. See [Download](#download).
>
> **AI disclosure:** Context Cleaner is developed with substantial AI assistance for code, testing, documentation and debugging. The [validation records](docs/validation) state what has actually been checked, and on what.

**Questions or bugs?** [Open an issue](https://github.com/chrissotraidis/contextcleaner/issues).

## Why it exists

Coding agents, Xcode, simulators and package managers write a lot to disk, and none of them clean up after themselves. On the Mac this was built on, free space dropped by more than 170 GiB in two days. The space had gone into Codex worktrees and recovery copies, Android build folders, iPhone install caches, simulators and a Windows VM. Finder's "Large Files" view didn't help: it listed big files, but it couldn't say what wrote them, whether they were still in use, or whether they'd come back.

Context Cleaner answers those questions for the places where this kind of data piles up. It tracks how much space those places take over time, so you can see where the space went and what's still growing.

### At a glance

| | What to expect |
|---|---|
| **Answers** | Every folder gets **Safe to remove**, **Rebuildable**, **Your call** or **Keep**, ranked by what removing it costs, with a short reason |
| **Evidence** | Last use from file dates, read-only git status for project folders, open files, and Xcode's own data for simulators |
| **History** | Disk space every hour while the app is open, folder sizes at every scan, and what grew in between |
| **Coverage** | About 30 known places across AI tools, developer tools, virtual machines, games and Downloads, plus folders you add |
| **Deletes** | Nothing, ever. You remove things in Finder, and space comes back when you empty the Trash |
| **Needs** | An Apple silicon Mac with macOS 14 or later |

## What's new in 0.13

- **One color system.** Green means safe or freed. Soft green is old items, cyan is rebuildable, orange is your call, gray is keep, and purple is ignored. Blue means used space and growth, and red means a scan couldn't read something. Each color means the same thing everywhere.
- **Where the space went, clickable.** Click a place, such as Codex worktrees, to see its biggest folders, each one click from its card. It follows the chart: pick 24 hours, 7 days or 30 days, click a day, or drag across a span.
- **A calmer Start here**: five rows per tab with one line of explanation, and the Trash note as a single footer line.
- **One Scan button**, in the toolbar. The Overview's top line only says how fresh the sizes are.
- **Scan History you can read.** Each scan shows its net change, the folders that grew and shrank most, and anything it couldn't read. It no longer lists every folder.
- **Kept is now Ignored**, covering folders you keep out of suggestions and folders you don't scan.
- **Shorter answers**, written to say what a folder is, what removing it costs, and one thing to do.
- **Lighter.** Old scans no longer hold their folder listings in memory, and a scan update takes 8.9 ms.

See the [0.13 validation record](docs/validation/Final%20validation%200.13.0.md).

## Can I remove it?

Every scanned folder gets one of four answers, ranked by what removing it costs:

| Answer | What removing it costs | Examples |
|---|---|---|
| 🟢 **Safe to remove** | Nothing | Idle package caches, Xcode DerivedData, iPhone install caches, build output from finished projects |
| 🔵 **Rebuildable** | Waiting for the next build or download | Build output and caches you used this week |
| 🟠 **Your call** | Maybe the only copy of something | Recovery copies, scratch `work` folders, virtual machines, folders git tracks |
| ⚪ **Keep** | Breaks the app | Chat history, app libraries |

**Old items inside** folders are counted separately. When a build, cache or scratch folder is still in use, the subfolders inside it that haven't changed in 7 days (project output) or 30 days (caches) are listed with dates, **Show in Finder**, and a copyable move-to-Trash command.

The answers come from evidence, not just folder names:

- **Is it still in use?** "Last used" is the newest file change inside the folder. Project folders also read git, read-only: last commit, whether the branch is merged, uncommitted changes, and whether a worktree is still registered. For example: *"Worktree kartpad-stabilization-20260918: last commit 4 days ago · merged into main · 1 uncommitted change."*
- **Is something using it right now?** Folders with open files are flagged, with the app's name ("Open in Parallels Desktop").
- **Simulators** are listed by device name, such as "iPhone 17 Pro · iOS 26.5", with size and last use taken from Xcode. You remove single devices in Xcode or with a copied `xcrun simctl delete`.
- **Finished worktrees.** A worktree that's merged, clean and quiet for two weeks says it looks finished and offers `git worktree remove`, which git refuses if anything is uncommitted.
- **Git ignores it?** Build folders are checked with `git check-ignore`, read-only. Ignored output is rebuildable; a tracked folder named build may be source, so it's your call.

Right-click any folder to **Always Keep This Folder**, **Watch for Growth**, say **Its Growth Is Normal**, or **Stop Scanning This Folder**. Kept and turned-off folders move to the **Ignored** view, with their own total.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/images/folders-git.png" alt="Folders view with a Codex worktree build folder selected; the card reads Rebuildable, with git evidence, and lists 19 old experiment folders such as evening-20260921 at 33 GiB"><br><sub><b>Folders.</b> Each folder has an answer, a reason, git evidence, and the old experiments inside it.</sub></td>
    <td width="50%"><img src="docs/images/folders-unused-inside.png" alt="The Overview's Start here panel on Old items: build folders with 75 GiB, 53 GiB and 41 GiB of subfolders untouched for a week or more"><br><sub><b>Old items.</b> The folders holding the most old builds, biggest first.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/scan-sheet.png" alt="Scan your folders sheet listing AI tools, developer tools, virtual machines, games and Downloads with sizes, a What happens section, and Watchlist Only and Start Full Scan buttons"><br><sub><b>Scan sheet.</b> What it will read, biggest first, and what happens before you start.</sub></td>
    <td width="50%"><img src="docs/images/cleanup-list.png" alt="Export cleanup list preview showing a Markdown checklist of safe folders with sizes, paths and removal steps"><br><sub><b>Cleanup list.</b> A Markdown checklist with paths and steps, saved on your Mac.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/settings-coverage.png" alt="Settings, Coverage tab, with AI tools expanded: Codex worktrees 492.87 GiB, recovery copies 94.44 GiB and more, each with a switch"><br><sub><b>Coverage.</b> Every place it looks, biggest first, each with a switch.</sub></td>
    <td width="50%"><img src="docs/images/overview-light.png" alt="The Overview in light mode"><br><sub><b>Light mode.</b> Follows your Mac, or pick Light or Dark in Settings (⇧⌘L).</sub></td>
  </tr>
</table>

## What it looks at

Context Cleaner reads the places where apps are known to pile up data, plus any folders you add. It isn't a whole-disk scanner, so its totals never equal your used space; the Overview shows the rest as "Everything else".

| Group | Places |
|---|---|
| **AI tools** | Codex worktrees, recovery copies, tasks, conversations and outputs; Claude; Hugging Face; LM Studio |
| **Developer tools** | Build folders in `~/GitHub`; Xcode DerivedData and device support; simulators; iPhone install caches; npm, npx, pip, uv, Yarn, Gradle, Homebrew and Playwright caches |
| **Virtual machines** | Parallels, Docker Desktop's disk, UTM |
| **Games and emulators** | Steam, CrossOver, OpenEmu |
| **Downloads** | Your Downloads folder |

It never looks at system files, other users' folders, Photos, Mail, Messages or iCloud Drive libraries, or Time Machine snapshots. Turn any place off in **Settings › Coverage**.

## Reading the chart

![The free-space chart: 176.96 GiB less free space over 7 days, with used space in blue and free space as a green band under the capacity line](docs/images/overview-chart.png)

- **Blue is used space; the green band is free space**, up to the dashed capacity line. When the blue rises, the green shrinks.
- **The headline is the change in free space** for the range you pick: 24 hours, 7 days or 30 days.
- **Point at the chart** for a reading. **Drag across it** to compare two times and see which folders grew most in between.
- **Change per day** switches to bars: orange means more space used, green means space was freed.
- Readings come from every scan and from an hourly check while the app is open. Gaps mean the app wasn't running; nothing is filled in.

## Download

Download the latest DMG from [Releases](https://github.com/chrissotraidis/contextcleaner/releases), open it and drag **Context Cleaner** to Applications.

The build is signed but not notarized, so the first launch needs one extra step. Open Context Cleaner, choose **Done** when macOS says it can't verify the app, then go to **System Settings › Privacy & Security** and choose **Open Anyway**. You only do this once per version.

### First run

1. Choose **Scan Folders…** (⌘R), check the list, and choose **Start Full Scan**. A first scan takes a few minutes; you can stop at any time.
2. macOS may ask whether Context Cleaner can read data from other apps (for example iPhone install caches) or your Documents folder. The scan waits for your answer. Either way it only reads sizes and dates.
3. Optional: turn on **Full Disk Access** from **Settings › Scanning**. It stops those questions and lets the app show how much your Trash holds.
4. Start with **Review Safe Folders** on the Overview, or sort **Folders** by **Biggest unused first**.

## Frequently asked questions

### Does it delete anything?

No. It has no delete, clean, Trash, uninstall or reset button. It shows you where a folder is and how to remove it, and you decide. Commands it offers, such as a move-to-Trash command or `git worktree remove`, are copied for you to run yourself.

### Why is "safe to remove" so much smaller than what I can get back?

Because most big folders on a working Mac are in use. "Safe" means nothing is lost at all. The big wins are usually **old items inside** your build folders and **rebuildable** output from projects you're working on, which only cost a rebuild. The Overview adds all three together.

### Why does removing a folder free less than its size?

APFS shares storage between copies of files, so some space only comes back when every copy is gone. Space also only comes back after you empty the Trash.

### Does it send my data anywhere?

No. It has no network code, accounts or analytics. Scans, settings and disk readings are saved as files under `~/Library/Application Support/Context Cleaner`. The cleanup list stays on your Mac unless you share it.

### How does it know what a folder is?

From where the folder is. Each place in [What it looks at](#what-it-looks-at) has a known owner and purpose, such as npm's download cache or Xcode's build data. A folder's location suggests which app writes to it but doesn't prove it, so the card shows the evidence behind each answer.

### Can I stop it suggesting a folder?

Yes. Right-click it and choose **Always Keep This Folder**, or **Stop Scanning This Folder** to leave it out of scans. Both are listed in **Ignored**, with their total.

### Does it run in the background?

Only while it's open. Scheduled checks are off by default; turn them on in **Settings › General**.

## Privacy and your data

Scans read folder sizes, dates and git status only. They never open, change or delete files. Every scan, setting and hourly reading is saved as a new file, and nothing is rewritten or pruned.

## Build from source

Requires an Apple silicon Mac with macOS 14 or later and Xcode 27.

```sh
git clone https://github.com/chrissotraidis/contextcleaner.git
cd contextcleaner
bash build-version.sh /absolute/path/to/new-build-output
```

The script refuses to overwrite an existing destination. It writes the app, a DMG, its SHA-256, the source revision and the icon it used. It signs with your Apple Development or Developer ID identity if you have one, so macOS remembers your privacy answers across updates; otherwise it signs ad hoc. Set `CC_SIGN_IDENTITY` to choose an identity, or `-` for ad hoc.

### Tests

```sh
bash test-preserving.sh /absolute/path/to/new-test-output
```

Six suites (about 250 checks) cover preservation, folder contents, scan limits, planning, discovery and model state, and the Overview's numbers. Every fixture and log is kept.

## Documentation

- [Design and copy rules](docs/DESIGN.md)
- [Validation records](docs/validation), one per release, with evidence and limits
- [Goal loops](docs) for earlier versions

## Getting help

[Open an issue](https://github.com/chrissotraidis/contextcleaner/issues/new/choose) with your macOS version, the Context Cleaner version (**Context Cleaner › About**), and what you expected to see. Check screenshots and paths for anything private before posting.
