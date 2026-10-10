# Final validation 0.22.0

Build 56. The four defects in [GOAL_LOOP_0.22.md](../GOAL_LOOP_0.22.md): on a 460 GiB Mac with under 2.3 GiB free, a 155 GiB git-ignored `docs/artifacts` folder was never measured, clones made folders look bigger than the disk, a blocked git looked like an answer, and Everything else didn't say where it grew.

## What changed

| Before | After |
|---|---|
| A repository was measured only at build, generated, work and two Android paths | Discovery also asks git (`ls-files --others --ignored --exclude-standard --directory`, read-only) for ignored folders, confirms each with `check-ignore` (`--directory` also lists a folder like `docs/` that merely holds ignored ones), keeps the outermost, and adds those of 500 MB or more. The size test stops as soon as 500 MB is reached |
| Only build, generated, intermediates and .cxx counted as build output by name | Inside a project, also build-*, build_*, cmake-build*, out, dist, target, node_modules, .build and DerivedData, unless the name says backup, save or private. Any other ignored folder is Review first, "Not in git" |
| Each file counted its full block count, so APFS clones counted once per copy | The scan reads each file's private size and clone family with the same batched read (ATTR_CMNEXT_PRIVATESIZE and CLONEID). Shared space counts once per clone family or file name and size. Volumes that don't know these attributes fall back to the old read |
| A folder or the disk map could exceed the disk | Each folder is capped at the volume's used space, the disk map scales its parts if their sum passes it, and "You can get back" and the Everything else drill-down are capped too |
| `developerToolsInstalled` only ran `xcode-select -p`; with Xcode's license unaccepted every git call exited 69 and returned nothing | Git is probed once with `--version`. On exit 69 the Command Line Tools' git is tried. If none works, the overview says project checks are off and copies `sudo xcodebuild -license accept` |
| Everything else grew without saying where; Look Inside saved nothing | Look Inside lists each project in ~/GitHub on its own and saves paths and sizes. It runs on its own when Everything else is a quarter of used space or grows 2 GiB a day, at most every six hours. The overview names the biggest place and the one that grew most since an earlier look |

## Evidence

| Check | Result |
|---|---|
| Goal check 1: fixture repository | A .gitignore with `docs/artifacts/` and `build-*/`, a 200 MB file in docs/artifacts with three clones in separate folders, and a build-macos holding three more. Discovery finds both and leaves out a small ignored folder. docs/artifacts measures 200 MiB, not 800, and is Review first, "Not in git"; build-macos measures 200 MiB and is Rebuildable |
| Goal check 2: never bigger than the disk | Folder sizes capped at the volume's used space in the scan; disk map, headline and drill-down capped in the views |
| Goal check 3: blocked git | Fixture gits that exit 69: the next working one is used and the block is recorded; with none working, git is blocked (the notice's condition); a missing git isn't a block |
| Goal check 4: Everything else | Two saved looks: the repository that grew 150 GiB is named biggest and fastest-growing, ~/GitHub itself isn't (its parts are), and one look alone names no growth |
| Clone reading on this Mac | A 50 MB file and four `cp -c` clones read through getattrlistbulk: clones share one clone ID with private size 0; a modified clone has its own ID and 16 KiB private |
| This Mac's ~/GitHub | 45 big ignored folders found across the repositories, 758 GiB that was Everything else: for example a 252 GiB and a 29.6 GiB `ref/` (Review first, Not in git) and build-ios* folders (Rebuildable, or Safe when their project is finished). A `build-ios-preview1-backup` was first called Rebuildable; names that say backup now stay Review first |
| Compiler | No warnings, no errors |
| Test suites | 378 checks pass, 6 new |

Not checked here: a Mac whose git is actually blocked (this Mac's git works), and a non-APFS volume, where the fallback read is taken.
