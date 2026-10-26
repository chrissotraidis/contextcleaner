# Final validation 0.23.2

Build 62. A second check after 0.23.1, aimed at the places the new code meets the rest of the app: the recheck before copying, Free Up Space grouping, what git calls ignored, and the tick rule.

## Found

| Problem | Fix |
|---|---|
| By kind groups by the label's first part, and the PadMint label held the newer version's name ("Older PadMint version, kartpad-v0.8.3 beside it"), so each older version was its own group of one | The label is "Older PadMint version · kartpad-v0.8.3 beside it": one group, one tick box |
| The README and changelog said these Review first items are "never ticked for you"; Select All does tick them (only backups are skipped) | They say the items start unticked, Select All includes them, and copying asks first |

## Checked, no problem

| Check | Result |
|---|---|
| Recheck on every Free Up Space item from this Mac's last scan (3 days) | 138 on disk: 128 ready, 10 left out as changed. Each of the 10 was looked at by hand: files written or a nested git clone fetched after the scan. The recheck did its job |
| The two new places measured fresh, as after a rescan | 98 measured, 25 offered (165.9 GiB), none twice, all ready on recheck, none refused by the command's path rules, one group of 14 older PadMint versions |
| Not in git folders that hold tracked files (git calls a folder ignored even if files in it were force-added) | 0 of 90 |
| Ticks, installed app: Clear, switch to Finder and back | Stays clear |
| Ticks, installed app: 3 ticked, switch to Finder and back | Still 3 |
| Full scan on the installed 0.23.2 | 706 folders read, none failed, in 3m 34s, including ~/.codex/private and ~/.padmint/games |
| Recheck on every Free Up Space item after that scan (3 days), measured with 0.23.x's rule | 155 of 155 ready, none left out: the 0.23.0 problem is gone on real data |
| By kind on the installed app, Review first | Not in git 63 (193.36 GiB), Left by a Codex task 6 (81.18 GiB), Older PadMint version 14 (62.07 GiB) in one group, Old item inside 47, Looks like a backup 1 |
| Free Up Space after the scan | 3 days: 156 items, 424.08 GiB (61.54 GiB Nothing lost). 1 week: 126 items, 386.01 GiB |
| Test suites | 394 checks pass, 1 new |

