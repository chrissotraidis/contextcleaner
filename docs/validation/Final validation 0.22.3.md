# Final validation 0.22.3

Build 59. After 0.22.2, a full scan read all 587 folders with no failures. The disk still had 15 to 35 GiB free and falling, and Free Up Space offered 23.5 GiB.

## Cause

The temporary folder held 101 GiB, about 95 GiB of it in `padmint-player-check.*` folders: one per run of PadMint's player check, which keeps its folder (a fresh PadMint, Android NDK and build) and asks you to delete it. Temporary items count as old only after 3 days, so finished checks under that age were never listed, and those listed were Review first.

## What changed

| Before | After |
|---|---|
| A `padmint-player-check.*` folder in your temporary folder was listed only after the Untouched for time, as Review first until 3 days | Listed once nothing has touched it for an hour, whatever the Untouched for time, as Rebuildable ("Finished PadMint player check"). One an app holds open isn't listed, and the recheck before copying leaves out one that changed or is open |
| Couldn't Scan offered Try Again one row at a time | Scan These Again reads every folder that failed to read (not those too big for the time limit or blocked by macOS) in one scan |

## Evidence

| Check | Result |
|---|---|
| This Mac's latest scan, 3-day filter | Four finished checks listed, 62.8 GiB, as Rebuildable; four checks running at the time (minutes old) left out |
| Fixture | A check untouched for 2 hours is listed; one 5 minutes old, one held open by a process, and another 2-hour-old temporary item aren't |
| Full scan on 0.22.2, this Mac | 587 folders measured, 0 couldn't be read (was 258 of 621, all "Too many open files") |
| Compiler | No warnings, no errors |
| Test suites | 383 checks pass, 1 new |
