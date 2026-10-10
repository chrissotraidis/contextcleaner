# Goal loop 0.22

Feedback from Oct 10: under 2.3 GiB free on a 460 GiB disk. Context Cleaner offered 5.84 GiB and put 406 GiB under Everything else. About 155 GiB of that was one git-ignored `docs/artifacts` folder in a repository under ~/GitHub, written by a coding agent over five days: 1,600 run folders and 359,000 files, mostly APFS clones of each other. The app never measured it, and the drill-down, du and Finder reported 708 GiB for it and 729 GiB for ~/GitHub, more than the whole disk. The owner asked why the space disappeared and why the app missed it.

## Outcome

On a full disk, the biggest folders are named with the space removing them really frees, including git-ignored folders inside projects, and the app says plainly when it can't check something.

## Defects to fix

1. **Ignored folders inside repositories are never measured.** `Coverage.projectSuffixes` (Coverage.swift) limits a repository to build, generated, work and two Android paths, and the .projects/.workspaces case in Inventory.swift adds only those. A `docs/artifacts` folder (155 GiB), a `ref/` folder (12 GiB) and `build-macos` (4.9 GiB, ignored by a `build-*/` rule) all fell into Everything else. For each repository, ask git read-only through `gitOutput` for ignored directories (for example `ls-files --others --ignored --exclude-standard --directory`), keep the top-level ones, and measure each one of 500 MB or more as its own location. Known build names (build, build-*, out, dist, DerivedData, .build, target, node_modules) are Rebuildable. Any other ignored folder is Review first: "Git ignores it, so it's only on this Mac." Every existing safety rule stays; a whole repository is still offered only when it's backed up.

2. **APFS clones are counted once per copy.** `TreeMeasure.measure` (Inventory.swift) adds st_blocks for every file and dedupes only hard links by inode. Clones have their own inodes and each reports its full block count. Read each file's private size with getattrlist (`ATTR_CMNEXT_PRIVATESIZE` in forkattr, options `FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW`). Private bytes are what removing a single file frees at least; for a folder, add the shared remainder once per clone group for "frees about". Use these numbers on cards, in Free Up Space totals and in the Everything else drill-down, and never show a folder or a sum larger than the volume's used space. On the Mac above the reference script below measured 708.6 GiB by blocks, 140.6 GiB private and about 155 GiB real, which matches the disk's own accounting.

3. **Git fails silently when the Xcode license isn't accepted.** `developerToolsInstalled` (OverviewData.swift) runs only `xcode-select -p`, which succeeds whenever Xcode is installed. With the license unaccepted, every `/usr/bin/git` call exits 69, `runGit` returns nil, and every backup check quietly becomes unknown. Probe `/usr/bin/git --version` once. If it exits 69 and `/Library/Developer/CommandLineTools/usr/bin/git` exists, use that (it worked on the Mac above). If neither works, show one plain notice that project checks are off and how to turn them on: `sudo xcodebuild -license accept`. A blocked git must never look like an answer.

4. **Everything else hides fast growth.** The overview knew Everything else grew 9.49 GiB a day but not where. When Everything else is a large share of the disk or grows quickly, size the top-level folders of the home folder and of each repository under ~/GitHub, within the existing limits and clone-aware, and name the biggest and fastest-growing ones on the overview with a way to open them.

## Checks

1. A fixture repository in a temporary folder: a .gitignore with `docs/artifacts/` and `build-*/`, a 200 MB file in docs/artifacts with three `cp -c` clones in separate subfolders, and a `build-macos` folder. docs/artifacts shows as Review first at about 200 MB (not 800 MB); build-macos shows as Rebuildable.
2. No folder, total or drill-down row exceeds the volume's used space.
3. With git made to exit 69 through a test seam, the fallback git is used; with no working git, the notice appears.
4. Everything else names its biggest and fastest-growing folders.
5. Existing tests (Tests/ and test-preserving.sh) pass, the build has no warnings, and a validation record is written like earlier releases.
6. Release 0.22.0, build 56: update build-version.sh (Info.plist block, volume name, DMG name), CHANGELOG and README, commit and push main, build with `./build-version.sh <new empty folder>`, then `gh release create v0.22.0` with the DMG and SHA256SUMS.txt marked Latest, and confirm the published checksum matches. If the build Mac runs out of space, stop and say so; never delete anything on it to make room.

## Reference: real size of a folder with clones

```python
import ctypes, os, struct, sys
libc = ctypes.CDLL("libc.dylib")
class attrlist(ctypes.Structure):
    _fields_ = [("bitmapcount", ctypes.c_ushort), ("reserved", ctypes.c_uint16), ("commonattr", ctypes.c_uint32),
                ("volattr", ctypes.c_uint32), ("dirattr", ctypes.c_uint32), ("fileattr", ctypes.c_uint32), ("forkattr", ctypes.c_uint32)]
# ATTR_CMN_RETURNED_ATTRS + ATTR_CMNEXT_PRIVATESIZE; options FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED (0x21)
request = attrlist(5, 0, 0x80000000, 0, 0, 0, 0x8); buffer = ctypes.create_string_buffer(64)
blocks = private = 0; shared = {}
for folder, _, names in os.walk(sys.argv[1]):
    for name in names:
        path = os.path.join(folder, name); st = os.lstat(path)
        if not os.path.isfile(path) or os.path.islink(path): continue
        allocated = st.st_blocks * 512; blocks += allocated
        ok = libc.getattrlist(path.encode(), ctypes.byref(request), buffer, 64, 0x21) == 0
        own = min(struct.unpack_from("<q", buffer.raw, 24)[0], allocated) if ok else allocated
        private += own
        if allocated > own:  # shared with a clone: count it once per name and size
            key = (name, st.st_size); shared[key] = max(shared.get(key, 0), allocated - own)
gib = 1 << 30
print(f"by blocks {blocks/gib:.1f} GiB, private {private/gib:.1f} GiB, real about {(private + sum(shared.values()))/gib:.1f} GiB")
```
