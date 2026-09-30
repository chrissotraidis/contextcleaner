# Final validation 0.14.0 (build 27)

A performance pass. Nothing about what the app shows or answers changed; the same work is done with less time and CPU.

## What changed

1. **Batched directory reads.** The folder walk used `readdir` and then a separate `lstat` call for every entry. It now uses `getattrlistbulk`, which returns name, type, device, change date, file ID, link count and sizes for a batch of entries in one call. The walk keeps its shape: one open directory per level, so memory stays bounded by depth, not width. Symlinks, other volumes, mount points, hard links, exclusions and every limit behave as before.
2. **Parallel launch decoding.** Saved scans, settings, discoveries and disk readings are decoded across cores instead of one file at a time.
3. **Cheaper per-update work.**
   - Turned-off folders are normalized once per settings change, not on every check.
   - Sorts that needed parents before children compared `String.count`, which walks the whole string. They now compare `utf8.count`, which is instant, and parents still sort before their children.
   - The advice cache is keyed by path instead of by a string built on every lookup.
4. **Cached table order.** The Folders table was re-sorted on every redraw, including selection clicks. The model now sorts once per change of rows or order, and the default order scores each row once instead of once per comparison.

## Measurements

The machine was under heavy load throughout (load average 28–106 from other work), so the CPU time of the measuring thread is reported next to wall time.

| What | Before | After |
|---|---|---|
| Walk `~/.codex/worktrees/kartpad-padforge/build` (273,004 files) | 6.1–6.6 s, 3.1–3.4 s CPU | 4.8–4.9 s, 1.8–1.9 s CPU |
| Walk `kartpad-release-051/build` (203,722 files) | 5.2–6.4 s, 2.6–3.0 s CPU | 3.8–4.5 s, 1.5–1.7 s CPU |
| Walk `~/GitHub/kartpad/build` (1M+ entries, to the 1M test limit) | 24 s, 11.7–12.3 s CPU | 16–19 s, 6.2–7.4 s CPU |
| Launch: decode 21 saved scans (34 MB) | 0.49–0.55 s | 0.18–0.23 s |
| Model work per scan update (180 folders) | 8.4 ms CPU | 4.1 ms CPU |
| Folders table order per redraw (241 rows) | 3.9 ms | 0.02 ms |

**Same results.** The old and new scanners were run side by side on 8 real folders: the npm, Gradle, Playwright and Hugging Face caches, this repository, iOS DeviceSupport, a Codex worktree build, and Downloads. They matched on state, allocated and logical bytes, file count, newest change, listed and omitted entries, every top-level child's bytes, files, date and type, and every file-type total. A second comparison on three more folders also matched. The only difference seen was the Gradle cache gaining one file between runs while Gradle was in use.

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 256 checks: 28 core, 22 detail, 70 discovery/model, 89 overview, 19 planner, 28 bounded-scan |
| New test | The cached table order matches a fresh sort, for the default order and after switching orders |
| Native UI | Overview and Folders on the installed build; default order unchanged; selection and folder card respond |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK; /Applications executable matches the build |
| Source | `dc49f36` |
| DMG SHA-256 | `6f70fcde34c279734ca44be5946824a5e603f230f297fb502fde34c51044c634` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing on the Mac was deleted, moved or trashed. The folder walks in the benchmarks only read metadata.

## Limits

- Wall-time gains on a busy machine vary; the CPU numbers are the steadier comparison.
- The largest remaining launch cost is decoding saved scans' folder listings. Only the last two listings per folder are kept in memory, but all are read at launch. Reading less would mean changing the saved format, which this pass didn't do.
