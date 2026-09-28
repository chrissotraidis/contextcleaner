# Context Cleaner 0.9 — goal loop

Assigned by the user on 2026-09-28 after reviewing three 0.8 screenshots. The text below is the agreed loop, unchanged.

---

Goal: Context Cleaner 0.9 — "calm, visual, obvious"
Non‑negotiable rule, above everything else: nothing is deleted, trashed, moved, pruned, reset or cleaned on this Mac. That covers your files, app data, old builds, DMGs, test fixtures and scan history. The app stays read‑only toward scanned folders, and its own records stay append‑only. Every build goes to a new folder. If any step seems to require removing something, I stop and tell you.
Working rules: use the existing ~/GitHub/contextcleaner checkout, commit in small verified steps, push to GitHub, and keep the Blue C logo.
Pass 1 — Audit before touching anything
Walk every screen, sheet, menu and Settings tab in light and dark mode at small and large window sizes. For each one, answer four questions:
1. What question does this screen answer?
2. What is the one thing to look at first?
3. What is the one action?
4. What can be hidden until asked for?
Write the answers into docs/DESIGN.md as a screen‑by‑screen spec, with a type scale (a few fixed sizes, used the same way everywhere), spacing and color rules. Every later pass checks against this spec.
Pass 2 — Make the storage chart intuitive
Replace "Free space over time" with "Space used". The line goes up when the disk fills, which matches how people think about it. Specifically:
- Show a filled area of used space with a visible ceiling at total capacity, so headroom is obvious at a glance.
- Use an even time axis with real day labels, and ranges of 24h, 7 days and 30 days.
- Hovering or clicking a point shows the date and the amount used. Selecting a span shows "+38 GB used between Sep 27 and Sep 28." When comparable folder scans exist, it also shows what grew in that span, with the top folders linked.
- Add a companion bar view, "Change per day," for people who think in daily deltas.
- To give the chart real continuity, the app records a tiny capacity reading about once an hour while it's open. Each reading is a timestamp and two numbers. It adds data, reads no folders and removes nothing. Gaps stay gaps; the chart never fills them in.
Accepted when: someone who has never seen the app can say what happened to their disk this week within 5 seconds.
Pass 3 — Overview that doesn't tire you out
Cut the Overview to three things, with no scrolling at the default window size:
- Hero: the storage ring plus the "Space used" chart, as one unit.
- What's taking space: the category bar becomes interactive. Hovering a segment highlights it; clicking filters Folders.
- Top folders: a short list with a tiny growth sparkline on each row.
The four count tiles (Scanned, Not scanned, Growing, Scan issues) collapse into one quiet status line, such as "145 scanned · 64 waiting · nothing needs attention," which appears only when it says something useful.
Pass 4 — Toolbar and actions
- Split Report and the appearance toggle, which currently share one capsule and look related. The appearance toggle moves to View ▸ Appearance and Settings. The toolbar keeps Scan, Share Report (a standard share/export button) and Search.
- Label the primary action by what it does. Scan shows scope and progress inline, then a short result ("Scanned 208 folders · 3 grew · 2 couldn't be read").
- Right‑click menus stay identical everywhere they appear.
Pass 5 — Folders and the inspector
- Replace the repetitive "First scan / Measured" columns with a Trend sparkline and one plain status word that's only shown when it matters.
- Replace the empty "Choose a folder" panel with a useful default: a summary of the current filter (total size, biggest item, what grew).
- The inspector leads with size, the owning app or project, a small size chart and one sentence on what the folder is. Evidence and paths move behind a "Details" disclosure.
Pass 6 — Scan Issues becomes obvious
Rename it "Couldn't Scan." Each row states the reason in plain words ("macOS blocked access," "Too large for the time limit," "Folder no longer exists") and offers one fix button. When there are no issues, the item stays visible but quiet, with a clear empty state, so it doesn't sit there like a warning.
Pass 7 — Settings that end
Settings becomes three short tabs.
General holds appearance and scheduled checks.
Scanning holds limits, with sensible defaults and an "Advanced" disclosure.
Coverage becomes a compact checklist grouped by kind (AI tools, developer tools, games and emulators, downloads, your folders). Each row shows the app name, whether it's on this Mac and its last scanned size. The path and description appear on hover or expand, and groups collapse. Filters let you show all locations, only those on this Mac, or only those turned off. The target is a Coverage tab that fits on about one screen when collapsed.
Pass 8 — Copy and typography sweep
Apply one voice everywhere: short, human and specific. Every number gets a subject and a time. No screen may contain a paragraph longer than two lines by default. Text sizes are checked against the Pass 1 scale on every screen.
Pass 9 — Verify, package, publish
- Run all preserving test suites, plus new tests for the hourly readings, span deltas and the chart's time axis.
- Click through every screen, button, menu and Settings tab natively, in light and dark mode at both sizes, with before/after screenshots kept locally.
- Confirm the older SpaceCheck history hash is unchanged and that earlier builds and DMGs are still present.
- Build a new versioned DMG from committed source, verify its checksum and signature, and update the README (with a short "how to read the chart" section).
- Push and confirm GitHub matches.
How each pass runs
Inspect → change → test → look at it natively → refine. A pass is done when it meets its acceptance check, not when it compiles. After three failed attempts at the same thing, I change approach and note why.
Honest limits I'll keep
- Growth before recording started stays unknown.
- The app still can't prove which program wrote a file.
- Folder sizes aren't guaranteed recoverable space.
- The DMG is ad‑hoc signed, not notarized.

---

## How each pass landed

1. **Audit.** Every 0.8 screen, sheet, menu and Settings tab was captured and reviewed. The screen‑by‑screen spec, type scale, spacing and color rules are in [DESIGN.md](DESIGN.md).
2. **Space used chart.** Used space fills upward under a dashed capacity line, with a gray free‑space band. Ranges are 24 hours, 7 days and 30 days on an even, calendar‑aligned axis. Hovering shows a reading; dragging selects a span, shows its change and the scanned folders that grew most. A Change per day (or hour) bar view sits alongside. Hourly capacity readings are appended while the app is open. Gaps stay gaps.
3. **Overview.** Three blocks: the disk ring beside the chart, one status line, then an interactive category bar and the largest folders with sparklines. At the default window size nothing scrolls, and the chart grows with the window.
4. **Toolbar and actions.** Scan Folders… (or Stop Scan while running) and Export Report… are separate. Appearance moved to View › Appearance and Settings. A bar under the title shows scope and progress, then a one‑line result such as "Scanned 208 folders · 3 grew · 2 couldn't be read". The same folder menu appears everywhere.
5. **Folders and inspector.** A Trend column with sparklines replaces the repeated "First scan / Measured" text. Status words appear only when they matter. With nothing selected, the inspector sums up the visible list. A selected folder leads with size, owner and one sentence; contents and evidence stay folded under What's inside and Details.
6. **Couldn't Scan.** Renamed, quiet when empty, red only when something failed. Each row gives a plain reason and one fix: Allow Access… for privacy blocks, Show in Finder for file permissions, Scan Subfolders for folders too large for the limit, Stop Checking for missing folders, and Try Again for anything else.
7. **Settings.** General covers appearance and scheduled checks. Scanning has one sentence, three buttons and an Advanced disclosure. Coverage is a collapsible checklist in five groups, each with an on count and a scanned size, and it fits on one screen when collapsed.
8. **Copy and type.** One voice across the app, README and report, checked against the five‑size type scale.
9. **Verification and release.** See [validation and limits](validation/Final%20validation%200.9.0.md).

