# Context Cleaner 0.5.0 — final checkpoint validation

2026-09-28, Asia/Tokyo. The overall goal remains active. This is a verified local checkpoint, not a notarized public release or multi-day monitoring acceptance.

## Deliverable

`../Context Cleaner 0.5.0-checkpoint-05/Context-Cleaner-0.5.0.dmg`

SHA256: `e917b5f63efb9ac1184730434e6623506f14ae4fb21d2950da5ddee067383517`

The exact DMG passed hdiutil checksum verification, mounted read-only at `/Volumes/Context Cleaner 0.5.0 2`, and its embedded app passed strict code-signature verification. It is locally ad-hoc signed, Apple Silicon, macOS 14+.

## What changed

The 0.4 dashboard, capacity ring, real history charts, clickable categories, native icon, named simulator context, light/dark appearance and expandable evidence remain. Version 0.5 concentrates on useful scan completion: bounded streaming traversal, smaller priority allowances, incomplete-size handling, explicit Needs Attention, durable discovery, persisted daily-attempt timing, bounded process lookup and cancel/progress controls.

Locations discovered but never measured say Not scanned. Partial discovery merges with the existing inventory and does not postpone the next scheduled rediscovery. Permission failures and scan limits do not become zero-byte totals or invented growth. Manual removal is always outside this app.

## Verification evidence

- 28 core, 22 detail, 25 scan-limit, 11 planner and 12 discovery/model checks passed during this checkpoint work (98 total). The previously verified 9 overview checks cover unchanged dashboard accounting.
- Limits include a 520-child directory retaining only 512 summaries, no growing handle count across 30 limited traversals, entry/depth/time bounds, exclusion and symlink behavior, and withheld partial totals. A process-local permission-denied fixture proves inaccessible state and unchanged payload.
- Discovery/model tests instantiate the real model against an isolated store and restart it. They verify persistent unmeasured inventory, tags/exclusions, no fabricated observations, append-only snapshots and partial-discovery scheduling semantics.
- The real packaged app reopened with 208 known locations and eight preserved scans. Two discovery snapshots remain on disk. Named, newly discovered simulator devices appear in Needs Attention without invented sizes.
- Shift-Command-T opened tags for the selected npx folder. The sheet was cancelled without changing its policy. Shift-Command-R started a selected-folder scan; Escape requested cancellation. The UI showed the stopping explanation, recovered its controls, and appended a ninth scan with `complete: false`, `requestedCount: 1`, `stopReason: Cancelled by you`.
- A real earlier broad pass completed eight locations and retained a cancelled ninth measurement. A separate UI access fixture was measured successfully and then excluded. That UI fixture did not reproduce denial, so it is not claimed as denied-access UI proof.
- Discovery initially waited in a directory open. macOS tccd logs identify an App Data permission request from the exact test app PID 70253, prompted at 10:45:44 and returned at 10:48:00. No permission was changed by this agent. Discovery then completed. The next packaged run rediscovered promptly. The app now names the current path and offers cooperative cancellation; it cannot interrupt a macOS request already in progress.
- Legacy SpaceCheck history SHA256 remains `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4`.
- No files were deleted, moved to Trash, pruned, reset or cleaned. All source revisions, test fixtures, stages and earlier DMGs remain preserved. Static deletion-API review found only removal from in-memory collections.

## Remaining limits / next goal work

Broader VoiceOver and small-window validation, richer filtering for very large child lists, multi-day scheduling evidence and public signing/notarization remain. Appearance is session-only. Scheduled checks run only while the app is open and remain disabled on this machine. Discovery itself has bounded listings but no hard total wall-clock guarantee; OS calls and permission prompts can delay cancellation. No historical writer monitor is installed; attribution remains evidence-labelled. Existing observations may have different ages, and most folders need a second comparable scan for a meaningful trend. Estimates are neither whole-drive accounting nor guaranteed reclaimable bytes.

Source: `../Context Cleaner 0.5.0-source/`. The README documents limits and the non-destructive versioned build command.
