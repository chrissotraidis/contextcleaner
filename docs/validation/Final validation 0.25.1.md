# Final validation 0.25.1 and Windows 0.1.1

Mac build 67. Chris set Free Up Space to 1 week and still saw a PadMint player check untouched for 11 hours (19 GiB), and asked to sort by size and date in a way that works with a long list.

## Found

| Problem | Fix |
|---|---|
| A finished PadMint player check was listed an hour after it ran, whatever Untouched for said (a rule from 0.22.3) | It follows Untouched for like everything else; once listed it's still Rebuildable |
| Safe to remove folders were listed by their own rule (for example an install cache unused for 8 days) under any Untouched for | They're listed only when their last use (Xcode's date for a simulator, otherwise the newest change) is at least that long ago |
| Only Biggest first or By kind; no way to see the oldest items first or hide small ones | Oldest first, and At least: any size, 1 GB or 10 GB, on both the Mac and Windows |
| Untouched for stopped at 1 week (Mac) or 30 days (Windows) | 1 month and 3 months on both |
| With the new controls the Mac header was cramped: the total cut off and the chips wrapped mid-word | The total has its own line; Untouched for, size and Sort share the next; the chips never wrap |
| A disc image untouched for a decade read "untouched 120 months" | Ages past two years read in years |

## Evidence

| Check | Result |
|---|---|
| Mac test suites | 418 checks pass, 3 new: a player check under 3 days and under an hour, a Safe folder under a week and a month, Oldest first's order |
| Mac compiler | No warnings, no errors |
| This Mac, after a full scan | Under 1 week: 158 GiB in 85 items, no player check (the 19 GiB one from 11 hours ago is gone). Under 1 month, Oldest first: 79 GiB, starting with disc images in meleepad/ref and Not in git ref folders untouched 3 months |
| Windows tests, Windows PowerShell 5.1 in the Parallels VM | 97 of 98 pass, 2 new (the new settings start at their old behavior, and are remembered). The one failure, never moves Documents, fails the same way on unchanged main: the VM runs tests as SYSTEM, whose profile has no Documents folder |
| Windows window | The XAML loads and every control the script uses exists in it. Not opened on a desktop here, and not run on PowerShell 7 |

