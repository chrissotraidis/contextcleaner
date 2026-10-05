# Final validation 0.21.0

Build 47, from source 19dbd36. The changes answer [the 0.20.0 review](../IMPROVEMENTS.md#improvements-from-the-0200-review-2026-10-05-evening).

## Evidence

| Check | Result |
|---|---|
| Test suites | 349 checks pass: Core 30, Detail 40, ScanLimit 28, Planner 21, Discovery 80, Overview 150. New: Safe to remove and Rebuildable both lose nothing and Review first doesn't; each item's kind; when a copy asks first (any Review first item, 20 or more items, 100 GiB or more, and just under both doesn't); the chosen terminal is used while installed, otherwise Terminal |
| Demo app, end to end | Opens on the Overview. Free Up Space: Nothing lost and Review first filters, By kind groups with a tick box each, Select All of 21 asked in place ("21 items, 98.2 GiB, including 9 Review first…"), Copy Anyway copied 20 of 21 and named the one left out in the footer. Seven Nothing lost items copied straight away. Folders: tick boxes select rows, one Copy button; two Review first folders asked first. Settings › Terminal listed Terminal and Ghostty; after a copy, **Open Ghostty** brought Ghostty to the front. The scan sheet shows What a scan does. The clipboard was saved before and restored after every copy |
| Found and fixed while checking | Row tick boxes in Free Up Space didn't redraw after Select All or a group tick, though the count above them did. The row now reads its value when drawn. The same pattern was avoided in the new Folders column |
| Real app, read-only | Opens on the Overview. Where the space went shows Grew (481.91 GiB) to the right and Freed (375.95 GiB, GitHub projects and Codex recovery copies) to the left. Free Up Space at 1 day: Nothing lost 51 · 198.23 GiB and Review first 15 · 77.24 GiB, where 0.20.0 showed Safe to remove 0 · 0 B. Folders shows a tick box on every row. Terminal set to Ghostty, as asked |
| Screenshot | Free Up Space screenshot remade from the demo build with made-up folders |

## Limits

- No command was copied in the real app, so nothing new is in its History, and nothing on this Mac was moved.
- Open Terminal opens the app only. Pasting and pressing Return stay with you, as before.
