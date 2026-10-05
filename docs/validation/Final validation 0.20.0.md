# Final validation 0.20.0

Build 46. The changes answer [the 2026-10-05 review](../IMPROVEMENTS.md).

## Evidence

| Check | Result |
|---|---|
| Test suites | 340 checks pass: Core 28, Detail 40, ScanLimit 28, Planner 21, Discovery 80, Overview 143. New: Parallels and Ollama breakdowns from fixtures, iCloud-only and empty folders, build-named items in task work folders, chat history kept while open, next scheduled check, and a quick check that can't finish keeping a full scan's size |
| Speed, real saved scans | Model work for Folders measured directly: 632 rows built in 19 ms, sorted by size or last use in 9–15 ms, other lists 2–3 ms. A 12-second sample of the running app while switching views was 89% idle; table cells now carry one tooltip instead of four |
| Real app, read-only | Free Up Space opens first; the Trash's size shows at launch (Full Disk Access detected on). Xcode DerivedData folders in a Codex task's work folder moved from Review first to Rebuildable. The Parallels card lists a 240.85 GiB disk image, 4.05 GiB suspended memory and logs; the Ollama card lists 9 models with sizes and an `ollama rm` command each. Folders › Safe to remove › Select All 83 gave one command for 71, leaving out 12 test devices with the reason. Everything else sized itself in under a minute. Settings and About checked on screen |
| Screenshots | Made from the demo build with made-up folders; no real paths |

## Limits

- Not run on real data: Copy in Folders (it would add a cleanup to History); the command itself is unchanged from 0.19.1 and covered by tests.
- Scheduled checks were checked by tests and Check Now's code path, not by leaving the app open for a day.
- Nothing on this Mac was moved.

