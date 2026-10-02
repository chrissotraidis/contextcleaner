# Final validation 0.18.0

Build 40, from the 0.18 goal loop (docs/GOAL_LOOP_0.18.md). Built on Oct 3, 2026.

## What changed

- **Overview order:** free space and "You can get back" first, then Free up space, then the chart and where the space went.
- **Free up space:** filters by answer with counts and sizes, Select All for what's shown (never backups), the ticked total and Copy above a list that scrolls inside the panel.
- **Backups:** names with backup, save, recovery, private, signing, keychain, secret, credential or provisioning are Might hold work and marked; they're left out of old items inside a folder.
- **Recheck before copying:** one open-files snapshot, then each item in parallel: gone, open in an app (Spotlight and Finder reads don't count), or changed since the scan (the item and what's directly inside it; for folders with over 2,000 entries, the folder's own date).
- **Trash command:** one line in a subshell. For each item: already gone, else macOS's /usr/bin/trash, else Finder with five minutes and a note that macOS may ask for a password. An item counts as moved only when its path is gone. Android emulators take their .ini file along.
- **History:** Cleanups and Scans. Each copied command is saved as a new file each time it changes; the newest state shows.
- **Words:** Your call is now Might hold work. Tiles, filters and legends say what each answer means.

## Evidence

| Check | Result |
|---|---|
| Test suites | 306 checks pass (Core 28, Detail 33, ScanLimit 28, Planner 19, Discovery 72, Overview 126), including backup rules, the recheck, the command text and History storage |
| Suggestions on this Mac (copy of saved scans) | 12 hours: 88 items, 179.5 GiB (5 safe, 34 rebuildable, 49 might hold work, 5 backups). 1 day: 78, 134.17 GiB. 1 week: 18, 16.47 GiB. Built in 2 to 36 ms |
| Backups caught | projectreach/generated/device-backups (5.96 GiB of dated iPad backups, rebuildable in 0.17), two iPhone app backups in Codex scratch, a Codex recovery copy, a private-phone test home |
| Copy flow, copy of saved scans | 1 week: 18 asked, 17 copied, a missing path left out, 2.4 s. 12 hours: 84 asked, 82 copied; Xcode DerivedData left out as changed since the scan, which it had been. The clipboard matched the expected command, and History saved the cleanup |
| Trash command, disposable disk image | Pasted into an interactive shell: 124 items (names with quotes, apostrophes, backslashes and accents, a missing path, an emulator .avd with its .ini) moved in about 30 s; one reported already gone. A read-only folder moved through Finder after its password prompt; with the prompt cancelled it was reported NOT moved (still in place). After Finder stalled on a read-only disk, the next item still moved |
| On screen | Overview order, chips with counts, Select All ticking 83 of 88 (5 backups skipped) and enabling Copy (83); History opens on Cleanups. No command was copied in the real app, so History has no test entry |
| Package | Signed app verified with codesign --verify --deep --strict, DMG checksum VALID, installed in /Applications |

## Limits

- "Untouched" is the newest change a scan saw; the recheck looks at each item and what's directly inside it, not every file deep down.
- On macOS 14 the trash tool doesn't exist, so every item goes through Finder.
- Finder can stall on a disk without a Trash; the command waits five minutes for that item and goes on.
- Nothing on this Mac's disk was deleted, moved or trashed during this work. Test folders lived on disposable disk images.
