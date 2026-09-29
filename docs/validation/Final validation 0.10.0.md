# Final validation 0.10.0 (build 22)

Goal loop: [Goal loop 0.10](Goal%20loop%200.10.md). Trigger: the user couldn't tell whether the app really knows what a folder is for, or whether they still use it. They also asked for the default order to be biggest-and-unused, for easy exclusion with its own view and share of the disk, for deleted folders to stop appearing, and for a more dynamic Overview.

## What changed

1. **Evidence from git.** Project folders read git, read-only (`--no-optional-locks`, GIT_OPTIONAL_LOCKS=0): last commit, branch merged into main, uncommitted changes, and whether a worktree is still registered. For example, on this Mac: "Worktree kartpad-stabilization-20260918: last commit 3 days ago on codex/upstream-all-platforms-20260922 · merged into main · 1 uncommitted change", so Check first. Finished worktrees offer `git worktree remove` (git refuses uncommitted work). "Last used" is the newest of file changes and commits.
2. **Big and unused first** is the default order in Folders and in the report (size × idle days, capped at 90). An Order menu offers Largest, Longest unused and Name.
3. **Keep, Never Suggest** (a context menu item, an inspector button or a multi-select action) and a **Kept** view with totals, share of the disk and turned-off folders. Kept rows say "Kept by you" or "Not scanned" instead of a verdict.
4. **Gone means gone.** Deleted folders leave every list, total and Couldn't Scan. History reports them as "N no longer on disk", never in red.
5. **Overview.** A whole-disk map (By answer / By type: Safe, Check first, Keep, Kept by you, Everything else, Free), with hover and click. It replaces the old safe banner and category panel. **How long it's sat unused** is shown as labeled rows stacked by answer.
6. **Virtual machines** (Parallels, Docker Desktop's disk, UTM) are a new type. This Mac has a Windows 11 VM of 144.4 GiB and a Docker disk of 33.6 GiB, previously hidden in "Everything else". They're never safe; the advice points to the apps' own tools (`docker system df`).
7. **Permission dialogs.** The orange banner adds **Stop These Questions…**, which opens Full Disk Access; granting it is the user's choice. The App Data prompt reappears on relaunch for this unnotarized build even with a stable signature.
8. The report lists, for every folder, its answer, last use, reason, evidence and how to remove it yourself.

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 243 checks: 28 core, 22 detail, 68 discovery/model, 78 overview, 19 planner, 28 bounded-scan |
| New tests | Git evidence rules (active, finished, summary wording), Keep wins, a real throwaway git repository with a worktree (branch, fresh commit, clean, 1 uncommitted change, registered, merged, repository root lookup), kept view and totals, loading legacy preferences, deleted folders aren't problems, idle ordering, VM classification and Docker advice, the "no longer on disk" wording |
| Main-thread cost | 9.5 ms mean, 16.7 ms max per scan update on a copy of the real data (gate: at most 10 ms mean) |
| Full scan, installed build | 178 folders in 239 s after the user answered macOS's dialog; VMs measured |
| Native UI | Overview (disk map, idle rows, safe list) in dark and light; Folders tiles, order menu and git evidence in the inspector; Kept; Couldn't Scan; Scan History; Settings › Coverage including Virtual machines |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK; signed with the Apple Development identity; the /Applications executable matches the build |
| DMG SHA-256 | `c3cf4a42d0920aa2be860881b2e4344b18deb6202f070bcc12f83674123f6ddf` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing was deleted, moved or trashed. Earlier builds, DMGs, fixtures and scan records remain.

## Observed on this Mac during the pass

Free space swung between 22.7 and 57 GiB within an hour. Both VM disks and kartpad build folders were being written to at the time; kartpad · build grew 11.59 GiB. The app's "Grew most" chips and the Idle space rows show this.

## Limits

- Git evidence covers folders inside git repositories. Recovery copies and app libraries have no git history to read.
- "Everything else" (1.63 TiB here) is space outside the scanned locations: macOS, apps, and folders the app doesn't cover yet.
- Unnotarized builds see the App Data prompt again after relaunch. Full Disk Access avoids that.
