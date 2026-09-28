# Context Cleaner design system

Source of truth for every screen. Grounded in Apple's Human Interface Guidelines for macOS (Designing for macOS, Sidebars, Panels, Toolbars, Color) and the Liquid Glass adoption guidance. When code and this document disagree, fix the code.

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
