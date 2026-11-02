# Final validation 0.24.1

Build 65. Chris put a lot into the Windows 11 Parallels machine and asked how to clean it, and for a general bug pass.

## What was in the machine

| Part | Size | Where |
|---|---|---|
| Disk image | 240 GiB of a 256 GiB cap | `~/Parallels/Windows 11.pvm/harddisk.hdd` |
| Second drive | 36 GiB | `~/.codex/worktrees/sunpad-windows-route/vm/sunpad-build.hdd`, attached as a second disk |
| Suspended memory | 7.3 GiB | in the machine, while it's suspended |

Parallels' own estimate (`prl_disk_tool compact -i`, read-only) counts 245,701 of 245,703 1 MiB blocks as in use, and the same with `--buildmap` (a full read, 1m41s): Reclaim Disk Space frees nothing until files are deleted inside Windows. Codex sessions that built PadMint games in the machine used folders such as `C:\\TribesPad`, `C:\\bw-win-20261003`, `C:\\SquirrelPad clean validation 20261026`, `C:\\ott` and `C:\\dino`.

## Found

| Problem | Fix |
|---|---|
| The second drive lives in a Codex worktree. That worktree was Review first only because Parallels had it open at the scan. With the machine suspended or shut down, ticking it in Folders and copying would pass every check, and Windows would lose a drive and fail to start or resume | A folder holding any drive a Parallels machine uses (read from its config.pvs) is Not for the Trash, "Drive of Windows 11", never suggested, and refused when a command is copied, however it was ticked |
| The machine's card didn't show a drive kept elsewhere, or whether Reclaim Disk Space would help | It lists drives kept outside the machine and where, and, when the machine is stopped or suspended, Parallels' estimate of what Reclaim Disk Space frees: "about 12 GiB now", or "everything on it is in use inside the machine… delete files inside the machine first" |
| A machine running at the scan still said "Running at last scan" after it was suspended | "Not running now" on the row, and "It isn't running now" on the card, when Parallels no longer has it running |

## Evidence

| Check | Result |
|---|---|
| This Mac's machine, card | Disk image 239.93 GiB, nothing to reclaim; drive sunpad-build.hdd 36.35 GiB in the worktree; suspended memory 7.35 GiB. Machine still suspended afterwards |
| This Mac's worktree | `sunpad-windows-route` is "Drive of Windows 11"; its `sunpad/build` folder, which holds no drive, keeps its own answer |
| Compiler | No warnings, no errors |
| Test suites | 407 checks pass, 4 new: drives from a machine's settings and a running machine, folders holding a drive, Parallels' estimate, the card |

