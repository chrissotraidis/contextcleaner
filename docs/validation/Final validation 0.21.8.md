# Final validation 0.21.8

Build 55. After 0.21.6 and 0.21.7 each found errors read as "nothing there", this pass listed every fallback in the files that decide (OverviewData, Model, Activity, Inventory, Classifier, Planner): each `try?`, `?? 0`, `?? []`, `?? true`, `?? false`, `?? .distant…` and `catch`, about 160. Each was asked one question: can this default make something look removable, or let a command through, when the truth is unknown?

## Changed

| Before | After |
|---|---|
| newestChange, the recheck before copying, used a folder's own date when it couldn't open the folder or a folder inside it | Counted as changed (distantFuture). EDEADLK (iCloud only) and ENOENT (just removed) still use the date |
| keepsEverything was true for a worktree with no repository named (`?? true`) | Only for a checkout that isn't a worktree. worktreeAdvice agrees: "Repository unknown", Review first |
| registered = lstat(gitdir) == 0: any failure meant unregistered, which feeds "looks finished" | true, false only for ENOENT, otherwise unknown |

## Already safe

| Fallback | Why it's safe |
|---|---|
| Open files unknown (lsof failed, timed out, cancelled, or over 16 MiB) | Nothing is copied |
| No scan date for an item | Counts as changed |
| Unknown idle time | Counts as used just now |
| Simulator "isAvailable" missing | Counts as available, so not idle |
| git status, rev-list, remote, merge-base or log failing | Changes unknown, not pushed, no remote, not merged, no date: all lead to Review first |
| Projects offered from Everything else | git asked again in full when copying |
| Whole repositories in Free Up Space and Folders | Never Safe or Rebuildable there; git only makes project advice more careful |
| Unknown shell | Read as POSIX; in another shell the command fails to parse and moves nothing |
| Temporary folder path | realpath, so it matches the paths lsof reports |

## Evidence

| Check | Result |
|---|---|
| This Mac's 87 Codex worktrees | Every .git file names its repository, so none changes to Repository unknown |
| Compiler | No warnings, no errors |
| Test suites | 372 checks pass, one new (an unreadable folder inside counts as changed) and one new case (Repository unknown) |
