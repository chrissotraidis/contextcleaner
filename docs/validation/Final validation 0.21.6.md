# Final validation 0.21.6

Build 53. Folders kept partly in iCloud, and the advice for folders a scan couldn't read.

## What changed

| Before | After |
|---|---|
| Context Cleaner turns off iCloud downloads for every read. Opening an iCloud-only folder was skipped, but listing one (macOS returns EDEADLK, "Resource deadlock avoided") counted as a failure, so its parent went to Couldn't Scan as "macOS blocked access" | Both are counted as iCloud-only folders. The parent is measured, and Details says how many folders inside are only in iCloud |
| A folder of iCloud-only folders listed 0 files, so it could be called "Empty" and Safe to remove, though moving it would remove it from iCloud | It's "In iCloud only", Not for the Trash. A folder is only "Empty" when nothing inside was skipped |
| Every unreadable folder said "macOS blocked access" with Full Disk Access steps | Only "Operation not permitted" does. Other read errors say "Part of it couldn't be read" and offer Try Again. A folder removed during a scan is skipped |

## Evidence

| Check | Result |
|---|---|
| Real folder | A Codex workspace in iCloud-synced Documents holding a dataless app bundle: before, Couldn't Scan, "macOS blocked access". After, measured at 302 MB and 5,458 files, 1 iCloud-only folder noted; the bundle's folder is In iCloud only. Nothing was downloaded, and the bundle stayed dataless |
| Compiler | No warnings, no errors |
| Test suites | 370 checks pass, two new: iCloud-only folders are never Empty, and only Operation not permitted is called blocked |
