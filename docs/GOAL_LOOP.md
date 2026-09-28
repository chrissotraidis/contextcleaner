# Context Cleaner overhaul — goal loop (assigned 2026-09-28)

Nothing on the user's Mac is deleted, trashed, pruned or reset by the assistant, the app, the tests or the build. The app's only outward action is revealing an exact folder in Finder. Every screen that lists something removable states that the user, not the app, deletes.

Each stage: inspect → implement → build → verify in the real UI → versioned DMG → commit to main.

| Stage | Scope | Done when |
|---|---|---|
| 0 | Design system + information architecture (`docs/DESIGN.md`) | Five sidebar destinations, semantic palette, system materials, one shared context menu documented and applied to the shell |
| 1 | Settings window (⌘,) and simplified scanning | General / Scanning / Coverage tabs; toolbar = Scan Now + Rescan This Folder; light/dark toggle; menu-bar equivalents |
| 2 | Coverage catalog of hard-coded known writers | Every location lists path, writer, presence, include/exclude; explicit "not scanned" section |
| 3 | Overview redesign | One screen at minimum size; stable free-space chart; stacked category bar; inline scan progress |
| 4 | Locations table | Multi-select with summed selection bar; colored status; Needs Attention red; auto-Watching on growth with undo; search scope stated |
| 5 | Inspector, History, Export | Selected-object inspector; timeline history with deltas; Export Report with preview |
| 6 | Performance | Cached derived state; work off main thread; launch < 2 s measured with Instruments; smooth scrolling |
| 7 | Icon, Liquid Glass, release | Icon candidates; system SDK rebuild; six suites pass; UI verified at two sizes and both appearances; tag v0.7.0; validation report |

Design references: Apple HIG — Designing for macOS, Sidebars, Panels, Toolbars, Color; Adopting Liquid Glass; WWDC25 session 323.

## Continuation checkpoint — 2026-09-28

Stages 0–5 are committed. Stage 6 caches and exact-build Instruments launch evidence are committed as fb7e600; scrolling acceptance remains open. Checkpoint 11 adds stable chart domains, system toolbar grouping and removes fixed radii. Two icon candidates are ready for the user's choice. See [performance evidence](validation/Performance%20checkpoint%200.7.0-10.md) and [remaining release gates](validation/Visual%20checkpoint%200.7.0-11.md). Do not tag v0.7.0 or mark the goal complete yet.
