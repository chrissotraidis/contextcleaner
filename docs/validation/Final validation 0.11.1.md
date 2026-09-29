# Final validation 0.11.1 (build 24)

A small fix release built for the README and the GitHub release. It fixes two things seen while taking the README screenshots.

## What changed

1. Removal advice for an active project said "Wait until you're done with…" twice in a row. It now says it once, naming the project.
2. The Overview's disk map labeled folders you turned off as "Kept by you". The purple segment is now named by what's in it: **Kept by you**, **Turned off by you**, or **Kept or turned off**. On this Mac, OpenEmu and CrossOver are turned off, so it reads "Turned off by you · 551.84 GiB", matching the Kept view.
3. The README was rewritten with new screenshots of this build.

## Evidence

| Check | Result |
|---|---|
| Compile | Clean, no warnings |
| Preserving suites | 250 checks: 28 core, 22 detail, 69 discovery/model, 84 overview, 19 planner, 28 bounded-scan |
| New test | Advice for an active project says to wait once and names the project |
| Native UI | Overview in dark and light (new segment label), Folders with git evidence (single "Wait until"), the unused-inside card, scan sheet, Settings › Coverage, cleanup list preview |
| Package | `hdiutil verify` VALID; `codesign --verify --deep --strict` OK (Apple Development); /Applications executable matches the build (`4b254028…`) |
| Source | `237b6ce` |
| DMG SHA-256 | `caef35bb36f89778ff1fa183212b96c6c924603c102e9966b79c3cc34b9ce91d` |
| Legacy SpaceCheck history | unchanged, `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4` |

Nothing was deleted, moved or trashed. Screenshots were taken with `screencapture -l` of the app window only.

## Limits

Same as [0.11.0](Final%20validation%200.11.0.md). The DMG is not notarized, so first launch on another Mac needs **Open Anyway** in Privacy & Security.
