# Final validation 0.21.4

Build 51. A code-quality pass: dead code, repetition, readability. No decision the app makes changed.

## What changed

| Before | After |
|---|---|
| 9 unused properties, functions and types (a sparkline, a trend color, idle-time buckets, an unused-space summary, a daily toggle and others), and InspectCLI.swift, which no build compiled | Removed. A word-level scan of every declaration now finds none unused, apart from three a saved file or the system reads |
| The same concurrentPerform-into-a-buffer loop written out 6 times, each force-unwrapping a buffer address that isn't guaranteed for an empty array | One parallelMap, which returns at once for an empty list |
| Clipboard, Show in Finder, Open Trash and the Full Disk Access link written out 3 to 11 times | One function each; all 21 uses checked |
| 38 lines over 300 characters, including a five-way nested ternary and two identical 345-character chart axes | 29, the rest being sentences shown to people. A plain problemSentence function and one byteAxis modifier |
| Watchlist's empty state named "Add to Watchlist", which doesn't exist; Ignored's suggested a filter | Each says what to do, with the real menu names. Every "choose …" in the app was checked against a real label |

Apple's swift-format was tried on a copy. It compiled, but split some lines awkwardly (an enum case from its value, .fixedSize( from its arguments) and added about 1,600 lines, so the existing style was kept and only the worst lines were fixed by hand.

## Evidence

| Check | Result |
|---|---|
| Compiler | No warnings, no errors |
| Test suites | 368 checks pass |
| Demo app | Both chart axes, the Folders selection summary by category, a folder's size over time and Ignored drawn and read on screen after the changes |
| Real app | Installed and launched; nothing copied or moved |
