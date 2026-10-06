# Changelog

What changed in each release. Each version's [validation record](validation) says what was checked, and on what.

## 0.21.1

A security and reliability pass. See [SECURITY.md](../SECURITY.md).

- **Git can't be made to run a program.** A folder carrying its own git config could name an fsmonitor or filter program, and reading git status ran it. Every git read now switches those settings off, along with signature checks, hooks and pagers. Without Apple's developer tools, git and simctl aren't run, so macOS's install dialog never appears.
- **Every copied command quotes every name.** The Ollama and "remove worktree" commands could run a name containing `$(…)` or a quote; now they can't. Simulator commands are offered only for real device IDs.
- **Commands expire after an hour.** One pasted later from clipboard history moves nothing.
- **Links are never moved**, at copy time or when the command runs, so what they point to is never touched.
- **Protected places.** A command never holds your home folder, its top-level folders, ~/Library's own folders, keychains, iCloud Drive, SSH or GPG keys, or names with control or invisible characters.
- **fish and other shells** get the command wrapped for zsh.
- **The exported cleanup list no longer holds Trash commands**, which skipped the recheck; copy them in Free Up Space.
- A worktree's `.git` file is read only when it's a small regular file. A stuck git is stopped at its time limit, then forced.
- Built with the hardened runtime.

## 0.21.0

From the [0.20.0 review](IMPROVEMENTS.md#improvements-from-the-0200-review-2026-10-05-evening).

- **Opens on the Overview** again, with Free Up Space second in the sidebar.
- **Nothing lost.** Free Up Space filters by **Nothing lost** (Safe to remove and Rebuildable together) or **Review first**; each row still says which. Empty filters are hidden, so it never shows "0 B".
- **By kind.** Group the list by what each item is (build output, Codex scratch, install caches…), each group with a tick box and its total.
- **One Copy button, which asks when it should.** Folders has a single Copy button for everything selected. A command with Review first items, 20 or more items, or 100 GiB or more asks in place before copying, with the count and size. No pop-ups.
- **Open your terminal.** After copying, a button beside Copy opens Terminal, Ghostty, iTerm, Warp, kitty, Alacritty or WezTerm; pick it in Settings › General. You still paste and run the command yourself.
- **No banner to close.** The button says what it copied; one line in the footer follows the items to the Trash. History records every command.
- **Tick boxes in Folders**, on every row.
- **Where the space went** draws growth to the right and space freed to the left of a center line, under **Grew** and **Freed**.
- **What a scan does.** The first launch opens the scan sheet, which lists what a scan reads, the read-only tools it runs, what it saves and where, and what it never does.

## 0.20.0

Built around the one thing the app is for: getting space back. From the [2026-10-05 review](IMPROVEMENTS.md).

- **Free Up Space has its own page, and the app opens on it.** The list fills the window; the Trash's size sits beside the controls. ⇧⌘C copies the command. The Overview shows one line of what's waiting there.
- **Folders makes commands too.** **Select All** above any list, then one Move-to-Trash command for the Safe to remove and Rebuildable folders, plus a second button that includes the **Review first** ones you've looked at.
- **Plainer answers.** *Might hold work* is now **Review first**; *Leave it* is now **Not for the Trash** and isn't a tile (nothing in it frees space). The tile says **Safe to remove**.
- **Folders that take no space are said to.** A folder whose files are kept only in iCloud is Not for the Trash ("In iCloud only"), since removing it frees nothing here and removes it from iCloud. An empty folder is Safe to remove.
- **Ignored explains "scanning off".** Its size is the last one seen, with when, and **Turn Scanning Back On** scans it again.
- **What's inside Parallels and Ollama.** A virtual machine's card shows its disk image, snapshots, suspended memory and logs; Ollama's shows each model with its size and the `ollama rm` command for it.
- **"Running right now" was wrong.** A virtual machine open at the last scan now says when that was.
- **Old items** on the Overview open Free Up Space at a week, listing each old item; Xcode build folders named after a feature ("DerivedData-…-save") are no longer taken for backups.
- **Everything else sizes itself** when you open it.
- **History** shows what you've moved to the Trash each day for 30 days, totals, and the Trash.
- **Scheduled checks**: Settings shows the last and next check and has **Check Now**. A quick check that can't finish a big folder no longer replaces the size a full scan found, so it doesn't land in Couldn't Scan.
- **Settings** has a gear in the toolbar, a Permission section that says whether Full Disk Access is on, and a tidier layout. **About** says what the app is and links to the project. "Never deletes" appears once.
- **Export Cleanup List** starts with what Free Up Space lists now, and one command for its Safe to remove and Rebuildable items.
- **Faster lists**: the Folders table draws less per row.

## 0.19.1

Tightens the last-second check on whole worktrees, found while checking 0.19.0 end to end:

- **The same git test, again, when you copy.** Copying a Clean worktree now repeats the full test that made it clean: nothing uncommitted or untracked, and nothing ignored that isn't build output, a cache or an exact copy of the main checkout's. 0.19.0 only repeated the first half, so a new file inside an ignored folder such as `ref/` could slip through.
- **The row updates at once.** If that check finds something, the worktree leaves the list right away and its build folder takes its place, instead of keeping its old answer until the next scan.
- "Everything else" no longer says only worktree build folders are scanned.

## 0.19.0

Finds much more to remove, especially what Codex leaves behind:

- **Whole Codex worktrees.** Each worktree is measured whole, and git is asked what's in it. A worktree with every change committed, its commits kept in the main repository, and nothing ignored except build output and caches is listed as **Clean worktree**: Rebuildable, or Safe after a week untouched. The command moves it and then tells git it's gone (`git worktree prune`), so its branch is free again. A worktree with uncommitted work, or files git doesn't keep (such as `ref/` or `private/` that differ from the main checkout's), is never listed whole; its build folders are listed on their own.
- **Nested worktrees.** Codex can wrap a worktree in a folder of its own (`name/repo/.git`). Their build and work folders were never scanned; now they are. On the Mac this was built on, one such `build` folder held 94 GiB.
- **Codex task work folders.** Old experiment runs inside `~/.codex/tasks/*/work` are listed like scratch.
- **Your temporary folder.** Apps and command-line tools leave build trees, Instruments traces and unpacked downloads there, in a folder Finder doesn't show. Items nothing has used for 3 days are listed as Safe, the same rule macOS uses; newer ones as Might hold work.
- **No more stale rows.** Anything that leaves its place, however it went, leaves Free up space within seconds, so a copy never offers items that are already gone. If every item you ticked was already gone, it says so.
- **Where the space went counts what you removed.** A folder you removed counts as space freed in its own place ("GitHub projects −234 GiB · 26 removed"), instead of disappearing into "Everything else".
- **Scans don't stall on iCloud.** Context Cleaner no longer asks iCloud (or any cloud folder) to download anything while reading sizes, and skips macOS's private items in the temporary folder. A Documents folder synced with iCloud had stalled every full scan for minutes.
- **~/Documents/Codex is measured folder by folder**, so one slow folder can't hide the rest, and each folder keeps its 512 biggest items rather than the first 512 by name.
- **Each byte counts once, for the innermost folder that holds it.** A worktree that holds uncommitted work no longer hides its rebuildable build folder in "You can get back".

## 0.18.3

A public-release pass: a shorter README with screenshots made from demo data, this changelog, and release builds signed under the developer's name.

## 0.18.2

Makes selecting more, and running the command, smoother:

- **Long commands stay short.** A command for many items reads its list from a file Context Cleaner saves, so it's one short line to paste whether you picked 5 items or 400. Short ones still spell out every path.
- **Select from Folders too.** Select several folders (⌘A works), and Copy Move-to-Trash Command sits at the top of the summary. It covers the Safe and Rebuildable ones and says what it left out and why.
- **Never a whole Downloads or ~/GitHub.** A Trash command never moves a place Context Cleaner looks in (Downloads, ~/GitHub, Codex scratch) unless that place is a cache, and never model libraries, virtual machines, simulators or chat history.
- **Shift-click** ticks a range in Free up space, **ticks survive** a change of the untouched time, and items down to 100 MiB are listed.
- **Open Terminal** sits next to the copied result.

## 0.18.1

Fixes two things found while recording the demo. Items you moved from inside a folder now leave Free up space at once, instead of waiting for the next scan. Items the recheck leaves out stay ticked, so the Copy button keeps saying what it copied ("Copied 20 of 21").

## 0.18

Is built around Free up space, and makes the Trash command dependable for any number of folders:

- **Free up space comes first.** The Overview opens with free space and "You can get back", then the list. Select All and Copy sit above the list, so they're in reach however long it is, and the list scrolls inside its panel.
- **Select All, by answer.** Filter the list to Safe, Rebuildable or Might hold work, each with its count and size, and tick everything shown in one click. Select All never ticks backups, saves, recovery copies or private copies; tick those yourself.
- **Backups are never called rebuildable.** A folder named like a backup, save, recovery copy or private copy is "Might hold work", even inside a `build` or `generated` folder. On the Mac this was built on, that caught dated iPad backups that 0.17 listed as an old build.
- **Checked again before copying.** When you click Copy, each item is rechecked: still there, no app has a file open in it, and nothing in it changed since the scan. Anything that fails is left out, and you're told why. The button shows what happened: Checking, Copied 82 of 84, or Nothing copied.
- **A Trash command that works for 1 item or 400.** It moves each item with macOS's own `trash` tool, which is instant and never shows a dialog, and falls back to Finder for a read-only folder, saying first that macOS may ask for your password. It prints a line per item (Moved, Already gone, or NOT moved with the reason) and counts them at the end. An item only counts as moved once it's gone. An Android emulator goes with its `.ini` file.
- **History shows your cleanups.** Scan History is now **History**, with **Cleanups** first: every command you copied, what was moved, what's still in place, and what was left out and why.
- **Clearer answers.** "Your call" is now **Might hold work**. Every list and tile says what the answers mean: Safe is not needed again, Rebuildable is recreated by the next build, Might hold work may be the only copy, so look first.

## 0.17

Tells you what to remove right now:

- **Free up space**, right under the chart: one list, biggest first, of everything safe plus everything nothing has touched or opened for the time you pick (12 hours, 1 day, 3 days or a week). That covers idle build output, Codex scratch, scratch work folders, recovery copies, Android emulators, and old runs inside folders you're still using. Each row says what removing it costs and how long it has sat untouched.
- **Tick rows and copy one command** for all of them, with a running total.
- **The Trash command reports back.** It moves each item on its own, skips any that are already gone, and prints "Moved 3 of 3 items to the Trash". Context Cleaner watches those folders and confirms when each one has left, then reminds you to empty the Trash.
- **Hours, not "today".** A folder untouched for 20 hours says so, instead of looking busy.
- **Scratch folders say what they are**, and rescanning a folder you removed says it's gone.

## 0.16

Finds the space that was hiding in "Everything else":

- **Codex scratch is scanned.** On the Mac this was built on, `~/.codex/scratch` held 274 GiB that no view showed: fresh-clone test homes, device backups and build outputs from finished tasks. Each task folder now gets its own row, size, last use and answer.
- **Ollama models, DiffusionBee and Android emulators are scanned too**, each with how to remove them properly (`ollama list` and `ollama rm`, DiffusionBee's settings, Android Studio's Device Manager).
- **Is this project backed up?** Open any folder in Everything else. Git projects and Codex worktrees say whether every commit is pushed, nothing is uncommitted or stashed, and which ignored files, such as `ref/` or `.env`, git would not keep. Projects that are fully backed up and unused for a month are added up, with a Move-to-Trash command to copy. A repository that other worktrees use is never offered.
- **Known folders are explained**, such as Ollama, Gemini and Antigravity, the Android SDK, Rust toolchains, conda and backups.
- **Charts read one way.** Everything is space used: the line climbs toward a dashed Full line, and bars go up on days that used space and down on days that freed it. The headline, axis, hover and caption agree, and days before tracking began aren't drawn.

## 0.15

Makes it easier to know where you are and what everything means:

- **Back and Forward** (⌘[ and ⌘]) in the toolbar. Open a folder from the Overview, dig into it, and go back to exactly where you were.
- **Every folder card shows its full path** and an **Up to** link to the folder it sits in. Subfolders are named for themselves, such as "project_dex_archive in Android build intermediates".
- **Copy Move-to-Trash Command on every card.** It asks Finder to move the folder, so **Put Back** works and same-named folders don't collide. You run it; Context Cleaner never does.
- **Biggest first** is the default order in Folders.
- **One vocabulary.** **Ignore** is your choice, so the folder is never suggested. **Leave it** is the app's answer for app libraries you manage inside their own apps.
- **How fast it's growing.** Where the space went shows each place's change and its rate per day.
- **A shorter Overview**, and a chart you can click and drag.
- **Everything else, explained.** Click it to see what it is, and **Look Inside** sizes the rest of your home folder, Library and Applications. It's read-only and saves nothing.

## 0.14

Is a speed release. Nothing it shows changed, only how fast it gets there:

- **Scans use about 40% less CPU** and finish about 25–35% sooner on big build folders. Each directory is read in batches with one system call instead of one call per file, with identical results.
- **Launch reads your saved history in parallel**: about 0.2 s instead of 0.5 s for 21 scans.
- **The interface does half the work per scan update**, and the Folders table no longer re-sorts on every click.

See the [0.14 validation record](validation/Final%20validation%200.14.0.md) for before and after measurements.

## 0.13

made the Overview calmer and clearer:

- **One color system.** Green is safe or freed, soft green is old items, cyan is rebuildable, orange is your call, gray is keep, purple is ignored, blue is used space and growth, and red means a scan couldn't read something. Each color means the same thing everywhere.
- **Where the space went is clickable** and follows the chart: pick 24 hours, 7 days or 30 days, click a day, or drag across a span.
- **Scan History you can read**: each scan's net change, what grew and shrank most, and anything it couldn't read.
- **A calmer Overview**: one Scan button in the toolbar, a shorter Start here list, and Kept renamed **Ignored**.
- **Shorter answers**, and old scans no longer hold their folder listings in memory.

Earlier releases: [0.12](validation/Final%20validation%200.12.0.md) added "You can get back", old experiments inside build folders and the four answers. [0.11](validation/Final%20validation%200.11.0.md) stopped calling recently used caches safe. See [all releases](https://github.com/chrissotraidis/contextcleaner/releases).
