# Final validation 0.21.3

Build 50. A third pass: first use, full disks, odd names, and what a stranger sees in the repository.

## Found and fixed

| Problem in 0.21.2 | How it was shown | Fix |
|---|---|---|
| A save on a full disk could leave a half-written file, reported as unreadable at every launch | Reading the code | Written to a hidden temporary file, synced, then moved into place with RENAME_EXCL. On a 4 MB disk image, a 20 MB save was refused and left no file of any kind; a second save to an existing name was refused and the first file kept its contents |
| With fewer than 20 folders, the status line said "No scan yet" after a full scan | First launch on an empty home folder with 6 folders | A full scan is known by its scope |
| A name with a newline showed as its first line | The same home folder, with a folder named two⏎lines | Control and invisible characters show as "?" in every name |
| "Left out 1: 1 a link or a protected place" | The same copy | "1 not allowed in a command"; "not checked for open files" |
| Size bars drawn before anything was measured | The scan sheet on first launch | Hidden until there's a size |
| One compiler warning | swiftc | Parallel result slots are a small Sendable type; zero warnings |

## Evidence

| Check | Result |
|---|---|
| Test suites | 368 checks pass: Core 31, Detail 46, ScanLimit 28, Planner 21, Discovery 80, Overview 162 |
| First launch, demo build on a new home folder | The scan sheet opens with What a scan does expanded. After Start Full Scan (1 s, 6 folders): Free Up Space lists 5 items. Selecting all asked first ("5 items, 1.56 GiB, including 3 Review first…"); Copy Anyway copied 4 of 5 and left out the name with a newline. The command quotes 日本語 プロジェクト and it's $(echo ran) correctly and parses in zsh and bash. Clipboard restored |
| Repository | 83 tracked files: no home paths, email addresses, keys, tokens or signing IDs. Every relative link and image in the README and docs resolves |
| Real app | Installed and launched; nothing copied or moved |

## Limits

- Not notarized; no open-source license chosen. These need decisions, not code.
