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
| Locations | Everything the app measures | Table with one filter row: All · Rebuildable · Growing · Review later · Excluded. Inspector for the selection. |
| Watching | What you care about | Watched locations plus locations that keep growing. Checked first on every scan. |
| Needs Attention | What could not be measured | Unreadable, limited, missing or unmeasured. Sidebar badge shows the count. Red is used here and only here for status. |
| History | What has changed | Timeline of scans, newest first, with per-scan deltas. |

Retired as destinations: Candidates (now the Rebuildable filter), Recurring (folded into Watching), Review Later and Excluded (filters), Growing (filter plus the orange status color), Scanned Locations (renamed Locations).

## Color

- **Selection and primary actions** use the system accent color. The app never overrides the accent and never tints sidebar icons except Needs Attention.
- **Status colors** are reserved and never used as category hues: red `Color.attention` (cannot measure, error), orange `Color.growing` (grew between comparable scans), green `Color.stable` (expected growth, stable).
- **Category hues**, one each, used for icons, bars and chart segments only: package cache teal · installation cache cyan · build output blue · debugging symbols indigo · simulator purple · mixed workspace brown · recovery backup orchid · conversation history mint · model library yellow · downloads khaki · application data gray · unclassified secondary.
- Text is always the system label colors. Colored text is limited to status words.

## Materials and shape

- Grouped content uses the system background hierarchy (`.background.secondary`) with the 12 pt continuous radius macOS uses for grouped panels. No custom borders, no per-view radii. `GroupBox` is not used: its accessibility structure crashes the automation that verifies every build, and verified builds outrank the nicer API.
- Charts use Swift Charts with fixed domains where the data is a time series, so axes do not move between refreshes.
- Typography uses system text styles only (`.largeTitle`, `.headline`, `.body`, `.caption`); no fixed point sizes.

## Actions

- One context menu (`LocationActions`) for every representation of a location: table row, overview card, inspector. Same items, same order, same wording.
- Toolbar: Scan Now, Rescan This Folder, Export Report, appearance toggle, search. Everything in the toolbar also exists in the menu bar with a shortcut.
- Wording: sentence case for descriptions, Title Case for commands. Commands are verbs ("Watch", "Exclude from Scans"); descriptions state facts ("Grew 2.1 GiB since Sep 27").

## Copy rules

- Lead with the number, then the meaning, then the caveat, and put the caveat behind a disclosure if it exceeds one sentence.
- Never say "clean", "free up" or "reclaim" as something the app does. Say "measure", "find", "watch", "reveal".
- The deletion sentence, verbatim wherever removal is discussed: **"Context Cleaner never deletes files. You decide, in Finder."**
