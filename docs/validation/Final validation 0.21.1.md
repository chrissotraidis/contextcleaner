# Final validation 0.21.1

Build 48, from source b0b5cab. A security and reliability pass; the threat model is in [SECURITY.md](../../SECURITY.md).

## Found and fixed

| Problem in 0.21.0 | How it was shown | Fix |
|---|---|---|
| Reading git status in a folder whose own git config named an fsmonitor or filter program ran that program | A test repository with a marker-writing program: plain reads ran it twice (fsmonitor and filter process); the app's reads now run nothing | Every git read passes -c settings that switch off fsmonitor, hooks, signature checks, pagers and external diff, and empties every filter driver the config names. Git's environment can't point it elsewhere |
| The Ollama command wrapped a name in quotes without escaping quotes inside it; the "remove worktree" command used double quotes, so $(…) in a path ran | Reading the code | One quoting function for every command, tested in zsh and bash |
| Simulator commands used any folder name | Reading the code | Offered only for a real device ID |
| A link could be in a Trash command; Finder's fallback would move what it points to | Reading the code | Links are left out at copy time and refused by the command itself |
| A command pasted hours later, from clipboard history, still ran | Reading the code | The command checks the clock and moves nothing after an hour; the app watches for that hour |
| Exported cleanup lists held Trash commands that skipped the recheck | Reading the code | Removed; the list says to copy in Free Up Space |
| Without Apple's developer tools, /usr/bin/git and xcrun open macOS's install dialog | /usr/bin/git is a stub | Neither is run unless xcode-select finds the tools |
| A worktree's .git file was read with no size or type check | Reading the code | Read only as a small regular file, never through a link or from a pipe |
| A stuck git was asked to stop but never forced | Reading the code | Forced two seconds after its limit |
| No hardened runtime | codesign -dv | Built with it: flags=0x10000(runtime) |

## Evidence

| Check | Result |
|---|---|
| Test suites | 359 checks pass: Core 30, Detail 40, ScanLimit 28, Planner 21, Discovery 80, Overview 160. New: names with quotes, $(…), backticks, backslashes, !, newlines and globs reach zsh and bash as text; worktree and simulator commands; protected paths and invisible characters; a link and a missing path are left alone and an expired command moves nothing, run for real in a temporary folder; git safety arguments; fish gets the command wrapped |
| Command forms | Written out, from a list, with worktree pruning, and wrapped for fish: all parse in zsh and bash (-n, nothing run). fish isn't installed here; the wrapped form has no backslashes inside quotes, which is what fish reads differently |
| Git on real data, read-only | 75 Codex worktrees: 73 read through the new code; 2 fail exactly as plain git does, because their main repository is gone, so they're never called clean |
| Demo app, hardened runtime | One copy: "Copied", Open Terminal beside it, and the clipboard held a command starting with the clock check. The clipboard was restored |
| Real app | Installed, launched and read; no command copied, nothing moved |

## Limits

- Not notarized; that needs a paid Developer ID.
- The threat model excludes software already running as you, which can change your files anyway.
- No open-source license has been chosen.
