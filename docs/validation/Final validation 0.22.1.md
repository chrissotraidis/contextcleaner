# Final validation 0.22.1

Build 57. Three changes from people trying 0.22.0 on their own Macs.

## What changed

| Before | After |
|---|---|
| Claude Code's scratchpads (`/private/tmp/claude-<uid>/<project>/<session>/scratchpad`) were outside every scanned place; a 7.2 GB Rust build left there didn't show up | A Coverage place under AI tools lists each project's folder there. Each is temporary, named "Claude Code scratch · <project>", Safe to remove after 3 days unused, Review first before. Only folders inside `/private/tmp/claude-<uid>` can go in a Trash command, and only when you own it |
| `~/GitHub` was the only projects folder; "is it in a project" was spelled out in five places | `Coverage.projectRoots` (GitHub, Developer) is used by discovery, build-folder rules, project names, location hints and Everything else. `~/Library/Developer` doesn't count |
| "Change Places…" in the scan window was a SettingsLink, opening Settings on whatever tab was last shown | It closes the scan window and opens Settings › Coverage with Your folders open. The Settings tab is now part of the model, so the toolbar and menu still open Settings as before |

## Evidence

| Check | Result |
|---|---|
| Change Places… | In the installed build: Scan Folders…, then Change Places…, closed the sheet and opened Settings on Coverage with Your folders open and Add Folder… showing |
| ~/Developer | A project's `target` folder there is build output and its hint reads "Developer/app"; `~/Library/Developer/Xcode` gets neither |
| Claude Code scratch | A project folder there is temporary and named for its project; a folder inside may go in a command, the scratch root and other `/private/tmp` folders may not; 3 days unused is Safe, an hour is Review first |
| Compiler | No warnings, no errors |
| Test suites | 381 checks pass, 3 new |

Not checked on a Mac with real Claude Code scratchpads: this Mac has none.
