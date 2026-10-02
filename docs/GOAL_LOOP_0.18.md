# Goal loop 0.18

Feedback from Oct 3, 6:31 AM: 1.95 GiB free. Free up space is the part of the app in daily use, but its controls sat below a long list, the Trash command seemed to fail for more than a handful of folders, it was unclear whether anything had been copied, and Safe, Rebuildable and Your call didn't explain themselves. "You can get back" sat at the bottom. Suggestions must be certain.

## Outcome

Open the app, pick how long things must have sat untouched, select everything that's safe to lose in one click, copy one command, and see exactly what it moved.

## Checks

1. Every suggestion double-checked against this Mac's scans. Backups, saves, recovery and private copies are never rebuildable and never ticked by Select All.
2. The command is rechecked before copying: gone, open in an app, or changed since the scan is left out, with the reason.
3. The command works for any number of items, quotes any path, reports a line per item, and only counts an item once it's gone. Tested by pasting into an interactive shell.
4. Overview order follows use: free space and "You can get back", then Free up space with its controls above the list, then the chart and where the space went.
5. Filters by answer with counts and sizes; one-line meanings of the answers everywhere. "Your call" becomes "Might hold work".
6. History records each cleanup: moved, still in place, left out.
7. Tests, real-data check, on-screen check, then build, install, release and push.
