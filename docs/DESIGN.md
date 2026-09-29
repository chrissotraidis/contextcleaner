# Context Cleaner design system

Source of truth for every screen. Grounded in Apple's Human Interface Guidelines for macOS (sidebars, toolbars, charts, color, writing) and the Liquid Glass adoption guidance. When code and this document disagree, fix the code.

## 0.9 spec — calm, visual, obvious

### 0.9.1 — answer "can I remove it?" everywhere

The question people open this app with is "what can I safely delete?" Every folder now carries one of three verdicts, and every screen shows it in the same words and colors.

| Verdict | Color | Means | Examples |
|---|---|---|---|
| **Safe to remove** | green | A tool recreates it, nothing had it open, and it hasn't been used recently | package caches, Xcode DerivedData, device install caches, build output unused for 7+ days, simulators unused for 30+ days, never started, or unable to run |
| **Check first** | orange | Might be fine, but look first; the card says what to check | work folders, recovery copies, recently used build output, project build output with unknown last use, downloads, AI models |
| **Keep** | gray | Manage it inside its own app | app libraries (OpenEmu, Steam, CrossOver), conversation history, folders you marked as expected |

Rules: project build output is "safe" only after 7 days without changes, so unknown last use there means "check first". Caches that their own tool recreates (package downloads, DerivedData, device install caches) are safe whatever their age, because the only cost is a slower next run. Open files downgrade to "check first"; your own marks win; the Simulator Devices folder is never removed whole. Simulator facts (name, iOS version, last used, current size) come straight from Xcode, so they are never stale: each device row is named after its device ("iPhone 17 Pro · iOS 26.5") and shows its size now, and the Devices folder shows Xcode's current total with a note when an older scan measured something different. Saved scans are never rewritten. When an older scan didn't record last use, the Folders list says "Not recorded" and scanning that folder fills it in. Each verdict states its reason, the evidence ("Last used 3 weeks ago · size from 2 days ago") and **how to remove it yourself** (in Finder, Xcode, or the tool's own clean command, copied never run). The app still never deletes anything.

Folders shows **Last used** and **Can I remove it?** columns. Overview leads with the safe total. Folders that no longer exist show "Gone" and leave all totals. When most sizes come from a full scan older than a day, the status line says so.

Charts: no vertical gridlines, faint horizontal ones, smooth monotone line with a soft fill, a labeled dot for the latest value, a hover bubble, and a quiet "No readings yet" area where there's no data.

Written from an audit of every 0.8 screen, sheet, menu and Settings tab (dark and light, 1103 × 752 and 1480 × 920 points) plus the user's 2026-09-28 screenshots. It supersedes every earlier rule below where they conflict.

### What the audit found

- The storage chart plotted **free** space, so filling the disk drew a falling line that read like a burndown chart. Readings came only from scans, so points bunched together with long flat bridges between them.
- Overview stacked five blocks of equal weight: drive card, chart, four count tiles, categories and largest folders. Nothing said "look here first", and the compact window scrolled.
- Report and the appearance toggle shared one toolbar capsule, so they looked like related commands.
- Folders repeated "First scan" and "Measured" on nearly every row. These words told you nothing.
- Scan Issues read like a warning even when empty, and rows did not say what to do.
- Coverage was one long form of 26 paths with sentences under each. It scrolled several screens.
- Text sizes drifted between headline, callout, caption and caption2 with no rule.

### Screen by screen

| Screen | Question it answers | Look here first | One action | Hidden until asked |
|---|---|---|---|---|
| Overview | Is my disk filling up, and what's using it? | Space used chart with the change for the chosen range | Scan | Caveats (info popover), minor categories (More) |
| Space used chart | What happened to my disk this week? | Headline change ("+148 GB used in 7 days") | Pick a range or drag across a span | Exact reading (hover), what grew (span) |
| Folders | Which folders are large or growing? | Size column, sorted largest first | Select a folder | Status words (shown only when they matter) |
| Folder inspector | What is this folder and is it growing? | Size and one sentence about it | Show in Finder | Sources, path, processes, history table (Details) |
| No folder selected | What does this list add up to? | Total of the visible list | Select the biggest | — |
| Watchlist | What am I keeping an eye on? | Trend per folder | Add from Folders | — |
| Couldn't Scan | What couldn't be read, and how do I fix it? | Plain reason on each row | The row's fix button | Technical diagnostic (inspector Details) |
| Scan History | What was checked and when? | Folder name and result | Expand a row | Measurements, disk space at the time |
| Scan sheet | What will a scan read? | The app names that will be checked | Start Scan | Exact paths (disclosure) |
| Report sheet | What will the file contain? | One-line description | Save | Full Markdown (scroll) |
| Settings › General | How does the app look and when does it check? | Appearance | Scheduled checks | — |
| Settings › Scanning | How far does a scan go? | One plain sentence | Leave defaults | Limits (Advanced) |
| Settings › Coverage | Where does the app look? | Group rows with on/off counts | Toggle a group or row | Path and description (expand or hover) |

### Type scale

Five sizes, always used the same way. No fixed point sizes; system text styles only.

| Role | Style |
|---|---|
| Page title | `.title2` semibold |
| Hero number | `.largeTitle` rounded semibold, monospaced digits |
| Section heading | `.headline` |
| Body and row text | `.callout` |
| Secondary, captions, axis labels | `.caption` (never `.caption2`) |

### Spacing

- Page padding 22 points horizontally. Space between blocks 16. Inside a panel 16 padding and 12 between items.
- Rows: 6 points vertical padding. Sparklines 64 × 18 points.
- One panel style (`Panel`), one background (`.background.secondary`), no borders.

### Color

- Accent color: selection, primary actions and the used-space area.
- Orange (`Color.growing`) marks growth: "more space used", growing folders and positive daily bars.
- Green (`Color.stable`) marks space given back: negative daily bars and expected growth.
- Red (`Color.attention`) appears only when something couldn't be scanned. An empty Couldn't Scan list shows no red anywhere.
- Category hues are unchanged from 0.8 and appear only in icons, bars and dots.

### Chart rules

- Show **used** space, filling upward, under a dashed capacity ceiling. The band between the line and the ceiling is free space.
- Even time axis with real labels: hours for 24h, weekdays for 7 days, dates for 30 days. The axis depends on the chosen range and the latest reading, never on redraw time.
- The vertical axis starts below the lowest reading so change is visible. It's labelled with real sizes, and the ceiling is always shown.
- Gaps longer than a range-specific limit break the line. Nothing fills them in.
- The headline states the change in words, with a subject and a time.

### Voice

Short, human and specific. Every number gets a subject and a time. No paragraph longer than two lines by default; anything longer goes behind a disclosure or popover. Commands are verbs in Title Case. The deletion sentence stays verbatim: **"Context Cleaner never deletes files. You decide, in Finder."**

---

## Archive: 0.7–0.8 rules

Kept for provenance. Superseded by the 0.9 spec above where they conflict.

## Principles, in order

1. **Clarity.** One idea per screen. Numbers first, explanation on demand. No paragraph where a sentence will do; no sentence where a label will do.
2. **Familiarity.** Standard macOS structure: sidebar → content → inspector, toolbar for frequent commands, menu bar for everything, Settings under ⌘,. Finder conventions for selection (click, ⇧-click, ⌘-click).
3. **Simplicity.** Five destinations. Everything else is a filter, a badge or a setting.
4. **Agency.** The app observes; the user acts. Every removable listing says who deletes (the user, in Finder) and the app has no delete, trash or clean action anywhere.
5. **Honesty.** Sizes are estimates. Association is evidence-labelled (observed / inferred / unknown). Incomplete scans never present as complete.

## Information architecture

| Destination | Purpose | Contents |
|---|---|---|
| Overview | Where does the space go, right now | Capacity, free-space trend, category breakdown, largest locations. Fits one screen at minimum window size. |
| Folders | What each folder contains and uses | Table with a compact filter menu: All, Scanned, Not scanned, Caches & builds, Growing, Review later, Excluded. Inspector for the selection. |
| Watchlist | What you care about | Watched folders plus significant measured growers. Prioritized by scheduled checks. |
| Scan Issues | What could not be scanned | Access problems, scan limits, missing folders and failures. Unscanned folders are neutral and live in Folders. |
| Scan History | What was checked and when | Named folders and outcomes, newest first; sizes and comparisons expand on demand. |

Retired destinations: Candidates, Recurring, Review Later, Excluded and Growing. These belong in filters or the Watchlist.

## Color

- **Selection and primary actions** use the system accent color. The app never overrides the accent and never tints sidebar icons except Scan Issues.
- **Status colors** are reserved and never used as category hues: red `Color.attention` (cannot measure, error), orange `Color.growing` (grew between comparable scans), green `Color.stable` (expected growth, stable).
- **Category hues**, one each, used for icons, bars and chart segments only: package cache teal · installation cache cyan · build output blue · debugging symbols indigo · simulator purple · mixed workspace brown · recovery backup orchid · conversation history mint · model library yellow · downloads khaki · application data gray · unclassified secondary.
- Text is always the system label colors. Colored text is limited to status words.

## Materials and shape

- Grouped content uses the system background hierarchy (`.background.secondary`) without fixed corner radii. No custom borders. Standard controls, sheets and toolbar groups receive the system shape and material; simple content panels stay rectangular. `GroupBox` is not used: its accessibility structure crashes the automation that verifies every build, and verified builds outrank the nicer API.
- Charts use Swift Charts with fixed domains where the data is a time series, so axes do not move between refreshes.
- Typography uses system text styles only (`.largeTitle`, `.headline`, `.body`, `.caption`); no fixed point sizes.

## Actions

- One context menu (`LocationActions`) for every representation of a location: table row, overview card, inspector. Same items, same order, same wording.
- Toolbar: Scan Folders opens the scope preview; Start Scan begins it. Report opens a local preview. Appearance toggles light/dark. Scan Folder belongs in the inspector and context menu. Search names its fields. Add Folder is in the File menu and Coverage settings. Menu shortcuts mirror frequent commands.
- Wording: sentence case for descriptions, Title Case for commands. Commands are verbs ("Watch", "Exclude from Scans"); descriptions state facts ("Grew 2.1 GiB since Sep 27").

## Copy rules

- Lead with the number, then the meaning, then the caveat, and put the caveat behind a disclosure if it exceeds one sentence.
- Never say "clean", "free up" or "reclaim" as something the app does. Say "measure", "find", "watch", "reveal".
- The deletion sentence, verbatim wherever removal is discussed: **"Context Cleaner never deletes files. You decide, in Finder."**

## Platform references

- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Apple WWDC25: Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)

Use the native toolbar material and grouping. Keep content backgrounds quiet; applying glass to every content panel obscures hierarchy. macOS 14–15 retains the standard toolbar fallback.


## 0.8 clarity rules (supersede earlier labels)

- Name the object before the mechanism: Folders, Watchlist, Scan Issues, Scan History. A history entry names the folder that was checked. Use Project files and Test devices in presentation; preserve stored category IDs.
- Separate unknown from wrong. Not scanned is a neutral folder filter/count; only access, scan limits, missing paths and actual failures belong in Scan Issues.
- One action at each level: Scan Folders opens a scope preview; Start Scan executes it. Scan Folder checks the selected folder. Show in Finder reveals it. Report previews a local file before saving.
- A number needs a subject and time. Disk capacity and its graph use the same latest reading. Fit the graph to actual sample dates; label units and state that these are discrete readings. Domains only change when readings change. Zero is the chart's vertical baseline.
- Reveal explanation when needed. Default folder details show size, purpose and one next action. No empty chart on a never-scanned folder. History is a compact outcome list with expandable details.
- Use normal words: folders rather than locations, scanned rather than measured, storage on your Mac rather than home volume, scan issues rather than needs attention. Commands state their object.
- Keep system typography, controls and materials. Preserve the Blue C icon and category palette. Red marks failures, not the existence of personal files.


## 0.10: evidence, Keep, idle order, disk map

- **Evidence before verdicts.** Project folders read git, read-only (no index refresh): last commit, merged into the default branch, uncommitted changes, and whether a worktree is still registered. Recent activity (a commit in the last 7 days or anything uncommitted) is always Check first. Merged or unregistered, clean and quiet for 14 days is "looks finished", which offers git's own worktree removal. Evidence shows as one line under the reason, with a branch icon.
- **Order.** Folders default to big and unused first: size × days idle (capped at 90), unknown idle time weighs a third, and app-managed Keep folders weigh a quarter. The Order menu offers Largest, Longest unused and Name.
- **Keep.** "Keep, Never Suggest" is a user choice stored as an optional flag. It overrides every rule, removes the folder from Folders, Safe and Check first, and lists it in **Kept** (purple) with turned-off folders, a total and a share of the disk.
- **Disk map.** One bar for the whole disk, with outlined Free space, By answer or By type. Hovering explains a segment and clicking opens it. It replaces the old safe banner and category panel.
- **How long it's sat unused.** Labeled rows (this week, this month, 1–3 months, 3+ months, unknown), stacked by answer and sized linearly with the number written beside each row.
- **Gone means gone.** Missing folders leave every list, total and Couldn't Scan.
- **Virtual machines** are a type (steel blue, desktop icon). They're never safe; the advice points to the app's own tools.
