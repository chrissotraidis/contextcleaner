# Context Cleaner 0.6.0 — contents browser and stable layout checkpoint

Native SwiftUI macOS 14+ app, Apple Silicon. Local ad-hoc signing only; not notarized for public distribution.

## Non-negotiable preservation boundary

No deletion, Trash action, cleanup, pruning, uninstall, reset, or worktree removal. Scanning reads metadata. New scan and preference records append to fresh JSON files through O_EXCL; existing destinations are refused. Finder actions reveal a location only. Existing SpaceCheck history, earlier sources, builds, fixtures and artwork remain preserved.

## This version

- Real overview dashboard: current home-volume total/used/free ring, capacity refresh, and recorded free-space chart.
- Clickable category bars and largest-location cards. Parent and child locations are counted once in category totals; these are asynchronous saved measurements, not whole-disk or reclaimable-space accounting.
- Folder size history on the default inspector, colored category icons, full size labels, expandable evidence and paths, and visible Scan Again.
- Simulator device names and runtimes from small local plist files, searchable device list, and explicit per-device measurement. Container identity includes parent device metadata where accessible.
- System/light/dark appearance for the current app session; adaptive readable accent colors.
- Bundled macOS ICNS icon, derived from the existing generated icon concept. The transparent PNG source is retained in Assets.

Build: `bash build-version.sh /absolute/path/to/a/NEW/checkpoint-directory`.
The script refuses an existing destination. Every stage is retained in `~/Library/Application Support/Context Cleaner Development/Builds/<UUID>`. A new Package directory is copied from the new app; iconset intermediates remain outside the DMG payload. No cleanup traps or destructive commands.

Core, detail, scan-limit, planner and discovery tests require Planner.swift, Contents.swift, Domain.swift, Classifier.swift, Store.swift, Inventory.swift, Activity.swift, Coverage.swift, Design.swift, OverviewData.swift and Model.swift plus the matching *Tests.swift file. Overview tests require Domain.swift, Contents.swift, Classifier.swift, Inventory.swift, OverviewData.swift and OverviewTests.swift. Discovery/model tests add OverviewData.swift and Model.swift. Always compile to a new executable path. Core, detail, limit and discovery tests take a fixture-parent path and retain every UUID fixture. Planner and overview tests make no filesystem mutations.

App-owned history: `~/Library/Application Support/Context Cleaner`. Artwork source: `Assets/ContextCleaner.png`. Current checkpoint: `../Context Cleaner 0.6.0-checkpoint-04/Context-Cleaner-0.6.0.dmg`.

See `../Context Cleaner Review/Visual refresh checkpoint 0.4.0.md` for evidence, limits and remaining goal work.

## Scanner durability in 0.5

- Streaming directory traversal: at most 128 open directory handles, no whole-directory pending queue. Retained child summaries are limited to the first 512 names alphabetically, explicitly incomplete above that count.
- Manual allowance: 120 seconds / 1,000,000 entries per location, 15 minutes per measurement pass. Priority allowance: 10 seconds / 100,000 entries per location, 90 seconds per measurement pass, up to 12 non-overlapping locations. These are cooperative bounds: an individual filesystem or macOS permission request can outlast them. Discovery and activity lookup are separate stages.
- Incomplete or denied measurements withhold partial sizes. Needs Attention exposes pending, unavailable and limited locations. Scan history preserves coverage, requested count and stop reasons.
- Cancel Discovery and Cancel Scan, plus Escape; current discovery path and a permission-wait explanation. Cancellation waits for the current OS request to return.
- Discovery snapshots append separately from measurements. Newly found locations survive restarting without fake size, timestamps or history; partial discovery retains the existing inventory.
- Daily priority attempts are recorded before they begin, so a cancelled attempt does not retry every five minutes. The app must remain open; this preference remains off on the development machine.
- Bounded process-handle evidence: 15-second helper deadline, 16 MiB output cap, cancellation of only the helper started by this app. Open handles are not proof of writes.

Final validation for 0.5: `../Context Cleaner Review/Final validation 0.5.0-checkpoint-05.md`.

## What 0.6 adds

- Contents browser: every retained child of a measured folder is searchable, sortable by size or name, filterable to folders only, and revealed 30 at a time. The child-change table is searchable the same way. Retained-name limits and skipped-entry counts stay visible so the browser never implies whole-disk coverage.
- Appearance (System/Light/Dark) is saved with preferences and restored on relaunch; unrecognized values are ignored rather than stored.
- Table and inspector use a fixed proportional split instead of a resizable split view. The previous split view reported a width larger than the window at moderate sizes and pushed the header, table and inspector past the visible edge. The inspector now takes about a third of the detail area, between 340 and 520 points, and nothing overflows at any window size from the 1100-point minimum upward.
- Decorative category and file-type icons are hidden from VoiceOver so the inspector header no longer announces raw symbol names and contents rows no longer announce "Move". Every interactive control keeps an explicit label.
- Checkpoint 01 introduced the browser and appearance persistence; checkpoint 02 tried an auto-hiding sidebar, which did not resolve the overflow; checkpoint 03 replaced the split view; checkpoint 04 adds the VoiceOver fixes. All four images are preserved.

Final validation: `../Context Cleaner Review/Final validation 0.6.0-checkpoint-04.md`.
