# Goal loop: Context Cleaner 0.10, "Can I trust this answer?"

Every recommendation must show what the folder is, who uses it, whether you still use it, and what you lose by removing it. It should be obvious at a glance, with visuals that make the size and the idleness clear.

## Hard rules (unchanged)

- Nothing on this Mac is deleted, trashed, moved, pruned or reset, by the app or by me. The app only reads metadata and copies commands for you.
- Every build goes into a new output folder. Earlier builds, DMGs, fixtures and scan history are kept.
- Primary checkout only. Commit in small verified steps, push, and confirm GitHub parity.
- Plain language. Every number gets a subject and a time.

## Workstreams

1. **Evidence behind every answer ("Why we think so")**
   - For project folders (GitHub repos, Codex worktrees), read git metadata only: the last commit date, whether the branch is merged into the main branch, whether the worktree is still registered with its main repo, and whether there are uncommitted changes. Show the result as plain sentences, for example: "Worktree kartpad-release-051: last commit yesterday, branch not merged, 3 uncommitted changes. You're probably still using this."
   - Every folder gets three evidence lines: **What it is**, **Last activity** (the newest of file changes, the git commit and the Xcode device), and **What you lose**.
   - A folder is marked safe only when the evidence supports it. Unknown evidence says "we don't know" and never guesses.

2. **Default order: big and idle first**
   - Folders sort by "idle space" by default, meaning size weighted by how long the folder has gone unused. Recently used folders sink. Other orders are one click away (size, last used, name).
   - Each row shows an idle bar or age chip, so large-but-stale folders stand out.

3. **Keep it: easy exclusion**
   - One click marks a folder "Keep, don't suggest" (right-click, the inspector, or a button in the row). OpenEmu, CrossOver and Steam are obvious first uses.
   - A dedicated **Kept & Skipped** view lists kept and turned-off folders with their total size and share of the disk, and restoring one is one click.

4. **Stop worrying about gone folders**
   - Folders that no longer exist leave every list, total and "Couldn't Scan", and they aren't scanned again. Unreadable folders that have since been removed disappear too.

5. **A dynamic Overview**
   - Replace the flat category bar with one interactive disk map: the whole disk split into Safe, Check first, Keep, Kept by you, Not scanned and Other, with free space as its own part. Hovering explains a part and clicking drills into it.
   - An "Idle space" view shows how much big folders take up by how long they've been unused (for example this week, this month, 3+ months), and each bucket is clickable.
   - It stays short: no scrolling needed on a 1440×900 window for the key facts.

6. **End-to-end review**
   - Walk every view in order (Overview, Folders, Watchlist, Kept & Skipped, Couldn't Scan, Scan History, Settings, scan sheet, report) in dark and light. Fix anything confusing, clipped, slow or inconsistent. Screenshot evidence goes to the validation doc.

7. **Quality gates at every checkpoint**
   - Clean compile with no warnings; the preserving test suites plus new tests for the git evidence, idle ordering, exclusion totals and gone-folder handling; main-thread cost per update stays at 10 ms or below on a copy of the real data.
   - Build into a new folder, verify with `hdiutil` and `codesign`, install to /Applications, check it natively, push, and confirm parity.

## Done when

Opening the app answers, for the biggest idle folders: what it is, whether I still use it (with evidence), and what I'd lose. Keeping or skipping a folder takes one click and shows up in its own view with a total. Gone folders never appear. The Overview's visuals are interactive and explain the whole disk. All gates pass on the installed build, and it's pushed.
