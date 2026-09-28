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

## Completed acceptance — 2026-09-28

Stages 0–7 are implemented and validated for the local 0.7.0 release. App source: `fc7f0f2`. The final affected-suite rerun brings validation to 154 checks across six suites. The exact release binary rendered its initial frame at 1.14 seconds of Instruments trace time. Native multi-selection, view changes, scrolling, Settings, coverage, report preview and both appearances were exercised. Two icon packages are provided for user choice. Earlier checkpoints remain preserved.

See [final validation, package provenance and limits](validation/Final%20validation%200.7.0.md). This is an ad-hoc signed local release, not notarized public-distribution acceptance or multi-day monitoring proof. The 13 GiB failed profiler trace is disclosed as a manual cleanup candidate; it was not deleted.
