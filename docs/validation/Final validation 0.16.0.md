# Final validation 0.16.0

Build 33, from the 0.16 goal loop (docs/GOAL_LOOP_0.16.md). Built on Sep 30, 2026, on the M3 Max this app is developed on.

## What changed

- **Charts use one framing: space used.** The level chart draws used space climbing toward a dashed Full line, with straight lines between readings. The axis leaves as much room below the lowest reading as above it, so a week's change fills the chart. Per-day and per-hour bars go up (blue) when space was used and down (green) when it was freed. The headline ("141 GiB more space used"), hover text ("+12 GiB used", "5 GiB freed"), axis signs and caption all agree. Days and hours before the first reading are neither drawn nor hovered as "no readings".
- **New coverage:** Codex scratch (`~/.codex/scratch`, one row per task folder), Ollama models, DiffusionBee, and Android Emulator devices (`~/.android/avd`). Coverage is now 33 places.
- **Everything else, drillable.** Every row opens one level deeper, sized the same read-only way and cached until Look Again. Known folders get a one-line explanation. Git checkouts get a backup line. Projects that are fully backed up and have had no commit, checkout or build for a month are summed, with a copyable Move-to-Trash command.
- **Backup check (read-only git, no fetch):**
  - A repository counts as backed up when it has a remote, `rev-list --branches --not --remotes` is 0, `status --porcelain --ignored=matching` shows nothing uncommitted, and there are no stashes.
  - A worktree only needs to be clean on a branch, since its commits stay in the main repository.
  - Ignored items that aren't build output or caches (for example `ref/`, `.env`, `private/`) are named.
  - A repository that other worktrees use is never offered for the Trash.
  - Last use comes from the newest commit on any branch, the last checkout, or a scanned build. File dates in `.git` don't count, because worktrees write there daily.
- **DiffusionBee** is never counted as old items, because it holds pictures you made.
- **Fixes:** Everything else no longer counts removed folders as "scanned separately". VoiceOver reads the folder buttons as "Show in Finder", and the chevrons are hidden from it.

## Evidence

| Check | Result |
|---|---|
| Test suites | 289 checks pass (Core 28, Detail 30, ScanLimit 28, Planner 19, Discovery 72, Overview 112), fixtures kept under `work/tests-016f` |
| Real fixture repos | Backup states verified in Detail tests with a bare remote: no remote, pushed and clean, ignored `private/`, untracked file, unpushed commit, clean worktree, worktree with a new file, repository used by a worktree |
| Full scan with the new coverage | 283 of 284 folders measured in 1m 42s. The 1 missing was a simulator app folder that no longer exists. Codex scratch measured 273.6 GiB in 99 folders, Ollama 143.9 GiB, DiffusionBee 71.3 GiB, Android emulators 61.0 GiB in 10 devices |
| Earlier full scan (0.15, 17:50) | 170 of 171 measured in 63 s. Size changes against earlier scans were real (a 76 GiB worktree build removed, Downloads emptied, the running VM grew 28 GiB) |
| Backup check on this Mac | 126 checkouts in ~/GitHub and Codex worktrees read in 17 s, with no timeouts. `--ignored=matching` takes 0.05 s on the largest repository, against 11 s for the default mode |
| Update cost (Parts014 bench) | 5.37 ms per update on the 0.15 data copy (0.15 binary: 5.64 ms). 7.96 ms on today's larger data (0.15 binary: 7.79 ms). The increase comes from having more folders |
| On screen | Overview, 7-day line and per-day bars, Everything else with ~/GitHub and ~/.codex/worktrees open, Folders with the new rows. Dark mode |
| Legacy history | SpaceCheck import SHA-256 unchanged: e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4 |
| Package | Signed app verified with `codesign --verify --deep --strict`, DMG checksum VALID, installed in /Applications |

## Limits

- "Backed up" reflects remote-tracking refs as of your last fetch. Context Cleaner never goes online.
- Look Inside reads `~/Library/Containers`, so macOS may ask about other apps' data. Sizing waits for that answer. Light mode was not captured this round; colors are the same semantic system colors as 0.15.
- Nothing was deleted, moved or trashed. The Trash commands were only generated.

