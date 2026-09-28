# Performance checkpoint 0.7.0-10

2026-09-28. Stage 6 implementation is built; final interaction acceptance remains open.

## What changed

Cached latest measurements, per-folder history and growth, table rows and Overview totals. Cache revisions follow actual mutations, including same-count replacements. Review deadlines expire filtered results. Discovery and filesystem measurement continue on the utility queue.

## Evidence

- All six suites passed: core 28, detail 22, scan limits 25, planner 17, discovery/model 29, Overview 9 (130 total). Eight new regression checks exercise cache invalidation and scan-stop behavior.
- Instruments 27 App Launch trace `work/cc-stage6-launch-10-b.trace` targets the exact retained executable in build `DA12C06C-4C7E-487B-95D8-2E184138B2F8`. Initial frame rendering ended at 1.6857 seconds of trace time; foreground began at 1.7500 seconds. AppKit scene creation took 999.76 ms. The trace begins before process initialization (first initialization event at 0.4779 seconds). Thus this recorded launch meets the under-two-second target.
- Instruments returned status 54 with a sampling-period warning (1 ms requested versus 5 ms configured); the trace and lifecycle events exported successfully. A prior trace resolved an older app copy and is excluded from the acceptance result.
- Independent window-visible probe returned 1.43 s and 0.88 s on checkpoint 09; an intervening 30 s observation timed out. This probe does not establish repeatable performance and is not the primary acceptance evidence.
- Current Overview renders with 208 known locations and 9 saved scans. App sample shows the main thread waiting normally for events, 0% CPU while idle, 70.6 MiB footprint at sampling.
- UI automation reads the current screen but currently fails on sidebar clicks with `cannotClickOffscreenElement` / `noWindowsAvailable`. Smooth scrolling and remaining interaction checks are NOT yet verified.
- Checkpoint 10 DMG checksum verified with hdiutil and ad-hoc signature verified by the build. No notarization claim.
- Legacy history SHA256 remains `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4`.

All paths under work/ and outputs/ are relative to the original task directory in Documents/Codex/2026-09-25/files-mentioned-by-the-user-screenshot. Every fixture, trace and earlier artifact is retained. No deletion operations were run.
