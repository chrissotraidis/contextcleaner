# Context Cleaner

**Find what’s filling your Mac. Understand it before you act.**

Context Cleaner shows large folders, tracks their growth, and explains which apps or projects they belong to. It helps you investigate recurring storage problems without handing over control of your files.

**It never deletes files.** There is no cleanup, Trash, uninstall, pruning or reset command. You decide what to do in Finder.

## Start here

1. Choose **Scan Folders…**. Review the apps and paths included, then choose **Start Scan**.
2. Open **Folders** to sort by size or filter to **Not scanned**, **Growing**, or **Caches & builds**.
3. Select a folder to see its purpose, project, saved sizes and supporting evidence. **Scan Folder** checks just that folder; **Show in Finder** reveals it.
4. Add recurring concerns to your **Watchlist**. Optional daily or weekly checks are in **Context Cleaner → Settings…** (⌘,). They run only while the app is open and are off by default.

Scans read directory metadata. They do not inspect every file’s contents or scan your entire Mac. Settings → Coverage lists the known paths, your added folders and exclusions.

## A clearer view of your storage

| View | What it answers |
|---|---|
| **Overview** | How much space is free? What changed? Which scanned folders take the most space? |
| **Folders** | What is in this folder, what uses it, and how large is it? |
| **Watchlist** | Which folders should I keep checking? |
| **Scan Issues** | Which scans could not finish, and what can I try next? |
| **Scan History** | Which folders were checked, when, and with what result? |

### New in 0.8.0

- **A scan preview with a clear scope.** See included apps and exact paths before starting. Stop a scan at any time.
- **A readable free-space chart.** Real sample dates, labelled units and a plain-language change. Its latest point matches the storage card; it represents whole-disk free space, not growth attributed to a particular app.
- **Unscanned is not an error.** Pending folders have their own filter. Scan Issues is reserved for access problems, limits, missing folders and failures.
- **Useful scan history.** Entries name the folder and result. Expand one for sizes, comparison details and the free space recorded at the time.
- **Simpler folder details.** One folder-scan button, one Finder button, details on demand, and no empty graph pretending to show history.
- **Plain category names.** Project files, App libraries and Test devices replace technical labels. Generic build folders identify their project.

Native ⇧-click and ⌘-click selection shows a combined size without counting a selected parent and its children twice. Tags, notes, expected growth and exclusions remain available from the folder menu. A report preview lets you inspect a local Markdown report before saving it to a new file.

## What the numbers mean

- **Free space** is a reading from macOS for the volume containing your home folder. The chart combines saved scan readings with the latest capacity check. Refreshing capacity does not scan folders or save a standalone history record.
- **Folder totals** use the latest complete measurement of each included folder. Parent/child overlaps are counted once. The readings can come from different dates and do not cover the entire disk.
- **Growth** requires comparable scans. The app cannot reconstruct what happened before it started recording, or reliably identify a historical writer from a path alone.
- **A cache is a clue, not a deletion guarantee.** Rebuilding can take time. App libraries, test devices, recovery copies and project folders can contain unique work, saves or other personal files.
- **Allocated size is an estimate.** APFS shared blocks, snapshots and unavailable folders mean these totals are not guaranteed recoverable space.

## Privacy and preservation

Scanned folders are read-only. Scan history and preferences are saved locally as new JSON records under `~/Library/Application Support/Context Cleaner`; older records and existing SpaceCheck history stay untouched. There is no automatic record cleanup. Reports stay local unless you share them yourself. Existing export files are never replaced.

If macOS blocks a folder, the app explains how to grant access. Incomplete sizes are withheld rather than presented as complete.

## Build and run

Apple Silicon, macOS 14 or newer. Built with Xcode 27.0; newer toolbar styling is availability-gated. These builds are locally ad-hoc signed, **not notarized for public distribution**.

Use a new output directory for each build:

```sh
bash build-version.sh /absolute/path/to/new-build-output
```

The output contains the DMG, checksum, source revision/status and icon provenance. The script refuses an existing destination. Build stages remain under `~/Library/Application Support/Context Cleaner Development/Builds/<UUID>`; nothing is cleaned automatically.

The Blue C icon is the default. To build the preserved alternative, pass `Assets/IconCandidates/StorageGauge.png` as the second argument.

## Development and validation

Run all six regression suites while keeping every fixture and log:

```sh
bash test-preserving.sh /absolute/path/to/new-test-output
```

The suites cover preservation, metadata, scan limits, planning, discovery/model state, totals, chart readings and history summaries. The 0.8.0 run passed **167 checks**. Native UI verification is separate from these automated checks.

[Design and copy rules](docs/DESIGN.md) · [0.8 goal loop](docs/GOAL_LOOP_0.8.0.md) · [0.8 validation and limits](docs/validation/Final%20validation%200.8.0.md)
