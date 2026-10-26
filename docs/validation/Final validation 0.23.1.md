# Final validation 0.23.1

Build 61. A check of 0.23.0 after release found that the scan and the recheck before copying disagreed about `.git`.

## Cause

0.23.0 leaves a folder's own `.git` out of "last used", so a tool running git doesn't make a project look used. The recheck before copying (`newestChange`) still counted it. After a new scan, a folder that is itself a repository is compared against a date that ignores `.git`, with a date that doesn't, and is left out as "changed since the scan" whenever git has run in it since its files last changed. On this Mac, with 0.23.0's rule, `~/.padmint/games/kartpad-v0.7.8` (git last ran in it an hour earlier, files untouched for 3 weeks) was left out.

The fixture checks added in 0.23.0 for `.git` didn't catch this: the suite's clock is 100 days ahead, so the fixture's "old" file was dated in the future and newer than `.git`.

## What changed

| Before | After |
|---|---|
| The recheck counted the folder's own `.git` | It leaves it out, the same as the scan |
| The `.git` fixture used the suite's future clock | It uses real file dates |

## Evidence

| Check | Result |
|---|---|
| `kartpad-v0.7.8` on this Mac, measured then rechecked | 0.23.0: left out as changed. 0.23.1: ready |
| `bananapad-v0.2.1` (git hasn't run in it) | Ready with both |
| The recheck check against 0.23.0's code | Fails, as it should |
| The "git isn't use" scan check against 0.22.3's scan code | Fails, as it should |
| Test suites | 393 checks pass, 1 new |

