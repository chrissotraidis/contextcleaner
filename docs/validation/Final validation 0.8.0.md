# Context Cleaner 0.8.0 validation

2026-09-28. This pass addresses the six user screenshots: ambiguous scan controls, misleading error counts, unreadable free-space history, technical category names and text-heavy details.

## Automated checks

All six preserving suites passed, **167 checks**: Core 28, Detail 22, ScanLimit 25, Planner 19, Discovery 45, Overview 28. Logs and every fixture remain in the local task's `work/cc-080-tests-final` directory. `test-preserving.sh` documents the exact commands and refuses an existing output destination.

New checks cover pending versus failed folders, current capacity in the chart, actual reading dates, missing history, duplicate timestamps, concrete scan summaries and presentation labels that preserve stored category IDs. Existing preservation, bounded-scan, selection, cache invalidation, exclusion and aggregation regressions remain passing.

An earlier compile run was interrupted by a source edit during compilation; the full run was repeated after freezing those inputs. No test fixtures were cleaned up. Subsequent presentation-only refinements were compiled and inspected natively.

## Native checks

On macOS with the user's existing local records:

- Overview showed pending folders separately from zero scan issues. The previous red warning count was not a count of actual failures.
- Scan Folders and Command-R opened the included-path preview. Exact paths expanded; Settings opened; Cancel returned without starting a scan.
- Start Scan began discovery. Stop Scan completed and preserved a result stating **1 of 208 folders scanned**. It did not claim a full scan.
- Scan History named folders, showed finished/stopped outcomes, and expanded to concrete measurements and the free space recorded at that time.
- Folder search and Not scanned filtering led to a neutral pending state with one Scan Folder action and one Show in Finder action. No empty timeline appeared.
- The capacity card and chart used the same latest free-space reading. Clicking the chart selected a recorded value and timestamp.
- Light and dark appearances were inspected at approximately 1103 × 752 and 1218 × 832 points. The compact Overview may scroll slightly; content remains reachable. A card-background inconsistency found during this check was corrected.
- Report preview opened locally for filtered folders before any Save action. Final copy uses singular/plural and describes the content concisely.

## Preservation

No files were deleted, trashed, pruned or cleaned. Previous app bundles, disk images, test outputs and fixtures remain. App records append; scans only read their target folders.

The legacy SpaceCheck history hash is unchanged:

```
e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4
```

User screenshots and raw local folder reports were not added to the repository.

## Limits

- No whole-disk scan or continuous writer attribution. Known paths and metadata provide context, not proof of historical writes.
- The free-space chart uses saved scans plus the latest capacity check. Capacity-only refreshes are not independently retained.
- Allocated folder sizes are not guaranteed recoverable space. Previous successful folder readings can predate the newest scan attempt.
- No new quantitative performance improvement is claimed. Native controls were exercised; this is not a comprehensive accessibility audit.
- Scheduled checks run only while open. Builds are ad-hoc signed, not notarized. Apple Silicon/macOS 14+ remains the build target; older OS visual appearance was not tested on physical hardware.

## Final package and smoke checks

- Source commit: `eea18556ac72f6b2651525ab94ab8e358cbbfc4f`; working tree clean when packaged.
- `Context-Cleaner-0.8.0.dmg` passed `hdiutil verify` and SHA-256 readback.
- DMG SHA-256: `aadb77b90b92615b3186f513a6468310a062e02aaa4927d04f97633c803a91c0`.
- App passed `codesign --verify --deep --strict`; launched and packaged executable hashes match: `95b3b9236cfb139ecabab42de40da78e00dbc7e471ddd2680b8ec096d56c0d4a`.
- Final app launched with the preserved records. Dark appearance, chart click, Show change reset, capacity Refresh and final report wording were verified.
- Selected-folder scanning completed for npm download cache. Shift-selection of two folders showed a combined 2.84 GiB; the model tests cover nested-folder deduplication.
- Latest app was left open on Overview with scheduled scans off and the user's dark appearance restored.

The source commit was pushed to GitHub and remote parity verified. This validation-only follow-up does not change the compiled source. The DMG remains a local deliverable; no new public GitHub release was published.
