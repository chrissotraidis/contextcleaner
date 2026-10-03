# Final validation 0.18.2

Build 42.

## What changed

- **List files for long commands.** Over 4,000 characters, the command reads its paths from a NUL-separated list saved under Context Cleaner's data folder (trash-lists), on its own file descriptor. Shorter commands write every path out.
- **Folders multi-select.** Copy Move-to-Trash Command at the top of the selection summary, for Safe and Rebuildable folders, each once.
- **One rule for whole folders.** Never virtual machines (Android emulators excepted, with their .ini), simulators, chat history, app libraries, model libraries, ignored, turned-off or Leave it folders, or a scanned place itself (Downloads, ~/GitHub, Codex scratch) unless it's a cache. The same rule applies to Free up space, folder cards and multi-select.
- **Selection.** Shift-click ranges in Free up space; ticks survive a change of untouched time; the list minimum is 100 MiB.
- **Open Terminal** next to the copied result. **Copied all N** when nothing was left out.
- **Words.** "You decide, in Finder" replaced where removal can also be the command; the export description no longer says "your calls".

## Evidence

| Check | Result |
|---|---|
| Test suites | 309 checks pass, including a list-file command run in zsh and bash on 301 missing paths with quotes, accents and a line break |
| 400 items, disposable disk | 87 KB inline command pasted and moved all 400 in about 2 minutes; the 1 KB list-file command moved all 400 in about 17 seconds |
| Real data (copy of saved scans) | Free up space 12 hours: 111 items, 227.67 GiB; Folders ⌘A: 129 Safe and Rebuildable folders in one command, 247 left out; no scanned place except caches; Downloads, Ollama models and Codex sessions offer no whole-folder command; Android emulators still listed |
| Demo app on screen | Ticks kept across 1 day → 3 days → 1 day; Folders ⌘A copied 11 of 12 (one changed since the scan) with Copy at the top; the command moved only caches and build output on the demo disk |

## Limits

- Shift-click was checked in code; the UI automation used here can't hold Shift while clicking.
- Nothing on this Mac's disk was moved during this work; moves happened on disposable disk images.
