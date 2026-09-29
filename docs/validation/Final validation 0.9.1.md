# Final validation 0.9.1 (build 11)

Goal of this pass: when you open Context Cleaner, you should be able to tell what you can safely remove, what to check first and what to keep. The trigger was the user's report that the Simulator data row, the Folders list and the Watchlist didn't answer that, and that the chart wasn't clean enough.

## What changed

- **Every folder gets an answer.** The Folders list columns are now Folder, Size, Last used and **Can I remove it?** (Safe to remove, Check first or Keep). Selecting a folder shows the reason, the evidence ("Last used 3 weeks ago · size from yesterday") and how to remove it yourself, with a copyable command where a tool has one. Commands are only copied, never run.
- **Simulators come from Xcode.** Each device row is named after its device ("iPhone 17 Pro · iOS 26.5") and shows Xcode's current size and last use (`xcrun simctl list devices -j`, read-only), so it needs no scan. The Simulator Devices folder shows Xcode's current total, 54 GiB on this Mac, and notes that yesterday's scan measured 264.44 GiB. It is never offered for removal as a whole; its card says 5 of 10 devices are idle and together use only 52 MiB.
- **Clutter removed.** Folders that are no longer on disk are hidden from the lists, and the filter line says how many. Xcode's `device_set.plist` and a temporary copy of it had been discovered as two unnamed "Simulator data" rows. Discovery now adds folders only, and the saved file entries are hidden.
- **Last used, honestly.** When an older scan never recorded file times, the list says "Not recorded" and explains that scanning the folder fills it in. Test devices that were never started say "Never".
- **Cleaner chart.** It starts at the first reading and ends at the latest one, so there are no empty days. The line is a smooth curve with a soft fill and a capsule label for the latest value. The capacity line carries its own label, and axis labels include the weekday on short spans and stay clear of the edges.
- **Watchlist** has a one-line explanation and the same "Can I remove it?" column.

## Evidence

| Check | Result |
|---|---|
| Preserving suites | 218 checks passed: 28 core, 22 detail, 25 bounded-scan, 19 planner, 58 discovery/model, 66 overview |
| New checks | Device rows use Xcode's name and size; the Devices folder shows the current total and names the older size; other folders keep their scanned size; without Xcode's list a device stays unscanned; files are told apart from folders; hidden folders that are no longer on disk |
| Native UI, dark | Overview: chart edge to edge, no empty block, labels unclipped. The Simulator search shows 13 live rows with real names and verdicts. The Simulator inspector and its device list are readable. The Watchlist is explained. |
| Native UI, light | Overview chart and cards readable. The appearance was returned to Dark, the user's saved choice. |
| Package | `hdiutil verify` VALID · `shasum -c` OK · `codesign --verify --deep --strict` OK for both the launched app and the copy in the DMG · CFBundleVersion 11 |
| DMG SHA-256 | `21faee6bb9aba54a7bb05b487b2cc0a0b3862a1ec165832dfcfaf08f2d65c48c` |
| Executable SHA-256 (launched = packaged) | `6c90aece517164c56bb848222f81405b341708ef304befb2e0d3fef2ad367c00` |
| Source revision | `8dd19d3` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing was deleted, moved or trashed. Every earlier checkpoint, DMG, fixture and scan record remains in place. The two untracked scratch images `docs/images/space-used.png` and `space-used-chart.png` were left uncommitted and in place.

## Limits

- Most saved sizes are from yesterday's scan, and most scanned folders come from older scans that didn't record file times. Until they are scanned again, they show "Not recorded" for last use. Project build output with unknown last use stays "Check first".
- "Safe to remove" means a tool recreates the folder, so removing it costs time rather than data. It can't prove you won't want something inside, which is why each card says how to remove it and what it costs.
- The previous 0.9.0 app is still running from an earlier session, waiting at a macOS permission prompt. It was not closed.
