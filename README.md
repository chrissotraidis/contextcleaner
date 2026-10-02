<p align="center">
  <img src="docs/images/icon.png" alt="Context Cleaner app icon, a blue C" width="128" height="128">
</p>

<h1 align="center">Context Cleaner</h1>

<p align="center">
  <strong>Find the hundreds of gigabytes that Codex, Xcode and your build tools quietly pile up on your Mac.</strong><br>
  A native macOS app that shows where your disk went, what each folder is, what removing it costs, and exactly how to remove it yourself. It never deletes a thing.
</p>

<p align="center">
  <a href="https://github.com/chrissotraidis/contextcleaner/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/chrissotraidis/contextcleaner?label=release&color=5E5CE6"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-0A84FF?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-0A84FF?logo=apple">
  <img alt="Native SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-FF9F0A?logo=swift&amp;logoColor=white">
  <img alt="Never deletes files" src="https://img.shields.io/badge/deletes%20files-never-30D158">
  <img alt="No network access" src="https://img.shields.io/badge/network-none-30D158">
  <img alt="Status: preview, not notarized" src="https://img.shields.io/badge/status-preview%2C%20not%20notarized-FFD60A">
  <a href="https://discord.gg/xwHfUD2bxW"><img alt="Join the community on Discord" src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?logo=discord&amp;logoColor=white"></a>
</p>

<p align="center">
  <a href="#getting-started">Download</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#can-i-remove-it">Can I remove it?</a> ·
  <a href="#a-tour">Tour</a> ·
  <a href="#frequently-asked-questions">FAQ</a> ·
  <a href="#build-from-source">Build it</a>
</p>

![Context Cleaner Overview: 193 GiB free of 3.63 TiB and about 66 GiB to get back, then Free up space with 88 items untouched for 12 hours, filters for Safe, Rebuildable and Might hold work, Select All and Copy Move-to-Trash Command above the list, and a device backup marked so Select All skips it](docs/images/overview-dark.png)

> [!IMPORTANT]
> **Context Cleaner never deletes, moves or empties anything.** It measures folders, explains them, and tells you how to remove them yourself: in Finder, or with a command it copies for you to run. There is no clean button, on purpose.
>
> **Preview build.** The DMG is signed but not notarized, so macOS asks you to confirm the first time you open it. See [Getting started](#getting-started).
>
> **AI disclosure:** Context Cleaner is developed with substantial AI assistance for code, testing, documentation and debugging. The [validation records](docs/validation) state what has actually been checked, and on what.

**Questions or bugs?** Join the [Discord](https://discord.gg/xwHfUD2bxW) or [open an issue](https://github.com/chrissotraidis/contextcleaner/issues).

## What is Context Cleaner?

Coding agents, Xcode, simulators and package managers write a lot to disk, and none of them clean up after themselves. On the Mac this was built on, free space fell by more than 180 GiB in three days. It went into Codex worktrees and recovery copies, dated experiment builds, Android and iPhone build output, install caches, simulators and a Windows VM. Deleting things by hand every day didn't keep up, and Finder's Large Files view couldn't say what wrote a folder, whether it was still in use, or whether it would come back.

Context Cleaner answers those questions for the places where this data piles up, and keeps a history so you can see where the space went.

- **How much can I get back?** One number at the top of the Overview, split by what removing it costs.
- **Where did it go?** This week's change in used space, grouped by place (Codex worktrees, task outputs, simulators), with each folder one click away.
- **Can I remove this?** Every folder gets an answer, a short reason, the evidence behind it, and the steps to remove it yourself.

### At a glance

| | What to expect |
|---|---|
| **Answers** | Safe to remove, Rebuildable, Might hold work or Leave it, ranked by what removing costs |
| **Evidence** | Newest file change, read-only git status, whether git ignores the folder, open files, and Xcode's own simulator data |
| **Inside folders** | Dated experiment builds and old downloads inside folders you still use, listed with dates and sizes |
| **History** | Every cleanup you did (what was moved, what wasn't), disk space every hour while open, and folder sizes at every scan |
| **Coverage** | 33 known places across AI tools, developer tools, virtual machines, games and Downloads, plus folders you add |
| **Everything else** | A read-only look at the rest of your home folder, with known folders explained and git projects marked backed up or not |
| **Deletes** | Nothing, ever. You remove things, and space comes back when you empty the Trash |
| **Needs** | An Apple silicon Mac with macOS 14 or later |

## What's new

**0.18 is built around Free up space, and makes the Trash command dependable for any number of folders:**

- **Free up space comes first.** The Overview opens with free space and "You can get back", then the list. Select All and Copy sit above the list, so they're in reach however long it is, and the list scrolls inside its panel.
- **Select All, by answer.** Filter the list to Safe, Rebuildable or Might hold work, each with its count and size, and tick everything shown in one click. Select All never ticks backups, saves, recovery copies or private copies; tick those yourself.
- **Backups are never called rebuildable.** A folder named like a backup, save, recovery copy or private copy is "Might hold work", even inside a `build` or `generated` folder. On the Mac this was built on, that caught dated iPad backups that 0.17 listed as an old build.
- **Checked again before copying.** When you click Copy, each item is rechecked: still there, no app has a file open in it, and nothing in it changed since the scan. Anything that fails is left out, and you're told why. The button shows what happened: Checking, Copied 82 of 84, or Nothing copied.
- **A Trash command that works for 1 item or 400.** It moves each item with macOS's own `trash` tool, which is instant and never shows a dialog, and falls back to Finder for a read-only folder, saying first that macOS may ask for your password. It prints a line per item (Moved, Already gone, or NOT moved with the reason) and counts them at the end. An item only counts as moved once it's gone. An Android emulator goes with its `.ini` file.
- **History shows your cleanups.** Scan History is now **History**, with **Cleanups** first: every command you copied, what was moved, what's still in place, and what was left out and why.
- **Clearer answers.** "Your call" is now **Might hold work**. Every list and tile says what the answers mean: Safe is not needed again, Rebuildable is recreated by the next build, Might hold work may be the only copy, so look first.

**0.17 tells you what to remove right now:**

- **Free up space**, right under the chart: one list, biggest first, of everything safe plus everything nothing has touched or opened for the time you pick (12 hours, 1 day, 3 days or a week). That covers idle build output, Codex scratch, scratch work folders, recovery copies, Android emulators, and old runs inside folders you're still using. Each row says what removing it costs and how long it has sat untouched.
- **Tick rows and copy one command** for all of them, with a running total.
- **The Trash command reports back.** It moves each item on its own, skips any that are already gone, and prints "Moved 3 of 3 items to the Trash". Context Cleaner watches those folders and confirms when each one has left, then reminds you to empty the Trash.
- **Hours, not "today".** A folder untouched for 20 hours says so, instead of looking busy.
- **Scratch folders say what they are**, and rescanning a folder you removed says it's gone.

**0.16 finds the space that was hiding in "Everything else":**

- **Codex scratch is scanned.** On the Mac this was built on, `~/.codex/scratch` held 274 GiB that no view showed: fresh-clone test homes, device backups and build outputs from finished tasks. Each task folder now gets its own row, size, last use and answer.
- **Ollama models, DiffusionBee and Android emulators are scanned too**, each with how to remove them properly (`ollama list` and `ollama rm`, DiffusionBee's settings, Android Studio's Device Manager).
- **Is this project backed up?** Open any folder in Everything else. Git projects and Codex worktrees say whether every commit is pushed, nothing is uncommitted or stashed, and which ignored files, such as `ref/` or `.env`, git would not keep. Projects that are fully backed up and unused for a month are added up, with a Move-to-Trash command to copy. A repository that other worktrees use is never offered.
- **Known folders are explained**, such as Ollama, Gemini and Antigravity, the Android SDK, Rust toolchains, conda and backups.
- **Charts read one way.** Everything is space used: the line climbs toward a dashed Full line, and bars go up on days that used space and down on days that freed it. The headline, axis, hover and caption agree, and days before tracking began aren't drawn.

**0.15 makes it easier to know where you are and what everything means:**

- **Back and Forward** (⌘[ and ⌘]) in the toolbar. Open a folder from the Overview, dig into it, and go back to exactly where you were.
- **Every folder card shows its full path** and an **Up to** link to the folder it sits in. Subfolders are named for themselves, such as "project_dex_archive in Android build intermediates".
- **Copy Move-to-Trash Command on every card.** It asks Finder to move the folder, so **Put Back** works and same-named folders don't collide. You run it; Context Cleaner never does.
- **Biggest first** is the default order in Folders.
- **One vocabulary.** **Ignore** is your choice, so the folder is never suggested. **Leave it** is the app's answer for app libraries you manage inside their own apps.
- **How fast it's growing.** Where the space went shows each place's change and its rate per day.
- **A shorter Overview**, and a chart you can click and drag.
- **Everything else, explained.** Click it to see what it is, and **Look Inside** sizes the rest of your home folder, Library and Applications. It's read-only and saves nothing.

**0.14 is a speed release.** Nothing it shows changed, only how fast it gets there:

- **Scans use about 40% less CPU** and finish about 25–35% sooner on big build folders. Each directory is read in batches with one system call instead of one call per file, with identical results.
- **Launch reads your saved history in parallel**: about 0.2 s instead of 0.5 s for 21 scans.
- **The interface does half the work per scan update**, and the Folders table no longer re-sorts on every click.

See the [0.14 validation record](docs/validation/Final%20validation%200.14.0.md) for before and after measurements.

**0.13** made the Overview calmer and clearer:

- **One color system.** Green is safe or freed, soft green is old items, cyan is rebuildable, orange is your call, gray is keep, purple is ignored, blue is used space and growth, and red means a scan couldn't read something. Each color means the same thing everywhere.
- **Where the space went is clickable** and follows the chart: pick 24 hours, 7 days or 30 days, click a day, or drag across a span.
- **Scan History you can read**: each scan's net change, what grew and shrank most, and anything it couldn't read.
- **A calmer Overview**: one Scan button in the toolbar, a shorter Start here list, and Kept renamed **Ignored**.
- **Shorter answers**, and old scans no longer hold their folder listings in memory.

Earlier releases: [0.12](docs/validation/Final%20validation%200.12.0.md) added "You can get back", old experiments inside build folders and the four answers. [0.11](docs/validation/Final%20validation%200.11.0.md) stopped calling recently used caches safe. See [all releases](https://github.com/chrissotraidis/contextcleaner/releases).

## How it works

```mermaid
flowchart LR
    A["Known places<br/>Codex, Xcode, caches, VMs"] --> B["Scan<br/>sizes and dates only"]
    B --> C["Evidence<br/>file dates, git, open files, Xcode"]
    C --> D{"What does<br/>removing cost?"}
    D -->|nothing| E["Safe to remove"]
    D -->|a rebuild| F["Rebuildable"]
    D -->|maybe your only copy| G["Might hold work"]
    D -->|breaks the app| H["Leave it"]
    E & F & G --> I["You remove it<br/>in Finder or Terminal"]
```

1. **Scan.** Context Cleaner reads the places where apps are known to pile up data. It records each folder's size, file count and newest change, plus the top level of what's inside. It never opens, changes or deletes a file.
2. **Evidence.** For project folders it reads git, read-only: the last commit, whether the branch is merged, uncommitted changes, whether a worktree is still registered, and whether git ignores the folder. Simulators come from Xcode's own device list. Folders with open files name the app using them.
3. **Answer.** Each folder gets one of four answers, with the reason and the evidence shown on its card.
4. **You decide.** Every card has **Show in Finder** and removal steps. Where it helps, it offers a command to copy, such as `git worktree remove`, `xcrun simctl delete`, or a move-to-Trash command for old items. Context Cleaner never runs them.

## Can I remove it?

| Answer | What removing it costs | Examples |
|---|---|---|
| 🟢 **Safe to remove** | Nothing: you won't need it again | Idle package caches, Xcode DerivedData, iPhone install caches, build output from finished projects |
| 🔵 **Rebuildable** | Waiting for the next build or download | Build output and caches you used this week |
| 🟠 **Might hold work** | It may be the only copy of something | Recovery copies, backups, scratch `work` folders, virtual machines, folders git tracks |
| ⚪ **Leave it** | Breaks the app | Chat history, app libraries |

**Old items inside** are counted on their own. Codex worktrees and project `build`, `generated` and `work` folders keep one subfolder per build or experiment. When one of those folders is still in use, every subfolder untouched for 7 days or more is listed with its date and size (30 days for caches). On the Mac this was built on, that found 205 GiB, including a single 33 GiB experiment build from ten days earlier.

A few rules keep the answers honest:

- **Recent use beats "rebuildable".** A cache used this week is never called safe.
- **Git decides what's build output.** A `build` folder that git tracks may hold source, so it might hold work.
- **Backups are never build output.** Anything named like a backup, save, recovery copy or private copy might hold work, wherever it sits.
- **Finished worktrees say so.** A worktree that's merged, clean and quiet for two weeks offers `git worktree remove`, which git refuses if anything is uncommitted.
- **Simulators are listed by name**, such as "iPhone 17 Pro · iOS 26.5", with size and last use from Xcode.
- **Your choice wins.** Right-click any folder to **Ignore This Folder** (still scanned, never suggested) or **Stop Scanning This Folder**. Both move it to **Ignored**.

## A tour

![Where the space went, with Codex worktrees expanded to show which build folders grew, next to Start here listing the folders with the most old items](docs/images/where-it-went.png)

<sub><b>Where the space went</b> and <b>Start here.</b> Click a place to see which folders grew. The Old items tab lists the folders holding the most untouched builds.</sub>

![Everything else with ~/.codex and its worktrees open. Each worktree says whether it is backed up: pushed and clean in green, or what isn't, such as 1 file not committed or ignored files git doesn't keep, in orange](docs/images/everything-else.png)

<sub><b>Everything else.</b> Open any row to go a level deeper. Known folders say what they are, and each project or Codex worktree says whether it's backed up.</sub>

<table>
  <tr>
    <td width="50%"><img src="docs/images/folders-git.png" alt="Folders view with a Codex worktree build folder selected. The card reads Rebuildable, shows git evidence, and lists 19 old experiment folders such as evening-20260921 at 33 GiB"><br><sub><b>Folders.</b> Biggest unused first. Each card shows the answer, git evidence, old items with dates, and how to remove it.</sub></td>
    <td width="50%"><img src="docs/images/scan-history.png" alt="Scan History with the latest scan expanded: minus 15 GiB since the scan before, with the folders that grew and shrank most"><br><sub><b>Scan History.</b> Each scan's net change, and which folders grew and shrank most.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/cleanup-list.png" alt="Export cleanup list preview showing a Markdown checklist of safe folders with sizes, paths and removal steps"><br><sub><b>Cleanup list.</b> A Markdown checklist with paths and steps, saved on your Mac (⇧⌘E).</sub></td>
    <td width="50%"><img src="docs/images/scan-sheet.png" alt="Scan your folders sheet listing AI tools, developer tools, virtual machines, games and Downloads with sizes and a What happens section"><br><sub><b>Scan sheet.</b> What it will read, biggest first, and what happens before you start.</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/ignored.png" alt="Ignored view listing folders that aren't scanned, 551 GiB in total, with OpenEmu and CrossOver libraries"><br><sub><b>Ignored.</b> Folders you keep out of suggestions or don't scan, with their share of the disk.</sub></td>
    <td width="50%"><img src="docs/images/settings-coverage.png" alt="Settings, Coverage tab, with AI tools expanded: Codex worktrees 492 GiB, recovery copies 94 GiB and more, each with a switch"><br><sub><b>Coverage.</b> Every place it looks, biggest first, each with a switch.</sub></td>
  </tr>
</table>

<p align="center"><img src="docs/images/overview-light.png" alt="The Overview in light mode" width="70%"><br><sub>Light mode follows your Mac, or pick it in Settings (⇧⌘L).</sub></p>

## What it looks at

Context Cleaner reads the places where apps are known to pile up data, plus any folders you add. It isn't a whole-disk scanner, so its totals never equal your used space; the Overview shows the rest as "Everything else".

| Group | Places |
|---|---|
| **AI tools** | Codex worktrees, scratch, recovery copies, tasks, conversations and outputs; Claude; Hugging Face; LM Studio; Ollama; DiffusionBee |
| **Developer tools** | Build folders in `~/GitHub`; Xcode DerivedData and device support; simulators; iPhone install caches; npm, npx, pip, uv, Yarn, Gradle, Homebrew and Playwright caches |
| **Virtual machines** | Parallels, Docker Desktop's disk, UTM, Android Emulator devices |
| **Games and emulators** | Steam, CrossOver, OpenEmu |
| **Downloads** | Your Downloads folder |

It never looks at system files, other users' folders, Photos, Mail, Messages or iCloud Drive libraries, or Time Machine snapshots. Turn any place off in **Settings › Coverage**.

## Reading the Overview

![The space-used chart: 141 GiB more space used over 7 days, a blue line climbing toward a dashed Full line, with 110 GiB free now](docs/images/overview-chart.png)

- **The chart.** Everything is space used. The blue line climbs toward the dashed **Full** line as your disk fills, and the headline is how much more (or less) is used over the range you pick. Point at the chart for a reading, click a day to look closer, or drag across a span. **Change per day** switches to bars: up and blue used space, down and green freed it.
- **You can get back.** Safe folders, old items inside folders and rebuildable output added together, each byte counted once. The bar below splits your whole disk by answer; click a color to list those folders.
- **Where the space went.** The chart's range split by place. New folders count in full, and "Everything else" is what the app doesn't scan.
- **Everything else.** Click it, then **Look Inside** to size the rest of your home folder, Library and Applications. Open any row to go a level deeper. Known folders say what they are, and git projects say whether they're backed up.
- **Free up space.** What to move to the Trash now, biggest first, with what each costs. Pick how long something must sit untouched, tick rows, and copy one command.

Readings come from every scan and from an hourly check while the app is open. Gaps mean the app wasn't running; nothing is filled in.

## Getting started

1. Download the DMG from [the latest release](https://github.com/chrissotraidis/contextcleaner/releases/latest), open it and drag **Context Cleaner** to Applications.
2. The build is signed but not notarized. Open Context Cleaner, choose **Done** when macOS says it can't verify the app, then go to **System Settings › Privacy & Security** and choose **Open Anyway**. You do this once per version.
3. Choose **Scan Folders…** (⌘R), check the list, and choose **Start Full Scan**. A first scan takes a few minutes, and you can stop at any time.
4. macOS may ask whether Context Cleaner can read other apps' data (such as iPhone install caches) or your Documents folder. The scan waits for your answer. Either way, it only reads sizes and dates.
5. Optional: turn on **Full Disk Access** from **Settings › Scanning**. It stops those questions and lets the app show how much your Trash holds.
6. Start with **Free up space** on the Overview. Tick what you want gone, copy the command, and paste it in Terminal.

## Frequently asked questions

### Does it delete anything?

No. It has no delete, clean, Trash, uninstall or reset button. It shows you where a folder is and how to remove it, and you decide. Commands it offers are copied for you to run yourself.

### Why is "safe to remove" so much smaller than what I can get back?

Because most big folders on a working Mac are in use. "Safe" means nothing is lost at all. The big wins are usually **old items** inside your build folders and **rebuildable** output from projects you're still working on, which only cost a rebuild. The headline adds all three.

### How does it know a project is backed up?

It asks git, read-only and without going online. A project counts as backed up when it has a remote, every commit on its branches is on that remote as of your last fetch, and nothing is uncommitted or stashed. A Codex worktree only needs to be clean on a branch, because its commits stay in the main repository when the folder goes. Files git ignores, such as `ref/` game data or `.env`, are never backed up by git, so they're named. Build folders and caches aren't.

### What's the difference between Safe and Rebuildable?

Neither loses anything. **Safe** means you won't need it again: its project is finished, or it has sat unused for weeks. **Rebuildable** means you're still using it, so the next build or download recreates it and you wait for that.

### What does "Might hold work" mean?

The folder may hold the only copy of something: a Codex recovery copy made before a risky change, a backup of a device, a scratch `work` folder with hand-made files, a virtual machine, or a `build` folder git tracks. Each card says what to check first. Select All never ticks backups.

### What does the Move-to-Trash command do?

It moves each item to the Trash, one at a time, and prints what happened to each: `Moved`, `Already gone`, or `NOT moved` with the reason. It uses macOS's `trash` tool, and Finder for anything that tool refuses. Before copying it, Context Cleaner rechecks every item and leaves out anything that's open in an app or changed since the scan. It watches the items until they're gone and records the cleanup in History. **Put Back** works in the Trash, and nothing is deleted until you empty it.

### Why does removing a folder free less than its size?

APFS shares storage between copies of files, so some space only comes back when every copy is gone. Space also only comes back after you empty the Trash.

### Does it send my data anywhere?

No. It has no network code, accounts or analytics. Scans, settings and disk readings are saved as files under `~/Library/Application Support/Context Cleaner`. The cleanup list stays on your Mac unless you share it.

### How does it know what a folder is?

From where the folder is, plus evidence. Each place in [What it looks at](#what-it-looks-at) has a known owner and purpose, such as npm's download cache or Xcode's build data. Location suggests which app writes to a folder but doesn't prove it, so the card shows the evidence behind each answer.

### Can I stop it suggesting a folder?

Yes. Right-click it and choose **Ignore This Folder**, or **Stop Scanning This Folder** to leave it out of scans. Both are listed under **Ignored**, with their total.

### Does it run in the background?

Only while it's open. Scheduled checks are off by default; turn them on in **Settings › General**.

## Privacy and your data

Scans read folder sizes, dates and git status only, and never open, change or delete files. Git is always read with optional locks off, so even git's index isn't touched. Every scan, setting and hourly reading is saved as a new file, and nothing is rewritten or pruned.

## Build from source

Requires an Apple silicon Mac with macOS 14 or later and Xcode 27. There are no third-party dependencies.

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

Six suites (294 checks) cover preservation, folder contents, scan limits, planning, discovery and model state, and the Overview's numbers. They run on fixtures only, and every fixture and log is kept.

## Documentation

- [Design and copy rules](docs/DESIGN.md)
- [Validation records](docs/validation), one per release, with evidence and limits
- [Goal loops](docs) behind each release, such as [0.17](docs/GOAL_LOOP_0.17.md) and [0.16](docs/GOAL_LOOP_0.16.md)

## Getting help

Join the [Discord](https://discord.gg/xwHfUD2bxW), or [open an issue](https://github.com/chrissotraidis/contextcleaner/issues/new/choose) with your macOS version, the Context Cleaner version (**Context Cleaner › About**), and what you expected to see. Check screenshots and paths for anything private before posting.

## Credits

Built with SwiftUI and Swift Charts, with no third-party code. The folder knowledge comes from how Codex, Xcode, CoreSimulator, CoreDevice, Gradle, npm and the other covered tools lay out their data.

## License

No open-source license has been chosen yet, so the code isn't licensed for reuse. Context Cleaner is an independent project, not affiliated with OpenAI, Apple or any of the tools it looks at.
