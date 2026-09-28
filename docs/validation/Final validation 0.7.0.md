# Final validation — Context Cleaner 0.7.0

2026-09-28. Local release acceptance for the approved overhaul. App source commit: `fc7f0f2ef4e06065eda418de59416806cc8dd3bd`. Later release-documentation commits do not change the packaged app. No files were deleted, trashed, pruned or reset.

## Delivered behavior

The five-destination shell, native Settings, explicit coverage catalog, compact Overview, fixed chart domains, selection totals, automatic Watching with undo, inspector disclosures, timeline History, report preview, cached model state and new icon options are implemented. Native toolbar grouping uses `ToolbarSpacer` on macOS 26+; earlier supported systems use their native fallback. Xcode 27.0 (27A266a), arm64 target, macOS 14 minimum. No custom fixed corner radii.

Final review also corrected legacy Recurring preferences to participate in the single Watching feature, disabled single-folder rescan for multiple selections, distinguished missing paths from access/errors in Coverage, avoided nested History delta double-counting, and cleared hidden selections after navigation or filtering.

## Tests and preservation

| Suite | Passed |
|---|---:|
| Core | 28 |
| Detail | 22 |
| Scan limits | 25 |
| Planner | 19 |
| Discovery/model | 42 |
| Overview | 18 |
| Total | 154 |

The full six-suite run is retained in task `work/cc-release-tests-v1` (152 checks). After the final selection fix, the affected Discovery/model suite was recompiled and passed 42 checks, including two new regression checks; its fixtures are in `work/cc-release-selection-fixtures`. All fixtures and older records remain. Full optimized builds compiled the final SwiftUI implementation successfully.

Core/Detail/ScanLimit/Planner/Discovery compile with `Sources/{Planner,Contents,Domain,Classifier,Store,Inventory,Activity,Coverage,Design,OverviewData,Model}.swift` plus the matching test file, `-swift-version 5 -O -target arm64-apple-macos14.0 -parse-as-library`, and SwiftUI/AppKit/Charts frameworks. Overview compiles with Domain, Contents, Classifier, Inventory, OverviewData and Coverage plus OverviewTests. Always choose a fresh executable path. Core, Detail, ScanLimit and Discovery take a fixture-parent argument and retain UUID fixtures; Planner and Overview do not mutate the filesystem.

The sole app data-writing primitive uses `O_CREAT | O_EXCL | O_NOFOLLOW`; existing output files are refused. Source audit found no filesystem deletion APIs or destructive shell commands in app sources, tests or packaging. Legacy `SpaceCheck/history.json` SHA256 remains `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4`.

## Real UI checks

- Light and dark Overview inspected at 1100 × 752 points (1100 × 700 content) and 1218 × 832 points. All primary Overview content fits without vertical scrolling. Chart axes remained stable through appearance and navigation changes.
- New Blue C and Silver Gauge icons both render in their packaged apps. Both builds launch with the existing history.
- Overview drill-down opens the matching location and inspector. Shift-selection of OpenEmu plus Simulator yields 595.71 GiB in the combined summary; multi-selection disables Rescan This Folder. The final release clears this unrelated selection on entering Needs Attention.
- Native table scrolling across three pages retained selection and returned updated state in about one second, with no observed UI freeze. This is a functional interaction observation, not a frame-rate benchmark.
- Needs Attention statuses render red. Shared multiple-selection actions expose Reveal, Watch, Stop Watching, Exclude and Clear. No deletion actions are provided. Some virtual row accessibility clicks needed a refreshed target or keyboard navigation; this tool limitation is not presented as app performance evidence.
- Settings opens with ⌘,. General/Scanning/Coverage work. Schedule options are Off, Daily while open and Weekly while open; Off was preserved. Coverage exposes full paths, presence and descriptions to accessibility. Access guidance opens without changing system permissions.
- ⌘⇧L changes appearance and updates the toolbar label; Dark was restored. ⌘⇧E opens a report preview with the location count, content description, file size and Save/Cancel controls. The report is a location inventory; opening it from History does not export the scan timeline. No report was sent anywhere.
- History renders preserved scans with timestamps, scope, measurement counts, cancellations and comparable deltas. Earlier checkpoint UI verification exercised bounded scanning/cancellation and retained outcomes; the final pass avoided another broad disk scan.

## Performance

A narrowly scoped, three-second Instruments App Launch recording targeted the exact Blue C release executable at retained build `164EA3EC-BAC4-4331-96CC-917FA33E8DFD`. The exported lifecycle shows initial frame rendering ending at **1.1409915 seconds of trace time**, foreground at **1.14848125 seconds**; first initialization event at 0.430661416 seconds. This measured run meets the under-two-second goal. It is not a repeated cold-launch benchmark.

Evidence: task `work/cc-release-launch-v1.trace` (98 MiB), `cc-release-launch-v1-toc.xml`, and `cc-release-launch-v1-lifecycle.xml`. xctrace returned 54 due to a requested/configured sampling-period warning; the trace and lifecycle export are valid, and the TOC confirms the exact executable path. Instruments terminates its own launched test process when recording ends; the app was then reopened normally for UI acceptance. Earlier exact-build launch evidence is in [checkpoint 10](Performance%20checkpoint%200.7.0-10.md).

Discovery, measurement and coverage presence checks use background work. Derived rows, latest observations, trends and Overview totals are cached with invalidation regression checks.

## Packages

Both packages came from the clean source commit above, verified by their empty `source-status.txt`. Each passed `codesign --verify --deep --strict` and `hdiutil verify`. Output paths below are relative to the original task directory `Documents/Codex/2026-09-25/files-mentioned-by-the-user-screenshot`.

| Icon | DMG | SHA256 |
|---|---|---|
| Blue C | `outputs/Context Cleaner 0.7.0 Release Blue C/Context-Cleaner-0.7.0.dmg` | `d750cb58e849bf8b1fdbed5c00cda627b1fd806ca39e7dc8c9a827339f3ee830` |
| Silver Gauge | `outputs/Context Cleaner 0.7.0 Release Silver Gauge/Context-Cleaner-0.7.0.dmg` | `992a598868ef24706bf4a318d01dd95ca3272497775c94b65ecab6560202b186` |

Silver build retained at `1489FDA9-D819-4AF7-85C2-33C36FAFC717`; Blue at `164EA3EC-BAC4-4331-96CC-917FA33E8DFD`, beneath `~/Library/Application Support/Context Cleaner Development/Builds`. Earlier packages, including ones named Final before the selection fix, are preserved but superseded by these **Release** packages. Both icon options are delivered for user choice; Blue is the build-script default, not a claimed user selection.

## Limits and diagnostic footprint

- Ad-hoc signed only; no Developer ID signing, notarization, Intel build, or clean-machine Gatekeeper acceptance is claimed.
- Scheduling requires the app to remain open. No multi-day monitoring acceptance was performed. Scope changes and incomplete scans interrupt comparisons; historic writers cannot be reconstructed from directory names or present handles.
- Estimates are not whole-disk accounting or promised recovered space. No cleanup is performed by this app.
- Own application history/preferences occupied about **800 KiB** at final review. All retained development builds occupied about **413 MiB**, and task outputs about **121 MiB**.
- A prior Animation Hitches profiler trace unexpectedly grew to about **13 GiB** during finalization. Its owned profiler was stopped; the trace remains at task `work/cc-stage7-scroll-11-a.trace`. It is an optional manual deletion candidate containing failed diagnostic recording data, not app/user documents. The assistant did not delete it. This trace is excluded from scrolling acceptance. See [checkpoint 11](Visual%20checkpoint%200.7.0-11.md).

Source, fixtures, history, icon originals and every earlier checkpoint remain preserved. The release tag is `v0.7.0`; local DMGs are the review deliverables, not a notarized public binary release.
