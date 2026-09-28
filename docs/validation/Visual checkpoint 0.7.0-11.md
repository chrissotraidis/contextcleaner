# Visual checkpoint 0.7.0-11 — release still in progress

2026-09-28. Preserved review build, not the final tagged release.

## Changes and evidence

- Toolbar uses native ToolbarSpacer on macOS 26+, with scanning actions grouped separately from export and appearance. Add Location remains in File and Settings / Coverage. Standard older-macOS toolbar fallback remains available.
- Removed fixed corner radii throughout the source. Content uses the system background hierarchy, icons use circles, and the category bar uses a capsule.
- Fixed the remaining moving-chart bug: the time domain is held in view state and anchored to seven calendar days. Capacity refreshes cannot change the free-space axis. New scan points can expand the vertical domain only when necessary; existing bounds never shrink during that view session.
- Five additional chart regression checks pass (Overview now 14 checks). The six-suite performance checkpoint passed 130 checks before these five additions. The chart helper suite was rebuilt with its Coverage dependency after an initial incomplete compile command failed.
- Typecheck, optimized package build, code signature verification, hdiutil checksum and git diff checks passed. DMG SHA256: `35c301b4baddd8f23648825e7b3c08422a5d4896bf45376a1cd4c7c6558967f5`.
- Real UI: Overview and Locations render. Keyboard folder selection opens the correct inspector. Shift-Down selects OpenEmu + Simulator data and both selection bar and inspector show 595.71 GiB, matching 331.27 + 264.44 GiB. Page Down changes the visible rows and retains that selection.
- Read-only API scan found no removeItem, unlink, rmdir, trashItem, truncate, shell rm or fixed cornerRadius use in Sources, Tests or build-version.sh.
- Two generated icon candidates and 64-pixel previews are retained in Assets/IconCandidates. Built-in imagegen prompts are in that directory's README. User choice is pending; checkpoint 11 retains the prior bundled icon.

## Still required before tagging v0.7.0

1. User icon choice and a new package using the selected asset, while retaining the old image.
2. Full interaction and scrolling validation. Native UI automation repeatedly reports noWindowsAvailable / missing frames on pointer actions. Keyboard selection and page navigation are verified; smooth scrolling is not yet established by these checks.
3. Two window sizes and both appearances on the final package, menu/context-menu/report/access checks, final six-suite run and final exact-build performance confirmation.
4. Final validation report, README, tag and remote verification. Do not mark the overarching goal complete before those gates.

No files were deleted. Existing builds, outputs, fixtures, artwork, scan records and legacy history remain preserved. Scheduled scanning remains off on this machine. App is ad-hoc signed only, not notarized, and no multi-day monitoring result is claimed.
