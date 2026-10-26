# Final validation 0.23.0

Build 60. The disk was 98% full (45 GiB free of 3.63 TiB). Folders showed 2.86 GiB Safe to remove, 97.79 GiB Rebuildable and 1.37 TiB Review first, and Free Up Space said nothing had sat untouched for a week.

## Cause

Review first folders were never offered in Free Up Space, apart from Codex scratch, work folders, backups and Android emulators. Most of the 1.37 TiB was folders git ignores (Not in git) that nothing had touched for days or months, such as `projectreach/ref` (252.6 GiB) and `meleepad/ref` (29.6 GiB). Context Cleaner already knew no commit held a copy, but it gave no way to act on that. Outside the scanned places, `~/.codex/private` (81 GiB) and `~/.padmint/games` (97 GiB) weren't scanned at all.

Separately, in Folders, ticks vanished two ways. Ticking a second folder made the selection bar appear above the list, which moved every row down, so a quick third click landed beside a box and a plain click on a row replaced all the ticks with that row; reproduced on the installed 0.22.3, 12 ticked folders became 1. And the table kept its own idea of the selection, which tick boxes don't update: a debug build logged it reporting an empty selection during an AppKit event (no click or key), which cleared 3 ticks.

## What changed

| Before | After |
|---|---|
| Not in git folders never appeared in Free Up Space | Listed once untouched for the Untouched for time, as Review first ("Not in git, only on this Mac"); while one is in use, its untouched items are listed instead |
| `~/.codex/private` and `~/.padmint/games` weren't scanned | Both are in Coverage. Private work is treated like Codex scratch; each PadMint game version is scanned with its build folders and the folders git ignores |
| An older PadMint game version looked like any project | Review first, "Older PadMint version, NAME beside it", listed once untouched |
| The selection bar appeared and vanished, moving the list | Always there; with two or more ticked, a plain click on a row ticks it and never clears the others |
| The table could replace the ticks with its own, older selection when the window activated or the list reloaded | Only a click or key press can take ticks away; anything else can only add |
| Any change inside `.git`, from any tool running git, made a project look used today | `.git` is left out of "last used"; commits count from git. `.git` is never listed as an item |
| `.next` and `obj` in a project were Review first | Build output |
| Filtered to Review first, the right panel said 1.42 TiB and the tile 1.37 TiB | Both show the tile's total, each byte counted once |
| A folder measured on its own could also be listed as an item inside its parent | Listed once, under its own answer |

## Evidence

| Check | Result |
|---|---|
| This Mac's last scan, 3-day filter, before | Nothing untouched for a week; Review first folders absent |
| Same scan, 3-day filter, after | 143 items, 630 GiB: 455 GiB Not in git (68 folders), 62.8 GiB finished player checks, 47 GiB build output, 20 GiB old items inside folders in use, 24.9 GiB `obj` and `.next` now Safe to remove |
| New places, measured live with the app's own discovery and measuring, 3-day filter | 25 items, 166 GiB: Codex private work 81 GiB, 13 older PadMint versions, PadMint build folders. No item listed twice; `kartpad-v0.7.8` listed whole once `.git` stopped counting |
| Selection, installed app | See the install check below |
| Compiler | No warnings, no errors |
| Test suites | 392 checks pass, 9 new: Not in git listing and old items inside, the untouched time, `.next` and `obj`, Codex private work, version order (0.7.10 after 0.7.9), older PadMint versions, row locations, nothing listed twice, `.git` dates |
