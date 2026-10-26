# Final validation 0.23.3

Build 63. A look over the whole app on this Mac, after Chris pointed out the top of Overview looked messy and asked why the Windows 11 virtual machine was "used in the last hour".

## Windows 11

Context Cleaner was right: Parallels reports the machine as running (`prlctl list`: running), started at 12:20 AM and holding about 32 GB of memory, with no window open. Its disk file changed a minute before the check. The list said "Open in Parallels Desktop at last scan" and "in the last hour", which made you work it out; it now says "Running at last scan".

## What changed

| Before | After |
|---|---|
| After a scan, Overview and Free Up Space showed two lines: "Scanned 706 folders · 23 grew · 30 no longer on disk" and "Sizes from the scan 26 minutes ago · 705 folders · … · 22 growing", with counts that didn't quite match | One line: "Scanned 26 minutes ago · 705 folders · 51 not scanned yet · 22 growing", with a check mark, or an amber clock after a day. Other pages still show the scan result; a stopped scan or folders that couldn't be read show everywhere |
| Overview's map said "You can get back about 230 GiB" and the card below "386 GiB you could get back now", counting different things | "About 230 GiB is safe, old or rebuildable" and "386 GiB untouched for a week or longer", each saying what it counts |
| The line under the map's total was cut off ("… nothing here del…") | "1.52 GiB safe to remove · 36.65 GiB old items · 162.39 GiB rebuildable" fits |
| Nearly every row had a second line, "size from 13 hours ago", "size from in the last hour", "size from Xcode, now" | Rows say when a size was measured only when it's over a day old ("measured 3 days ago"); a folder's card always says it |
| "Downloads · Downloads" | "Downloads" |
| History: "Moved all 9 to the Trash · 21 left out when rechecked" | "Moved 9 to the Trash · 21 left out when rechecked"; "all" only when nothing was left out |

## Evidence

| Check | Result |
|---|---|
| A build of this change on this Mac, Overview | One status line; the map's total and the card below say what each counts; nothing cut off |
| Same build, a one-folder scan | "Scanned 1 folder" shows in Watchlist and Folders, not on Overview or Free Up Space |
| Same build, Watchlist | One line per row in Last used; Windows 11 says it was running |
| Compiler | No warnings, no errors |
| Test suites | 397 checks pass, 3 new: when a row shows its measured time, the Downloads name, a running virtual machine |

