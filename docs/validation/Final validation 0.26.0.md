# Final validation 0.26.0 and Windows 0.1.2

Mac build 68. Chris ticked four Safe to remove rows (three simulators and an install cache) and the command covered one. He has also lost original game files more than once by removing a project's `ref` folder (for example `deviltouch/ref`, which holds Diablo's data), because the app called it Review first, "Not in git", and Free Up Space listed it once untouched.

## Found

| Problem | Fix |
|---|---|
| A project's `ref` folder was Review first and Free Up Space offered it once untouched; 0.25.1's own validation found `meleepad/ref` disc images at the top of Oldest first | `ref`, `refs`, `reference(s)`, `original(s)` inside a project (`~/GitHub`, `~/Developer`, Codex worktrees and task folders), and anything inside them, are Not for the Trash: "Needed to build <project>". Free Up Space never lists them or items inside them, and a copied command leaves out them and any project folder holding one |
| Ticked simulators were left out of a multi-folder command as places "you remove in their own apps" | The command removes each simulator Xcode lists with `xcrun simctl delete <ID>`, after the folders, with a line for each |
| A column-header sort read "Sort: Custom"; Size sorted smallest first read "Biggest first"; ties came out in no particular order | Every header order has a name in both directions; ties go biggest first |

## Evidence

| Check | Result |
|---|---|
| Mac test suites | 424 checks pass, 6 new: which folders count as a ref folder and which don't (a project named ref, git's refs, caches outside projects), a 3-month-old ref folder is Not for the Trash, a project's old items never include its ref folder, simulator IDs in the command, and a command with only simulators or both is valid bash and zsh. The 0.23 test that expected a ref folder in Free Up Space now uses another ignored folder and checks ref stays out |
| Mac compiler | No warnings, no errors |
| This Mac, build 68 | `deviltouch/ref` (1.27 GiB, 4 months) reads Not for the Trash · Needed to build deviltouch. Ticked with an install cache: "One command for 1 folder… Leaves out 1 ref folder". Ticking iPhone 18 Pro Max and iPhone Air (never started) gave "One command for 2 test devices"; the copied command named both IDs Xcode lists and passed `bash -n`. It was not run. Free Up Space at 3 months, any size: 8 items, no ref folder |
| Sort labels | Code only: the table's headers aren't exposed to accessibility, so clicking one wasn't exercised |
| Windows, Windows PowerShell 5.1 in the Parallels VM | The 3 new ref checks pass on their own (Not for the Recycle Bin; a ref folder, what's inside it and the project holding it are recognized, a plain folder and the projects folder aren't; a move leaves a ref folder out). The full suite ran 96 checks with 1 failure, never moves Documents, the same known failure as 0.25.1: the VM runs tests as SYSTEM, whose profile has no Documents folder. That full run used the test file from before the ref checks were moved out of the git-only block, and the VM has no git on SYSTEM's path |
| Windows window | Run with -MTA, so the XAML check was skipped (the window is unchanged). Not opened on a desktop, and not run on PowerShell 7 |
