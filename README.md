# Context Cleaner

See where storage goes, what grows, and what it belongs to. Context Cleaner is a native macOS app that helps you investigate folders and decide what to review in Finder. **It never deletes files.**

## Version 0.7.0

- A compact Overview with used/free capacity, stable seven-day free-space history, category totals and clickable largest locations.
- Five destinations: Overview, Locations, Watching, Needs Attention and History.
- Native multi-selection with a combined size that counts nested folders once. Filters and navigation keep the inspector aligned with visible selections.
- Folder timelines, project/app associations, simulator identities and evidence that separates observation from inference.
- Watching for recurring growth, expected-growth notes, tags and exclusions. Significant measured growth can add a location to Watching, with undo.
- Native Settings (⌘,) for appearance, bounded scans, optional daily/weekly checks while open, and an explicit catalog of covered locations.
- Local Markdown report preview before saving. Files with existing names are never replaced.
- Two icon builds: Blue C and Silver Gauge. System controls and toolbar styling adapt to macOS and light/dark appearance.

Apple Silicon, macOS 14 or newer. These builds are locally ad-hoc signed, **not notarized for public distribution**. The implementation was built with Xcode 27.0; newer toolbar styling is availability-gated.

[Validation and limits](docs/validation/Final%20validation%200.7.0.md) · [Design](docs/DESIGN.md) · [Completed goal loop](docs/GOAL_LOOP.md)

## Scanning and privacy

Scan Now discovers and measures included known tool locations plus folders you add. Coverage lists the exact paths and exclusions. This is not a whole-disk scanner. Scheduled checks run only while the app is open; they are off by default.

Folder sizes are allocated-space estimates from different observation times. APFS sharing, snapshots, inaccessible areas and nested folders mean these totals are not guaranteed reclaimable space. A known path or an open file handle does not prove which process wrote historical data. Missing history stays unknown.

No delete, Trash, cleanup, pruning, uninstall or reset feature exists. Scans read directory and tool metadata. Finder actions reveal locations; you decide what to do there. Scan history and preferences append to new JSON files under `~/Library/Application Support/Context Cleaner`. Existing SpaceCheck history stays untouched.

## Build

Use a new output directory for every build:

```sh
bash build-version.sh /absolute/path/to/a/new-output-directory
# Optional alternative icon:
bash build-version.sh /absolute/path/to/another-new-output-directory Assets/IconCandidates/StorageGauge.png
```

The output contains a verified DMG, SHA256, source revision/status and icon provenance. The script refuses an existing output directory. Every build stage remains under `~/Library/Application Support/Context Cleaner Development/Builds/<UUID>`; nothing is cleaned automatically.

## Validation

Six suites cover preservation, metadata/contents, scan limits, planning, discovery/model state, and Overview arithmetic. Latest results: **154 checks passed**. [Test commands and evidence](docs/validation/Final%20validation%200.7.0.md).

[Earlier checkpoint notes](docs/README-before-release-0.7.0.md) remain preserved for provenance.
