# Security

Context Cleaner reads folder sizes and dates, and copies Terminal commands you run yourself. It never deletes, moves or changes your files, and it has no network code.

## What it's built to withstand

| Risk | What Context Cleaner does |
|---|---|
| A folder you downloaded or copied carries its own git config that names a program to run (fsmonitor, a filter, a signature checker) | Every git read switches those settings off with `-c`, which wins over every config file, and empties each filter the config names. Git runs read-only and offline, with no prompts, no hooks and no optional locks. Without Apple's developer tools, git isn't run at all |
| A file name that is really shell code, such as `$(…)` or a backtick | Every name in a copied command is single-quoted, so the shell reads it as text. This is tested in zsh and bash with quotes, `$(…)`, backticks, backslashes, `!`, newlines and globs |
| Names with control or invisible characters, which could garble the terminal or hide what a command says | Never put in a command |
| A link where a folder was | Never moved, at copy time or when the command runs. Finder would move what it points to |
| A command pasted much later, from clipboard history | Checks the clock first and moves nothing after an hour |
| A command that reaches too far | Only paths inside your home or temporary folder. Never home itself, its top-level folders, a folder directly in ~/Library, keychains, iCloud Drive, `.ssh`, `.gnupg` or the Trash. Virtual machines, simulators, chat history and app libraries are never offered whole |
| Something changed between the scan and the copy | Each item is checked again when you copy: anything gone, open in an app, or changed anywhere inside since the scan is left out. Items with no date from the scan count as changed. If open files can't be checked, nothing is copied. Clean worktrees, and projects from Everything else, get git's full test again |
| Reading files it shouldn't | Only metadata. The few small files it reads (git pointers, manifests, plists) must be regular files under 1 MiB, never through a link, never a pipe. iCloud placeholders aren't downloaded |
| Telling git a worktree is gone | Only in a real repository inside your home folder, with git's fsmonitor and hooks off |
| Its own data | New files only, created with `O_EXCL` and `O_NOFOLLOW`, readable by you alone, under `~/Library/Application Support/Context Cleaner`. Open files are saved one line per app and item, so each scan stays small |
| Code injected into the app | Built with the hardened runtime |

The commands use macOS's `trash` tool, or Finder as a fallback, so everything goes to the Trash and Put Back works.

## Out of scope

Another program running as you can already change your files, so it can also change Context Cleaner's saved data. Context Cleaner doesn't try to defend against software you've already let run.

## Reporting a problem

Please use **Report a vulnerability** on the repository's Security tab, which keeps the report private. For anything else, open an issue.
