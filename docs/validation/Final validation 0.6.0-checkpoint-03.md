# Context Cleaner 0.6.0 — checkpoint 03 validation

2026-09-28, Asia/Tokyo. The overall goal remains active. This is a verified local checkpoint, not a notarized public release or multi-day monitoring acceptance.

## Deliverable

`../Context Cleaner 0.6.0-checkpoint-03/Context-Cleaner-0.6.0.dmg`

SHA256: `1a68e2921abcf39c8835d2f19ad9448ee23361d395723301f7fdef3173698754`

The exact DMG passed hdiutil checksum verification, mounted read-only at `/Volumes/Context Cleaner 0.6.0 2`, and its embedded app passed strict code-signature verification. Locally ad-hoc signed, Apple Silicon, macOS 14+.

## What changed from 0.5

Contents browser for retained children (search, size/name sort, folders-only filter, 30-at-a-time reveal, searchable child-change table), persisted appearance choice, and a fixed proportional table/inspector split that cannot overflow the window. Checkpoints 01 and 02 of 0.6 are preserved as the two earlier attempts; 02's auto-hiding sidebar did not fix the overflow and is not in 03.

## Verification evidence

- 110 checks passed on the 0.6.0 source: 28 core, 22 detail, 25 scan-limit, 11 planner, 9 overview and 15 discovery/model. The discovery/model suite gained three checks: appearance survives an actual model restart, an unrecognized appearance value is ignored, and saving appearance preserves unrelated exclusions. Fixtures are retained under `work/context-cleaner-0.6.0-*-fixtures/`.
- The overview suite's compile recipe in the README was stale (Contents.swift now needs Inventory.swift); the README is corrected and the suite passes with the corrected recipe.
- Contents browser, exercised in the packaged 0.6 app on the kartpad-stabilization Android intermediates folder (85 retained children): the search field found `validate_signing_config`, which was previously hidden behind the 30-row cap; the sort switched to alphabetical; "Show all 31 file types" expanded the extension list.
- Appearance persistence, exercised in the packaged app: Light was chosen at 11:03 and saved as a new preference event; a Dark event was saved at 11:06 (after the app relaunched and while the assistant's turn was paused, consistent with the user changing it back); the relaunched app displayed Dark. The saved preference, whichever it is, is what the app shows after relaunch.
- Layout, measured with the window at 1189 × 875 points on a 1728-point-wide display: checkpoint 02 clipped the capacity bar, inspector text and footer past the right edge (the split view reported 766 + 360 minimum with only 981 available). Checkpoint 03 at the identical window size shows every element inside the window, with the Simulator data folder selected and its inspector fully readable. Zoomed to full display width, the inspector caps at 520 points and the table takes the rest. The window was restored to its previous size afterwards.
- Legacy SpaceCheck history SHA256 remains `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4`. App-owned history still holds 9 scans and 2 discovery snapshots; nothing was pruned.
- Static review of the 0.6.0 sources and build script finds no deletion, trash, unlink or truncate calls. All earlier source revisions (`*.revision-NN`), stages, DMGs and fixtures remain in place.

## Remaining limits / next goal work

Full VoiceOver pass, multi-day scheduling evidence and public signing/notarization remain open. Scheduled checks run only while the app is open and remain disabled on this machine. Discovery has bounded listings but no hard wall-clock guarantee; a macOS permission prompt can delay cancellation. No historical writer monitor is installed; attribution remains evidence-labelled. Most folders still have a single observation and need a second comparable scan for a meaningful trend. Estimates are neither whole-drive accounting nor guaranteed reclaimable bytes. The table/inspector split is no longer user-resizable; that trade was made for layout stability.

Source: `../Context Cleaner 0.6.0-source/`.
