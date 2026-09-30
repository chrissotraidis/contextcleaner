# Goal loop 0.16

Feedback from Sep 30, 5:50 PM, after a full scan.

## Outcome

Charts read the same way everywhere, and "Everything else" stops being a 1.9 TiB mystery.

## Checks, in order

1. Charts use one framing: space used. Up means the disk filled, down means space came back. Headline, bars, axis, hover and legend agree. Days before the first reading are not drawn or hovered as "no readings".
2. The level chart shows used space rising toward a "Full" line, drawn honestly (no smoothing overshoot).
3. Codex scratch (~/.codex/scratch, 274 GiB measured) is scanned, one folder per task, with a plain answer. Ollama models, DiffusionBee and Android emulators are scanned too.
4. Everything else explains known folders (Ollama, DiffusionBee, Gemini/Antigravity, Android SDK, Rust, backups, ...) and every row can be opened to see what's inside.
5. Git projects inside Everything else (GitHub, Codex worktrees) say whether they are backed up: on a remote, nothing unpushed, nothing uncommitted, no stashes, and which ignored files git would not keep. Backed up and unused for 30+ days are summed with a copyable Trash command.
6. VoiceOver reads the folder buttons in Everything else as "Show in Finder".
7. Read-only throughout. Tests pass, the update benchmark doesn't regress, on-screen check in dark and light, then build, install, release and push 0.16.0.

