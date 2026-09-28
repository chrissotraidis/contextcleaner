# Context Cleaner — visual refresh checkpoint 0.4.0

2026-09-28, Asia/Tokyo. The approved goal remains active. Nothing is deleted, moved to Trash, pruned or reset. Old source trees, builds, stages, icon variants, imported history and fixtures remain intact.

## Screenshot-led audit and implementation

1. **Overview — refreshed and exercised.** The supplied 09:53 screenshot showed an Overview-like table with no volume denominator and repeated activity-unknown labels. The new dedicated Overview shows home-volume total/used/free, a storage ring, refresh timestamp, and a selectable recorded free-space chart. Category and largest-location cards open real table selections; search from Overview opens matching locations. A zero Growing count is accompanied by the number of comparable baselines, rather than implying every location has been tracked.
2. **Folder selection — refreshed and exercised.** In the supplied 09:54 screenshot the work folder evidence consisted of long paths and prose. The default inspector now shows project/tool, a folder size chart, purpose, removal consequences and links to deeper contents/evidence. Full-sized table columns, category symbols and the selected workspace name provide context. A single observation is explicitly a baseline, not fabricated history. Some older imported records still need a fresh scan for contents and process details.
3. **Evidence — refreshed and exercised.** Observed/inferred/unknown badges remain explicit; source explanations and exact folder paths expand on demand. The npm evidence disclosure was exercised in the actual packaged app. Open handles do not prove writes, and missing activity evidence is not proof of inactivity.
4. **Simulators — working metadata navigation and targeted scan.** The simulator overview explains virtual test devices and their potentially unique app data. The Contents tab identifies named devices and runtimes without traversing their payloads, offers device search, and lets the user measure a chosen device. There were 59 device directories at inspection time. The real BallPad iPad Local 20260916 measurement recorded 4,273,709,056 allocated bytes (3.98 GiB), 16,773 files, iOS-26-5, and 2.877 seconds of traversal after the activity check. This does not establish that the device is unused or safe to remove.
5. **Appearance and identity — bundled and visually checked.** The app includes a macOS icon in Info.plist/Resources and visible dashboard identity. System/light/dark appearance is selectable without changing global macOS settings. Light accents were deepened after visual inspection; selected-row text/icons use a contrasting color. Broad keyboard/VoiceOver compliance is still an open validation task.

The user-provided screenshots are the before-reference; actual native CUA screenshots and accessibility observations in this chat supply the implementation verification. This is a native application, not a hosted web prototype.

## Validation

- 28 current core checks passed: preservation, append-only history/preferences, legacy migration, exclusions, symlinks, cancellation, growth scope and classification.
- 22 current detail checks passed: real additive growth, content summaries, uncertain child events, app/container identity, inherited device identity, excluded metadata and byte preservation.
- 9 overview checks passed: overlapping paths, duplicate records, failed/unknown measurements, exclusions, zero values, deterministic grouping and used/free/total reconciliation. These made no filesystem mutations.
- A real selected simulator scan completed through the UI and appended a sixth scan; the app reopened with that record intact.
- Legacy SpaceCheck history SHA256 stayed `e43403193af9a93b1152d01fc231b2aa6172e30e875d9ec956fea542f8124be4`.
- Versioned DMGs use checksum verification and strict local code-signature verification. Checkpoint 03 is a preserved failed compile (custom Color type inference); checkpoint 04 corrected it. Checkpoint 05 adds selected-row contrast, compact tabs and baseline coverage wording.

## Limits and next goal work

Historical folder sizes were collected at different times. Category totals are saved metadata estimates with parent/child overlap removed, not a scan of the entire drive or guaranteed reclaimable bytes. Volume capacity is measured separately. Charts show actual observations; line segments do not prove events between them. Attribution remains observed metadata, structural inference or explicitly unknown.

Most large locations currently have a single imported observation. Repeated targeted scans, with stable scope, are required for useful growth history. Daily checks run only while the app is open; no multi-day reliability claim is made from these tests. No always-running writer monitor has been installed, and no historical process attribution is invented.

Remaining: resource limits on exceptionally large directories, broader keyboard/VoiceOver and small-window checks, richer drilldown/search of very large child lists, multi-day scheduling evidence, and release signing/notarization for other users. Appearance choice currently lasts for the app session. The new checkpoint is useful for local review; the full goal is not complete.

## Artifacts

Current source: `../Context Cleaner 0.4.0-source/`.
Deliverable: `../Context Cleaner 0.4.0-checkpoint-05/Context-Cleaner-0.4.0.dmg`.
Artwork: `../Context Cleaner 0.4.0-source/Assets/ContextCleaner.png`.
The artwork reuses the built-in ImageGen concept already generated in this task: a navy rounded-square macOS icon with a teal folder, rising measurement dots and a magnifying glass, no text. No new ImageGen prompt or replacement generation was needed for this refresh; sips/iconutil produced bundled size variants while preserving the original.

Core fixture: `work/context-cleaner-0.4.0-core-fixtures/F14609BB-3733-4888-AF29-CD1DAAC484D7`.
Latest detail fixture: `work/context-cleaner-0.4.0-detail-fixtures/F918D82C-4724-4850-B763-59646AFE6287`.
