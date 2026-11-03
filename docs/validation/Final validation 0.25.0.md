# Final validation 0.25.0

Build 66. Chris put a lot into the Windows 11 Parallels machine and asked how to clean it. 0.24.1 was built for this but not published; its changes ship here.

## What was in the machine

| Part | Size | Where |
|---|---|---|
| Disk image | 240 GiB of a 256 GiB cap | `~/Parallels/Windows 11.pvm/harddisk.hdd` |
| Second drive (V:) | 36 GiB | `~/.codex/worktrees/sunpad-windows-route/vm/sunpad-build.hdd` |
| Suspended memory | 7.3 GiB | in the machine, while it's suspended |

Both drives are BitLocker volumes (Windows 11 device encryption, used space only, protection off). That is why Parallels' read-only estimate (`prl_disk_tool compact -i`, also with `--buildmap`) counted every block as in use: it can't read the file system through the encryption. Inside Windows, C: had 12.6 GiB free of 255 GiB and V: 5.9 GiB of 40 GiB.

Read-only inside Windows, through Parallels Tools: about 156 GiB of top-level build, test and validation folders on C: from Codex and PadMint sessions (`C:\kpiosm` 31 GiB, `C:\pm029-focus20261003` 30 GiB, `C:\PadForgeClean` 21 GiB, `C:\pm020user` 18 GiB, `C:\PadForge` 14 GiB, `C:\bw-win-20261003` 11 GiB, `C:\bw-ios` 9 GiB and smaller dated ones), 22.8 GiB of old PadForge homes in the user folder, 10.5 GiB of Windows Update downloads, and on V: 27 GiB in `PadMint validation 20261026` plus a 5.4 GiB SunPad build checkout. Of 95 git checkouts, every one of Chris's own repositories was clean and its commit is on GitHub or in a repository on the Mac; the only exception was a throwaway "VM test only" commit. Modified files exist only in upstream sources that recipes patch during builds.

## Found

| Problem | Fix |
|---|---|
| A running Windows machine was a closed box: the card showed a 240 GiB disk image and nothing about what filled it | **Look Inside Windows** on the machine's card lists the biggest folders on Windows' fixed drives and in each user folder, biggest first, with when each was made. It runs a fixed, read-only PowerShell script through `prlctl exec` (robocopy /L lists without copying), only for a machine whose settings say Windows and whose id is hex digits, and saves nothing |
| On a BitLocker drive the card said "everything on it is in use, Reclaim Disk Space frees nothing", which reads as "nothing to gain" | A BitLocker drive is recognized from the image's own block table (a few KiB read, 0.01 s here) and the card says what works: delete files inside Windows, then Optimize Drives, and Parallels gives the space back right away |
| The second drive lives in a Codex worktree; with the machine suspended, that worktree could be ticked and moved to the Trash | A folder holding any drive a Parallels machine uses is Not for the Trash, "Drive of Windows 11", never suggested, and refused when a command is copied |
| A machine running at the scan still said "Running at last scan" after it was suspended | "Not running now" on the row, and "It isn't running now" on the card |

## Evidence

| Check | Result |
|---|---|
| Space really comes back | In Windows, a 2 GiB file was written (image grew 1.8 GiB on the Mac), deleted, and Optimize-Volume -ReTrim run: the image ended at 251.64 GiB, below the 251.77 GiB it started at |
| Look Inside Windows, this Mac | 25 rows in 17 to 70 s (70 s just after resuming), matching a separate full inventory, with Windows Update's 10.5 GiB of downloads as its own row; a wrong machine id gives the plain "couldn't run it inside Windows" message |
| BitLocker detection | Both real drives found, in every snapshot layer; synthetic plain-NTFS, empty and missing disks aren't |
| Second pass | Found and fixed: robocopy's summary was found by its English label, so on Windows in another language every folder would have read as 0 and vanished (now read by position); only one layer of a machine with snapshots was checked for BitLocker; compatibility junctions in `C:\Users` are skipped explicitly; a machine Parallels keeps outside ~/Parallels (read from its own list of machines) wasn't known, so the folder holding it had no drive protection |
| Third pass | Found and fixed: BitLocker on an older machine that starts the BIOS way (no GPT) wasn't recognized; a machine whose path has an apostrophe or quote wasn't read from Parallels' list; an answer cut short, or a Windows with nothing big, read as "couldn't run it" (the script now ends with a marker, and an empty answer says so); a VM drive left out of a command is now named as the reason; the busy indicator has a VoiceOver label |
| Overview after launch | Watched for two minutes after a relaunch: 63 GiB of old items and 30 GiB safe until git had been read (about 100 s), then 141 GiB and 56 GiB. The conservative start is by design; Overview now says it's still asking git, as Free Up Space did |
| Git after launch | Projects were read one after another. Read several at a time: 80 projects in 4.2 s instead of 74 s with identical answers, and git done 33 s after launch instead of 84 s (warm). The app is idle afterwards; Overview updated within a minute |
| Parallels' command limit | Measured: commands over about 3,900 encoded characters (1,460 of script) fail with the same message as missing Parallels Tools. The script is 758 characters, and a check keeps it under 1,200 |
| Compiler | No warnings, no errors |
| Test suites | 415 checks pass, 8 new: BitLocker through the block table, its snapshot layers and the older BIOS layout; which machines are offered the look; how its answer is read and that it ran to the end; the script's length; machines registered outside ~/Parallels, with quotes in their path; ages past two years in years |
| The machine afterwards | Suspended again, as it was found. Nothing inside Windows was deleted |

