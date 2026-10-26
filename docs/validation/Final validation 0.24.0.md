# Final validation 0.24.0

Build 64. Chris needs Context Cleaner to keep finding more to delete as agents fill the disk, without anyone adding paths by hand. On this Mac, Everything else was 1.21 TiB. Looking inside it showed where: ~/Backups/kartpad 167 GiB, ~/Movies/Movies 75 GiB, three 10 GiB copies of Antigravity data in ~/.gemini, ~/models 28 GiB, the Android SDK 25 GiB and ~/.codex/work… folders 24 GiB.

## What changed

| Before | After |
|---|---|
| A big folder in Everything else could only be added by hand (File › Add Folder to Scan), then showed as one row | **Track** on any folder there adds it to Your folders and scans it at once. From then on, what sits untouched inside it shows in Free Up Space item by item, as Review first, never the whole folder. Every item in a folder that looks like backups is marked a backup and never auto-ticked |
| ~/.codex/work and work-… folders weren't scanned | Scanned like Codex scratch, item by item; a new work-… folder is found on its own |
| The Android SDK was one blob in Everything else | Each emulator system image and NDK version is a row. An image no emulator uses is Safe to remove; one an emulator uses is Not for the Trash, named for that emulator, and never suggested; an NDK is a download cache |
| Free Up Space was shorter for the first minutes after launch with no reason given | It says it's still asking git, and that Not in git folders join when it's done |

Track is offered only where every item inside could go in a Trash command (not ~/Library itself, iCloud, keys or the Trash), not where apps keep their own data (Application Support, Containers, Group Containers, Mail, Messages), and not on projects folders or git checkouts, which are already looked at project by project. Inside a tracked folder, an app's library (Photos, Music, iMovie, Final Cut) is never listed.

## Evidence

| Check | Result |
|---|---|
| New places measured live on this Mac, with the app's own discovery and rules | 41 folders, 43.1 GiB: Android 28, 29 and 34 images (9.9 GiB) and NDK 29 (3.1 GiB) Safe to remove; Android 35 and 36 images, used by 3 emulators, Not for the Trash; 22 GiB of Codex work folders Review first |
| First run of that check | Found the used images offered as Rebuildable; changed to Not for the Trash before release |
| Track on this Mac's Everything else places, installed app | First build offered it on ~/Library/Application Support and ~/Library/Containers too; fixed before release. Now on ~/Backups, ~/Movies, ~/Library/Caches, ~/ComfyUI-Shared, ~/.gemini, ~/Applications, ~/models; not on /Applications, ~/GitHub, Application Support or Containers |
| Compiler | No warnings, no errors |
| Test suites | 403 checks pass, 6 new |

