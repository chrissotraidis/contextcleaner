# Improvements from 2026-10-05 review

Feedback from using 0.19.1 to clear a nearly full disk. Free up space is the part of the app in daily use; everything below is judged by how much it helps there. Status is updated as each item ships.

## Words that confuse

1. **"Might hold work"** reads as a verdict on a terabyte of folders, most of which hold nothing worth keeping. Needs a clearer name for "look before you remove it".
2. **"Safe"** on the Folders tile should say **Safe to remove**, as everywhere else.
3. **"Leave it"** sounds like "Ignored", but it's a different list, and it's empty (0 B). Either explain it or drop it.
4. **Ignored › "Not scanned"** shows a size, so how can it be "not scanned"? It's the size from before scanning was turned off, and half a terabyte sits there with no way to tell whether any of it could go.
5. **0-byte folders** (Codex task outputs synced to iCloud) are listed as "Might hold work". They take no space on this Mac; they shouldn't sit in a removal list as if they did.
6. **"Old items"** opens a list of the *folders* that hold old items, each marked as used recently. The old items themselves should be what you see.
7. **"Parallels is running right now"** when it isn't: the open-files check comes from the last scan, not now.
8. **"Never deletes"** appears twice (sidebar and header).

## Getting things removed

9. **Free up space deserves its own place in the sidebar**, and should be where the app opens. It's the only part used every day.
10. **Folders can't do what Free up space does.** Selecting folders should give the same Copy Move-to-Trash Command, including for "Might hold work" folders you've looked at, without going back to Overview.
11. **The copy command is the main action.** Make it faster: fewer clicks, a keyboard shortcut, clear feedback.
12. **The Trash note sits at the bottom** of Free up space, which is odd. Move it up with the other controls.
13. **Say what's inside big opaque folders**: Parallels virtual machines (snapshots, disk images) and Ollama models (which model, how big, the command to remove it).
14. **"Everything else" is 1.6 TiB** and stays unknown until Look Inside is pressed. It should look on its own.
15. **Export Cleanup List** only lists Safe folders; Rebuildable belongs in it too.

## Speed

16. **Folders › All folders** takes a while to switch to, and sorting by Last used is slow.

## History

17. **A graph of what's been removed**, by day, plus totals: space moved to the Trash, cleanups, scans.

## Settings, About, README

18. **No settings button** in the window. A gear next to search, as on most Mac apps.
19. **Settings** could be easier to navigate and better looking.
20. **Scheduled checks** must be checked end to end, and **Full Disk Access** should be detected and stated.
21. **About** should say what the app is, its version, and link to the project.
22. **README**: first-class, with badges like the other repositories.

