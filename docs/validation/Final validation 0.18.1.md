# Final validation 0.18.1

Build 41. Two fixes found while recording the demo video, on demo data.

## What changed

- **Moved items leave the list at once.** Old items inside a folder that a Trash command moved stayed in Free up space until the next scan, because scans track the folder rather than what's inside it. Paths the watcher sees leave are now dropped from the list; the set clears when a scan is saved.
- **Left-out items stay ticked.** Copy used to untick items the recheck left out, which changed the selection and reset the Copy button before you could read "Copied 20 of 21". Only items already gone are unticked now.
- **Demo build switch.** Compiling with -D DEMO lets a separate build read a stand-in home folder, data folder and disk size from CC_DEMO_HOME, CC_DEMO_DATA and CC_DEMO_DISK, for videos and screenshots. Release builds don't set the flag.

## Evidence

| Check | Result |
|---|---|
| Test suites | 306 checks pass |
| Demo recording | 20 items moved, left-out item still ticked with "Copied 20 of 21", the list dropped from 23 to 3 items (2 backups and the left-out folder) as soon as the move was seen |
| Package | Signed app verified with codesign --verify --deep --strict, DMG checksum VALID, installed in /Applications |
