# Goal loop 0.15: know where you are, trust every number

Trigger (Sep 30), from Chris's walkthrough:

- In a folder card he couldn't tell which folder he was looking at.
- Drilling into "What's inside" had no way back.
- A subfolder scan showed 1,020 KiB under its parent's name. It was really `intermediates/project_dex_archive`, but the classifier named children after their parent.
- The move-to-Trash command needs to be correct and offered on every card.
- Folders should sort by size by default.
- "Keep" and "Ignored" mean different things in different places.
- "Where the space went" should also show how fast.
- The Overview scrolls too much, the charts could be clearer, and "Everything else" (1.89 TiB) is unexplained.

## Rule that overrides everything

Context Cleaner never deletes, moves, trashes, empties, prunes or resets anything. It reads metadata and git state, and it only copies commands for the user to run. Tests use fixtures only. Any command it offers is checked for syntax without being run.

## Goals

1. **Names that match the folder.** A subfolder of a recognized folder is named for itself ("project_dex_archive in Android build intermediates"). Project names use the folder's own worktree or repository folder, so "GitHub/kartpad-release-source" is never labeled "kartpad-source-migration".
2. **Know where you are.** Every folder card shows its full path (with ~), with a link up to its parent folder.
3. **Go back.** A Back and Forward pair in the toolbar (⌘[ and ⌘]) returns to the previous view, filter and folder, including after opening a folder from the Overview or drilling inside.
4. **One correct trash command, everywhere.** "Copy Move-to-Trash Command" is on every card, for the folder and for its old items. It moves items to the Trash through Finder, so Put Back works and same-named folders don't collide. It's quoted for any path, and the tests syntax-check it without running it.
5. **Biggest first by default**, with "Biggest unused first" still one click away.
6. **One vocabulary.**
   - The user's choice is **Ignore**: an Ignore button, "Ignored" as the status, and the Ignored view.
   - The app's answer for app libraries is **Leave it**: manage it inside its app.
   - "Keep" and "Never suggested" are gone.
7. **How fast.** "Where the space went" shows each place's change and its rate per day, plus a headline rate.
8. **Less scrolling.**
   - The chart uses a fixed height and drops the duplicate "Grew most" chips.
   - The disk map legend is one compact block.
   - Panel rows are one line.
   - The Overview fits a normal window with little or no scrolling.
9. **Clearer charts.**
   - The Overview chart shows free space directly, falling toward zero as the disk fills.
   - A folder's size chart shows its readings without stray isolated dots.
10. **Explain Everything else.** Say what it is (macOS, apps, Photos, Mail and folders outside the covered places). Offer a read-only **Look inside** that sizes the top-level folders of your home, Library and Applications, leaving out places already scanned. The results are shown and never mixed into the answers.
11. **Quality gates.**
    - Clean compile with no warnings, all preserving suites plus new tests, and scan updates within 10 ms.
    - A native UI check in dark and light.
    - README and screenshots updated, a validation record, a signed DMG, a GitHub release, and remote parity.
    - The SpaceCheck history hash stays unchanged.
