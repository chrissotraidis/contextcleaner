# Final validation 0.12.0 (build 25)

Goal loop: [GOAL_LOOP_0.12.md](../GOAL_LOOP_0.12.md). Trigger: free space fell 185 GiB between Sunday and Wednesday, while the Overview offered 11 GiB as safe. 1.2 TiB sat under "Check first", which didn't say what to do.

## What changed

1. **Four answers, ranked by what removing costs.** They are Safe to remove, Rebuildable, Your call and Keep, and "Check first" is gone. Build output and caches you still use are **Rebuildable**. Active projects no longer push their ignored build output into "check first", because uncommitted work lives in tracked files.
2. **Old experiments inside folders.** Project `build`, `generated`, `intermediates/.cxx` and scratch `work` folders list subfolders untouched for 7+ days; caches use 30+ days. The kartpad-stabilization `build` card lists 19 items totalling 75.33 GiB, such as `evening-20260921` (33.35 GiB, 7 days) and `handoff-verification-20260919` (14.33 GiB, 9 days).
3. **Git evidence.** `git check-ignore -v -n` runs read-only per project. "Git ignores this folder" appears as evidence. A `build` folder git tracks is Your call.
4. **Overview.** "You can get back about 614.23 GiB" is 11.26 GiB safe, 205.12 GiB in old items and 397.85 GiB rebuildable, with each byte counted once through the outermost scanned folder. The whole-disk bar is split the same way. **Where the space went** replaces the idle panel. **Start here** has Safe / Old items / Rebuildable / Your call tabs.
5. **Where the space went, on this Mac, since Sun 11 PM:** Codex worktrees +76.25 GiB (29 new folders), Codex task outputs +15.44 GiB, yomiboy-foundation +9.92 GiB, Downloads +4.77 GiB, iPhone install caches +3.77 GiB. Scanned folders shrank by 231.69 GiB, most of it in simulators. The rest is outside scanned folders.
6. The copy is shorter: two to four word reasons ("Used yesterday", "75.33 GiB old inside", "May be the only copy"), and the cleanup list has five sections that match the answers.

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 254 checks: 28 core, 22 detail, 69 discovery/model, 88 overview, 19 planner, 28 bounded-scan |
| New tests | Active project build output is Rebuildable with git evidence; a git-tracked build folder is Your call; git-ignored evidence; experiment builds older than 7 days are listed and this week's aren't; caches use 30 days; "where it went" groups by place, counts new folders in full, counts nested folders once, and skips folders first scanned later |
| Main-thread cost | 8.8 ms mean per scan update on current real data (180 folders), including the new totals; 6.8 ms on the older data set. Gate: at most 10 ms. A first version measured 10.2 ms and was fixed by keeping the get-back total steady during a scan. |
| Native UI | Overview in dark and light (get-back bar, where it went, Start here tabs), Folders with new tiles and short reasons, the worktree card with old items, Old items tab |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK; /Applications executable matches the build (`90d57f06…`) |
| Source | `88b133e` |
| DMG SHA-256 | `f07a3b2c0aaac1cdfaf4bc6a75a3596166d1ad49936ddfe3bf97250abc109da5` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing on the Mac was deleted, moved or trashed. Git was only read.

## Limits

- "Old" means no file inside changed. A build you still run without rebuilding would look old; check the date before removing it.
- Subfolder dates come from the latest scan. Run a full scan before a big cleanup.
- "Outside scanned folders" includes anything the app doesn't cover, plus space from folders removed since. It can't be split further.
- Recovery copies and scratch `work` folders stay Your call: they may hold the only copy of something.
