import Foundation
@main struct OverviewTests {
    static func main() {
        var count = 0
        func check(_ test: Bool, _ description: String) { precondition(test, description); count += 1; print("PASS " + description) }
        func item(_ path: String, _ category: FolderCategory, _ bytes: Int64?, _ state: MeasurementState = .measured) -> FolderMeasurement {
            var p = Classifier.profile(path: path, home: "/fixture", readMetadata: false); p.category = category
            return FolderMeasurement(profile: p, observedAt: Date(), state: state, allocatedBytes: bytes, fileCount: 0, processes: [], activityCheckAvailable: false, elapsedSeconds: 0)
        }
        let a = item("/fixture/work", .workspace, 100), child = item("/fixture/work/build", .buildOutput, 90), cache = item("/fixture/cache", .packageCache, 25)
        let input = [child, cache, a, item("/fixture/failed", .appData, 500, .failed), item("/fixture/unknown", .unknown, nil)]
        let groups = overviewGroups(input, preferences: Preferences())
        check(groups.reduce(0) { $0 + $1.bytes } == 125, "overview excludes nested, failed and unknown-size totals")
        check(groups.first?.category == .workspace && groups.first?.bytes == 100, "outer folder retains category and complete size")
        check(overviewGroups(input.reversed(), preferences: Preferences()).map(\.id) == groups.map(\.id), "aggregation ordering does not depend on input order")
        var prefs = Preferences(); prefs.locations["/fixture/work"] = LocationPolicy(excluded: true)
        check(overviewGroups(input, preferences: prefs).reduce(0) { $0 + $1.bytes } == 25, "excluded parents and descendants do not leak into dashboard")
        check(overviewGroups([a,a], preferences: Preferences()).first?.count == 1, "duplicate measurements cannot inflate location count")
        check(overviewGroups([item("/fixture/a", .buildOutput, 0)], preferences: Preferences()).first?.bytes == 0, "measured empty location remains a real zero")
        check(overviewGroups([a,item("/fixture/work2", .workspace, 30)], preferences: Preferences()).first?.bytes == 130, "similar path prefix is not mistaken for a child")
        check(overviewGroups([], preferences: Preferences()).isEmpty, "no data produces no fabricated category")
        if let volume = VolumeSnapshot.read() { check(volume.total > 0 && volume.free >= 0 && volume.used + volume.free == volume.total, "read-only capacity snapshot reconciles used free and total") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_790_582_400)
        let start = calendar.startOfDay(for: morning)
        check(UsageRange.week.window(endingAt: start.addingTimeInterval(60), calendar: calendar) == UsageRange.week.window(endingAt: start.addingTimeInterval(40_000), calendar: calendar), "redraws within a calendar day keep the 7-day axis fixed")
        let week = UsageRange.week.window(endingAt: start, calendar: calendar)
        check(week.upperBound.timeIntervalSince(week.lowerBound) == 7 * 86400 && week.upperBound == start.addingTimeInterval(86400), "7-day range is seven whole days ending tonight")
        let month = UsageRange.month.window(endingAt: start, calendar: calendar)
        check(month.upperBound.timeIntervalSince(month.lowerBound) == 30 * 86400, "30-day range covers thirty whole days")
        let day = UsageRange.day.window(endingAt: start.addingTimeInterval(3700), calendar: calendar)
        check(day.upperBound == start.addingTimeInterval(7200) && day.lowerBound == start.addingTimeInterval(7200 - 86400), "24-hour range ends at the next whole hour")
        check(UsageRange.day.window(endingAt: start.addingTimeInterval(3601), calendar: calendar) == day, "24-hour axis is stable within an hour")
        let gib: Int64 = 1_073_741_824
        func reading(_ id: String, _ seconds: TimeInterval, used: Int64, total: Int64 = 4000) -> UsageReading {
            UsageReading(id: id, date: start.addingTimeInterval(seconds), used: used * gib, total: total * gib, isCurrent: false)
        }
        let fullAxis = usageAxis([reading("a", 0, used: 3380, total: 3720), reading("b", 60, used: 3530, total: 3720)])
        check(fullAxis.upperBound == 3720 && fullAxis.lowerBound < 3380 && fullAxis.lowerBound > 0, "a nearly full disk zooms the axis but still shows the capacity ceiling")
        check(usageAxis([reading("a", 0, used: 1000), reading("b", 60, used: 1200)]).lowerBound == 0, "a half-empty disk starts the axis at zero")
        check(usageAxis([]) == 0...1, "no readings produce a neutral axis")
        func record(_ id: String, _ measurements: [FolderMeasurement]) -> ScanRecord {
            ScanRecord(id: id, startedAt: start, finishedAt: start, scope: "fixture", complete: true, measurements: measurements, discoveryNotes: [])
        }
        let before = record("before", [a, child, cache])
        let after = record("after", [item("/fixture/work", .workspace, 150), item("/fixture/work/build", .buildOutput, 140), item("/fixture/cache", .packageCache, 10)])
        let changes = scanDelta(after, previous: before)!
        check(changes.grew.count == 1 && changes.grew.reduce(0) { $0 + $1.delta } == 50, "history growth totals count comparable nested folders once")
        check(changes.shrank.count == 1 && changes.shrank[0].delta == -15, "independent shrinkage remains visible alongside growth")
        let failedParent = record("partial", [item("/fixture/work", .workspace, nil, .failed), item("/fixture/work/build", .buildOutput, 120)])
        check(scanDelta(failedParent, previous: before)?.grew.first?.delta == 30, "an incomparable parent cannot hide a comparable child change")
        check(scanDelta(record("missing", [item("/fixture/other", .workspace, 200)]), previous: before) == nil, "disjoint scan coverage does not claim zero growth")
        var sampleA = before; sampleA.freeBytes = 250*gib; sampleA.finishedAt = start
        var sampleB = after; sampleB.freeBytes = 220*gib; sampleB.finishedAt = start.addingTimeInterval(3600)
        let live = VolumeSnapshot(date: start.addingTimeInterval(7200), total: 4000*gib, free: 125*gib)
        let hourly = [CapacityReading(date: start.addingTimeInterval(1800), total: 4000*gib, free: 240*gib)]
        let usage = usageReadings(records: [sampleB, sampleA], capacity: hourly, current: live)
        check(usage.map(\.used) == [3750*gib, 3760*gib, 3780*gib, 3875*gib] && usage.last!.isCurrent, "used space combines scans, hourly readings and the live reading in time order")
        check(usageReadings(records: [sampleA], capacity: [CapacityReading(date: live.date, total: 4000*gib, free: 1*gib)], current: live).last!.used == live.used, "the live reading wins over a duplicate timestamp")
        check(usageReadings(records: [], capacity: [], current: nil).isEmpty, "empty history never invents a reading")
        let spaced = [reading("a", 0, used: 10), reading("b", 3600, used: 11), reading("c", 36000, used: 12), reading("d", -90000, used: 9)]
        let series = usageSeries(spaced.sorted { $0.date < $1.date }, in: start...start.addingTimeInterval(86400), gapLimit: UsageRange.day.gapLimit)
        check(series.map(\.segment) == [0, 0, 1], "a gap longer than the range limit breaks the line; readings outside the window are left out")
        check(usageChange(usage, from: start, to: live.date)?.delta == 125*gib, "a span reports used space gained between its first and last readings")
        check(usageChange([reading("a", 0, used: 1)], from: start, to: live.date) == nil, "one reading cannot describe a change")
        let hourReadings = [reading("h0", 0, used: 100), reading("h0b", 1800, used: 110), reading("h1", 5400, used: 130), reading("h3", 12600, used: 150)]
        let buckets = usageBuckets(hourReadings, window: start...start.addingTimeInterval(4*3600), component: .hour, calendar: calendar)
        check(buckets.map { $0.delta.map { $0 / gib } } == [10, 20, nil, nil], "per-hour change uses the previous reading only when it is recent; empty hours stay empty")
        func itemAt(_ path: String, _ bytes: Int64, _ seconds: TimeInterval) -> FolderMeasurement {
            var m = item(path, path.hasSuffix("build") ? .buildOutput : .workspace, bytes); m.observedAt = start.addingTimeInterval(seconds); return m
        }
        let early = record("early", [itemAt("/fixture/work", 100, 0), itemAt("/fixture/work/build", 90, 0), itemAt("/fixture/cache", 25, 0)])
        let late = record("late", [itemAt("/fixture/work", 150, 3600), itemAt("/fixture/work/build", 140, 3600), itemAt("/fixture/cache", 10, 3600)])
        let names = Dictionary((early.measurements + late.measurements).map { ($0.profile.path, $0.profile) }, uniquingKeysWith: { a, _ in a })
        let grew = folderGrowth(history: historyIndex([early, late]), profile: { names[$0] }, from: start.addingTimeInterval(-60), to: start.addingTimeInterval(7200))
        check(grew.map(\.path) == ["/fixture/work"] && grew.first?.delta == 50, "what grew lists growing folders once, under their outermost parent, and omits shrinking ones")
        let stale = record("stale", [itemAt("/fixture/work", 100, -3 * 86400)])
        check(folderGrowth(history: historyIndex([stale, late]), profile: { names[$0] }, from: start, to: start.addingTimeInterval(7200)).isEmpty, "a baseline from days before the span is not treated as growth inside it")
        let sparkPoints = [10, 20].map { HistoryPoint(recordID: "r\($0)", path: "/p", date: start.addingTimeInterval(Double($0)), bytes: Int64($0), state: .measured, scopeID: "s") }
            + [HistoryPoint(recordID: "fail", path: "/p", date: start.addingTimeInterval(25), bytes: nil, state: .failed, scopeID: "s")]
            + [30, 40].map { HistoryPoint(recordID: "r\($0)", path: "/p", date: start.addingTimeInterval(Double($0)), bytes: Int64($0), state: .measured, scopeID: "s") }
            + [HistoryPoint(recordID: "stop", path: "/p", date: start.addingTimeInterval(50), bytes: nil, state: .cancelled, scopeID: "s")]
        check(sparklineValues(sparkPoints) == [30, 40], "sparklines show the latest comparable run and ignore stopped scans")
        var outcome = record("outcome", [cache, a, child, item("/fixture/locked", .appData, nil, .inaccessible)])
        check(scanOutcome(outcome, grew: 2) == "Scanned 3 folders · 2 grew · 1 couldn't be read", "scan result names folders scanned, grown and unreadable")
        outcome.complete = false; outcome.requestedCount = 9
        check(scanOutcome(outcome, grew: 0) == "Stopped after 3 of 9 folders", "a stopped scan says how far it got")
        var blocked = record("blocked", [item("/fixture/locked", .appData, nil, .inaccessible)]); blocked.complete = false; blocked.requestedCount = 1
        check(scanOutcome(blocked, grew: 0) == "1 folder couldn't be read" && blocked.resultSummary == "1 folder couldn't be read", "an unreadable folder is reported as unreadable, not as a stopped scan")
        var stoppedOne = record("stopped-one", [item("/fixture/a", .appData, nil, .cancelled)]); stoppedOne.complete = false; stoppedOne.requestedCount = 1
        check(scanOutcome(stoppedOne, grew: 0) == "Stopped after 0 of 1 folder", "a stopped one-folder scan uses the singular")
        let withGone = record("with-gone", [cache, item("/fixture/deleted", .appData, nil, .missing)])
        check(scanOutcome(withGone, grew: 0) == "Scanned 1 folder · 1 no longer on disk" && withGone.resultSummary == "1 folder scanned · 1 no longer on disk", "folders you deleted are reported plainly, never as problems")
        // Can I remove it?
        let now = start.addingTimeInterval(100 * 86400)
        func folder(_ path: String, _ category: FolderCategory, lastChanged daysAgo: Double?, project: String? = nil) -> FolderMeasurement {
            var m = item(path, category, 10 * gib); m.latestModifiedAt = daysAgo.map { now.addingTimeInterval(-$0 * 86400) }
            m.profile.project = project; return m
        }
        let staleBuild = advice(for: folder("/fixture/kartpad/build", .workspace, lastChanged: 20, project: "kartpad"), policy: LocationPolicy(), devices: [:], now: now)
        // Git evidence: an active project is never called safe; a finished worktree offers git's own removal.
        let activeProject = ProjectActivity(root: "/fixture/kartpad", isWorktree: false, mainRepository: nil, registered: nil, branch: "codex/x", defaultBranch: "main", lastCommit: now.addingTimeInterval(-86400), merged: false, uncommitted: 3)
        let activeAdvice = advice(for: folder("/fixture/kartpad/build", .workspace, lastChanged: 20, project: "kartpad"), policy: LocationPolicy(), devices: [:], project: activeProject, now: now)
        check(activeAdvice.verdict == .rebuild && activeAdvice.reason.contains("still working on") && activeAdvice.evidence.first?.contains("3 uncommitted changes") == true && activeAdvice.lastUsed == activeProject.lastCommit,
              "build output of an active project is rebuildable, with the git evidence; uncommitted work lives in tracked files")
        let busyBuild = advice(for: folder("/fixture/kartpad/app/build", .buildOutput, lastChanged: 1, project: "kartpad"), policy: LocationPolicy(), devices: [:], project: activeProject, now: now)
        check(busyBuild.verdict == .rebuild && busyBuild.howTo.contains("between builds") && busyBuild.short == "Used yesterday",
              "busy build output says to remove it between builds, with a short reason")
        var trackedProject = activeProject; trackedProject.ignored = ["/fixture/kartpad/build": false]
        let tracked = advice(for: folder("/fixture/kartpad/build", .workspace, lastChanged: 20, project: "kartpad"), policy: LocationPolicy(), devices: [:], project: trackedProject, now: now)
        check(tracked.verdict == .check && tracked.evidence.contains("Git tracks this folder."), "a build folder git tracks may be source, so it's your call")
        var ignoredProject = activeProject; ignoredProject.ignored = ["/fixture/kartpad/build": true]
        let ignoredBuild = advice(for: folder("/fixture/kartpad/build", .workspace, lastChanged: 1, project: "kartpad"), policy: LocationPolicy(), devices: [:], project: ignoredProject, now: now)
        check(ignoredBuild.verdict == .rebuild && ignoredBuild.evidence.contains { $0.contains("Git ignores this folder") }, "git-ignored build output says so as evidence")
        var experiments = folder("/fixture/wt/kartpad-x/build", .workspace, lastChanged: 0.5, project: "kartpad")
        experiments.contents = FolderContents(children: [
            ChildSummary(name: "evening-20260921", directory: true, identity: "1", bytes: 30 * gib, files: 10, modifiedAt: now.addingTimeInterval(-8 * 86400)),
            ChildSummary(name: "ios89", directory: true, identity: "2", bytes: 6 * gib, files: 10, modifiedAt: now.addingTimeInterval(-86400))],
            fileTypes: [], listedChildren: 2, retainedLimit: 512, omittedEntries: 0)
        let experimentAdvice = advice(for: experiments, policy: LocationPolicy(), devices: [:], project: activeProject, now: now)
        check(experimentAdvice.verdict == .rebuild && experimentAdvice.staleItems.map(\.name) == ["evening-20260921"] && experimentAdvice.staleDays == 7 && experimentAdvice.short == "30 GiB old inside",
              "a project build folder lists experiment builds untouched for a week, and leaves this week's alone")
        let finishedWorktree = ProjectActivity(root: "/fixture/wt/kartpad-diag", isWorktree: true, mainRepository: "/fixture/kartpad", registered: true, branch: "codex/diag", defaultBranch: "main", lastCommit: now.addingTimeInterval(-20 * 86400), merged: true, uncommitted: 0)
        let finishedAdvice = advice(for: folder("/fixture/wt/kartpad-diag/work", .workspace, lastChanged: 20, project: "kartpad"), policy: LocationPolicy(), devices: [:], project: finishedWorktree, now: now)
        check(finishedAdvice.reason.contains("looks finished") && finishedAdvice.command == "git -C '/fixture/kartpad' worktree remove '/fixture/wt/kartpad-diag'" && finishedAdvice.evidence.first?.contains("merged into main") == true,
              "a finished worktree says so and offers git's own removal, which refuses uncommitted work")
        check(finishedWorktree.summary(now: now) == "Last commit 2 weeks ago on codex/diag · merged into main · nothing uncommitted", "git evidence reads as one plain sentence")
        var keepPolicy = LocationPolicy(); keepPolicy.isKept = true
        let pvm = Classifier.profile(path: "/Users/x/Parallels/Windows 11.pvm", home: "/Users/x", readMetadata: false)
        let dockerDisk = Classifier.profile(path: "/Users/x/Library/Containers/com.docker.docker/Data/vms", home: "/Users/x", readMetadata: false)
        check(pvm.category == .virtualMachine && pvm.name == "Windows 11 virtual machine" && dockerDisk.category == .virtualMachine && dockerDisk.associatedApp == "Docker Desktop", "virtual machines and Docker's disk are recognized")
        var dockerItem = item(dockerDisk.path, .virtualMachine, 40 * gib); dockerItem.profile = dockerDisk
        let dockerAdvice = advice(for: dockerItem, policy: LocationPolicy(), devices: [:], now: now)
        check(dockerAdvice.verdict == .check && dockerAdvice.command == "docker system df", "a virtual machine is never called safe, and Docker's advice starts with seeing what's reclaimable")
        check(advice(for: folder("/fixture/.npm/_cacache", .packageCache, lastChanged: 50), policy: keepPolicy, devices: [:], now: now).verdict == .keep, "your Keep wins over every rule")
        check(staleBuild.verdict == .safe && staleBuild.reason.contains("kartpad") && staleBuild.reason.contains("2 weeks ago"), "build output idle for weeks is safe and says which project and when")
        check(advice(for: folder("/fixture/kartpad/build", .workspace, lastChanged: 0.2, project: "kartpad"), policy: LocationPolicy(), devices: [:], now: now).verdict == .rebuild, "build output changed today is rebuildable")
        check(advice(for: folder("/fixture/kartpad/build", .workspace, lastChanged: nil, project: "kartpad"), policy: LocationPolicy(), devices: [:], now: now).verdict == .rebuild, "unknown last use is never called safe")
        check(advice(for: folder("/fixture/kartpad/work", .workspace, lastChanged: 90), policy: LocationPolicy(), devices: [:], now: now).verdict == .check, "work folders may hold hand-made inputs")
        let npm = advice(for: folder("/fixture/.npm/_cacache", .packageCache, lastChanged: 10), policy: LocationPolicy(), devices: [:], now: now)
        check(npm.verdict == .safe && npm.command == "npm cache clean --force" && npm.short == "Unused for 10 days", "an idle package cache is safe and offers the tool's own clean command")
        let freshCache = advice(for: folder("/fixture/.gradle/caches", .packageCache, lastChanged: 0.2), policy: LocationPolicy(), devices: [:], now: now)
        check(freshCache.verdict == .rebuild && freshCache.short == "Used 4 hours ago" && freshCache.reason.contains("next run is slower"), "a cache a tool used today is rebuildable, never safe")
        var derived = folder("/fixture/Library/Developer/Xcode/DerivedData", .buildOutput, lastChanged: 0.1)
        derived.contents = FolderContents(children: [
            ChildSummary(name: "OldGame-abc", directory: true, identity: "1", bytes: 3 * gib, files: 10, modifiedAt: now.addingTimeInterval(-60 * 86400)),
            ChildSummary(name: "Current-def", directory: true, identity: "2", bytes: 5 * gib, files: 10, modifiedAt: now),
            ChildSummary(name: "Tiny-ghi", directory: true, identity: "3", bytes: 1_000, files: 1, modifiedAt: now.addingTimeInterval(-90 * 86400))],
            fileTypes: [], listedChildren: 3, retainedLimit: 512, omittedEntries: 0)
        let derivedAdvice = advice(for: derived, policy: LocationPolicy(), devices: [:], now: now)
        check(derivedAdvice.verdict == .rebuild && derivedAdvice.staleItems.map(\.name) == ["OldGame-abc"] && derivedAdvice.staleBytes == 3 * gib && derivedAdvice.staleDays == 30 && derivedAdvice.short == "3 GiB old inside",
              "a busy cache points at the old items inside it, ignoring tiny ones")
        let command = trashCommand(["/a/it's \"here\"", "/b\\c"])
        check(command.hasPrefix("( ") && command.hasSuffix(" )") && !command.contains("\n") && command.contains(#"for p in '/a/it'\''s "here"' '/b\c'; do"#),
              "the Trash command is one line in a subshell, with each path quoted once for the shell")
        check(command.contains("/usr/bin/trash \"$p\"") && command.contains("with timeout of 300 seconds") && command.contains("(item 1 of a)") && command.contains("Already gone: ") && command.contains("NOT moved: ") && command.contains(" of 2 items to the Trash."),
              "it uses macOS's trash tool, falls back to Finder with five minutes per item, prints a line per item, and counts them at the end")
        let many = trashCommand((0..<400).map { "/fixture/item \($0)" })
        check(many.contains("/fixture/item 399") && many.contains(" of 400 items"), "any number of items fits in one command")
        check(trashTargets(["/a/.android/avd/K.avd", "/b/x"], exists: { $0 == "/a/.android/avd/K.ini" }) == ["/a/.android/avd/K.avd", "/a/.android/avd/K.ini", "/b/x"],
              "an Android emulator goes with its .ini file, so Android Studio isn't left pointing at nothing")
        check(looksIrreplaceable("device-backups") && looksIrreplaceable("iphone-ballpad-backup-20260929") && looksIrreplaceable("phone-test-private.SU67mk") && looksIrreplaceable("SaveData")
              && !looksIrreplaceable("intermediates") && !looksIrreplaceable("kp071"), "backups, saves and private copies are recognized by name")
        let dex = Classifier.profile(path: "/Users/x/GitHub/kr/android/app/build/intermediates/project_dex_archive", home: "/Users/x", readMetadata: false)
        let parent = Classifier.profile(path: "/Users/x/GitHub/kr/android/app/build/intermediates", home: "/Users/x", readMetadata: false)
        check(dex.displayName == "kr · project_dex_archive in Android build intermediates" && parent.displayName == "kr · Android build intermediates" && dex.project == "kr",
              "a subfolder is named for itself, and the project is its own folder")
        check(abbreviatedPath(NSHomeDirectory() + "/GitHub/x") == "~/GitHub/x" && abbreviatedPath("/Applications") == "/Applications", "paths show the home folder as ~")
        check(usedPercentText(0.995) == "99.5%" && usedPercentText(0.5) == "50%" && usedPercentText(0.9999) == "99.9%" && usedPercentText(1) == "100%", "a nearly full disk never reads as 100% used")
        check(friendlyApp("prl_vm_app") == "Parallels Desktop" && friendlyApp("node") == "node", "processes get the names people know")
        check(advice(for: folder("/fixture/Library/Application Support/OpenEmu", .appData, lastChanged: 200), policy: LocationPolicy(), devices: [:], now: now).verdict == .keep, "app libraries are kept however old")
        check(advice(for: folder("/fixture/.codex/backups/x", .backup, lastChanged: 300), policy: LocationPolicy(), devices: [:], now: now).verdict == .check, "recovery copies are never called safe")
        var busy = folder("/fixture/.npm/_cacache", .packageCache, lastChanged: 50); busy.processes = [ProcessEvidence(pid: 1, command: "node", access: "r", path: "/fixture/.npm/_cacache/x")]
        let busyAdvice = advice(for: busy, policy: LocationPolicy(), devices: [:], now: now)
        check(busyAdvice.verdict == .check && busyAdvice.reason.contains("node"), "open files downgrade a safe folder and name the app")
        check(advice(for: folder("/fixture/.npm/_cacache", .packageCache, lastChanged: 50), policy: LocationPolicy(expected: true), devices: [:], now: now).verdict == .keep, "your expected mark wins")
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
          {"udid":"0A1B2C3D-0000-4000-8000-000000000001","name":"iPhone Old","isAvailable":true,"lastUsedAt":"2026-05-01T00:00:00Z","dataPathSize":5000000000},
          {"udid":"NEW","name":"iPhone New","isAvailable":true,"lastUsedAt":"\(ISO8601DateFormatter().string(from: now.addingTimeInterval(-86400)))","dataPathSize":2000000000},
          {"udid":"NEVER","name":"iPad Fresh","isAvailable":true,"dataPathSize":4096}],
          "com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"GONE","name":"iPhone 15","isAvailable":false,"lastUsedAt":"2026-09-20T00:00:00Z","dataPathSize":1000}]}}
        """
        let sims = parseSimDevices(Data(json.utf8))
        check(sims.count == 4 && sims["0A1B2C3D-0000-4000-8000-000000000001"]?.runtime == "iOS 26.5" && sims["GONE"]?.available == false, "Xcode's device list is parsed with readable runtimes")
        func device(_ udid: String) -> Advice { advice(for: folder("/Users/x/Library/Developer/CoreSimulator/Devices/\(udid)", .simulator, lastChanged: nil), policy: LocationPolicy(), devices: sims, now: now) }
        check(device("0A1B2C3D-0000-4000-8000-000000000001").verdict == .safe && device("0A1B2C3D-0000-4000-8000-000000000001").reason.contains("iPhone Old") && device("0A1B2C3D-0000-4000-8000-000000000001").command == "xcrun simctl delete 0A1B2C3D-0000-4000-8000-000000000001", "an unused simulator is safe, named, and removed through Xcode")
        check(device("NEW").verdict == .check, "a simulator used yesterday is check first")
        check(device("GONE").verdict == .safe && device("GONE").reason.contains("iOS 17.0"), "a simulator whose iOS is gone is safe")
        check(device("NEVER").verdict == .safe && device("NEVER").reason.contains("never been started"), "a never-started simulator is safe")
        let simRoot = advice(for: folder("/Users/x/Library/Developer/CoreSimulator/Devices", .simulator, lastChanged: nil), policy: LocationPolicy(), devices: sims, now: now)
        check(simRoot.verdict == .check && simRoot.reason.contains("4 test devices") && simRoot.command == "xcrun simctl delete unavailable", "the Devices folder is never removed whole; it summarizes devices from Xcode")
        check(simSummary(sims, now: now).idle == 3, "idle devices: unused, never started, or unable to run")
        var pendingDevice = folder("/Users/x/Library/Developer/CoreSimulator/Devices/0A1B2C3D-0000-4000-8000-000000000001", .simulator, lastChanged: nil); pendingDevice.state = .pending; pendingDevice.allocatedBytes = nil
        let liveDevice = withSimulatorFacts(pendingDevice, devices: sims, now: now)
        check(liveDevice.state == .measured && liveDevice.allocatedBytes == 5_000_000_000 && liveDevice.profile.displayName == "iPhone Old · iOS 26.5" && sizeSourceText(liveDevice) == "size from Xcode, now", "a device row uses Xcode's name and current size; no scan needed")
        let staleRoot = withSimulatorFacts(folder("/Users/x/Library/Developer/CoreSimulator/Devices", .simulator, lastChanged: nil), devices: sims, now: now)
        let staleAdvice = advice(for: staleRoot, policy: LocationPolicy(), devices: sims, now: now)
        check(staleRoot.allocatedBytes == simSummary(sims, now: now).bytes && staleAdvice.reason.contains("measured 10 GiB"), "the Devices folder shows Xcode's current total and names the older scanned size")
        let plain = folder("/fixture/.npm/_cacache", .packageCache, lastChanged: 3)
        let unchanged = withSimulatorFacts(plain, devices: sims, now: now)
        check(unchanged.allocatedBytes == plain.allocatedBytes && unchanged.scopeID == plain.scopeID && unchanged.observedAt == plain.observedAt, "other folders keep their scanned size")
        check(withSimulatorFacts(pendingDevice, devices: [:], now: now).state == .pending, "without Xcode's list, a device row stays unscanned")
        check(ageText(now.addingTimeInterval(-3600 * 20.5), now: now) == "20 hours ago" && ageText(now.addingTimeInterval(-600), now: now) == "in the last hour" && ageText(now.addingTimeInterval(-86400 * 1.5), now: now) == "yesterday" && ageText(now.addingTimeInterval(-86400 * 20), now: now) == "2 weeks ago" && ageText(nil, now: now) == "unknown", "ages read like a person would say them")
        check(missingPaths(["/fixture-definitely-missing/x", "/"]) == ["/fixture-definitely-missing/x"], "missing folders are found by metadata only")
        check(fileOnlyPaths(["/etc/hosts", "/", "/fixture-definitely-missing/x"]) == ["/etc/hosts"], "files such as device_set.plist are told apart from folders by metadata only")
        let tricky = ["/", "/a", "/a/", "/a//b", "/a/./b", "/a/../b", "/a/.", "/a/..", "/a/...", "/a/.hidden", "/a/b..c", "/Users/x/Library/Application Support/Café"]
        check(tricky.allSatisfy { normalized($0) == URL(fileURLWithPath: $0).standardizedFileURL.path }, "the fast path check gives the same result as URL standardization")
        check(hasAncestor(in: ["/a/b"], "/a/b/c") && hasAncestor(in: ["/a/b"], "/a/b") && !hasAncestor(in: ["/a/b"], "/a/bc") && !hasAncestor(in: ["/a/b"], "/a") && hasAncestor(in: ["/"], "/x/y"), "ancestor lookup matches whole folder names only")
        check(containsPath("/a/b", "/a/b/c") && !containsPath("/a/b", "/a/bc") && containsPath("/", "/a") && containsPath("/a/b/", "/a/b/c") && !containsPath("/a/b/c", "/a/b"), "folder containment compares whole components")
        check(protectedPlace("Discovering: /Users/x/Library/Containers/com.apple.CoreDevice/Data") && protectedPlace("Discovering: /Users/x/Documents/Codex") && !protectedPlace("Discovering: /Users/x/.npm/_cacache"), "the permission hint appears only for places macOS asks about")
        let legacyBuild = FolderProfile(path: "/fixture/kartpad/build", name: "build", category: .workspace, project: "kartpad", associatedApp: "Compiler", explanation: "", consequence: "", evidence: [])
        let discoveredBuild = FolderProfile(path: "/fixture/kartpad/build/intermediates", name: "intermediates", category: .buildOutput, project: "kartpad", associatedApp: "Gradle", explanation: "", consequence: "", evidence: [])
        let refreshed = savedProfilesToRefresh([legacyBuild, discoveredBuild, legacyBuild], discovered: [discoveredBuild])
        check(refreshed.map(\.path) == ["/fixture/kartpad/build"], "a full scan re-measures saved folders discovery didn't find, each once")
        check(advice(for: folder("/fixture/kartpad/android/app/build/intermediates", .buildOutput, lastChanged: 0.5, project: "kartpad"), policy: LocationPolicy(), devices: [:], now: now).verdict == .rebuild, "project build output used today is rebuildable, even when classed as build files")
        check(advice(for: folder("/fixture/kartpad/android/app/build/intermediates", .buildOutput, lastChanged: nil, project: "kartpad"), policy: LocationPolicy(), devices: [:], now: now).verdict == .rebuild, "project build output with unknown last use is rebuildable")
        check(advice(for: folder("/fixture/Library/Developer/Xcode/DerivedData", .buildOutput, lastChanged: nil), policy: LocationPolicy(), devices: [:], now: now).verdict == .safe, "Xcode's DerivedData is safe; Xcode manages it")
        // Where the space went: growth since a date, new folders in full, older folders first scanned later skipped.
        let from = now.addingTimeInterval(-3 * 86400)
        func point(_ path: String, _ daysAgo: Double, _ bytes: Int64) -> HistoryPoint { HistoryPoint(recordID: "r\(daysAgo)", path: path, date: now.addingTimeInterval(-daysAgo * 86400), bytes: bytes, state: .measured, scopeID: "") }
        let grown = item("/Users/x/.codex/worktrees/a/build", .workspace, 50 * gib), fresh = item("/Users/x/.codex/worktrees/b/build", .workspace, 20 * gib)
        let unknown = item("/Users/x/Parallels/Win.pvm", .virtualMachine, 150 * gib), inner = item("/Users/x/.codex/worktrees/a/build/x", .workspace, 10 * gib)
        let history = [grown.profile.path: [point(grown.profile.path, 5, 30 * gib), point(grown.profile.path, 0, 50 * gib)], fresh.profile.path: [point(fresh.profile.path, 1, 20 * gib)],
                       unknown.profile.path: [point(unknown.profile.path, 0, 150 * gib)], inner.profile.path: [point(inner.profile.path, 5, 0), point(inner.profile.path, 0, 10 * gib)]]
        let went = spaceChanges(history: history, latest: [grown, fresh, unknown, inner], created: [fresh.profile.path: now.addingTimeInterval(-86400), unknown.profile.path: now.addingTimeInterval(-300 * 86400)], from: from, home: "/Users/x")
        check(went.count == 1 && went.first?.title == "Codex · Worktrees" && went.first?.bytes == 40 * gib && went.first?.newFolders == 1,
              "growth since a date groups by place, counts new folders in full, counts nested folders once, and skips folders first scanned later")
        var laterGrown = grown; laterGrown.observedAt = now
        let past = spaceChanges(history: [grown.profile.path: [point(grown.profile.path, 5, 30 * gib), point(grown.profile.path, 2, 35 * gib), point(grown.profile.path, 0, 50 * gib)]],
                                latest: [laterGrown], created: [:], from: now.addingTimeInterval(-4 * 86400), to: now.addingTimeInterval(-86400), home: "/Users/x")
        check(past.first?.bytes == 5 * gib, "a span that ended in the past uses the last scan before it ended")
        var wholeNew = item("/Users/x/.codex/worktrees/a", .workspace, 80 * gib); wholeNew.observedAt = now
        let pastInner = spaceChanges(history: [grown.profile.path: [point(grown.profile.path, 5, 30 * gib), point(grown.profile.path, 2, 35 * gib), point(grown.profile.path, 0, 50 * gib)], wholeNew.profile.path: [point(wholeNew.profile.path, 0, 80 * gib)]],
                                     latest: [wholeNew, laterGrown], created: [:], from: now.addingTimeInterval(-4 * 86400), to: now.addingTimeInterval(-86400), home: "/Users/x")
        check(pastInner.first?.bytes == 5 * gib, "a folder first measured after the span doesn't hide the folders inside it that were measured")
        let removedRun = item("/Users/x/.codex/scratch/old-run", .workspace, 12 * gib), longGone = item("/Users/x/.codex/scratch/ancient", .workspace, 3 * gib)
        let freed = spaceChanges(history: [removedRun.profile.path: [point(removedRun.profile.path, 5, 12 * gib), point(removedRun.profile.path, 1, 12 * gib)], longGone.profile.path: [point(longGone.profile.path, 40, 3 * gib)]],
                                 latest: [removedRun, longGone], created: [:], from: from, removed: [removedRun.profile.path, longGone.profile.path], home: "/Users/x")
        check(freed.count == 1 && freed[0].title == "Codex · Scratch" && freed[0].bytes == -12 * gib && freed[0].removedFolders == 1,
              "a folder removed inside the span counts as freed in its own place; one removed before the span doesn't")
        check(locationHint("/Users/x/.codex/worktrees/kartpad-stab/android/app/build") == "Codex worktree kartpad-stab" && locationHint("/Users/x/GitHub/kartpad/build") == "GitHub/kartpad" && locationHint("/tmp/x") == nil, "same-named projects are told apart by where they live")
        let single = record("single", [cache])
        check(single.folderSummary == cache.profile.displayName, "single-folder scan history identifies the folder")
        var stopped = single; stopped.complete = false; stopped.requestedCount = 4
        check(stopped.resultSummary == "Stopped · 1 of 4 folders scanned", "stopped history distinguishes scanned folders from requested coverage")
        let workspace = FolderProfile(path: "/fixture/project/build", name: "build", category: .workspace, project: "Project A", associatedApp: "Compiler", explanation: "", consequence: "", evidence: [])
        check(workspace.displayName == "Project A · build", "generic build folders identify their project")
        check(FolderCategory.workspace.rawValue == "Mixed workspace" && FolderCategory.workspace.displayName == "Project files", "plain labels preserve stored category identifiers")
        // 0.16: one framing for the charts, space used.
        check(usedChangeText(5 * gib).hasPrefix("+") && usedChangeText(5 * gib).hasSuffix(" used") && usedChangeText(-5 * gib).hasSuffix(" freed") && !usedChangeText(-5 * gib).contains("−") && usedChangeText(0) == "No change",
              "chart changes read as space used: up is +used, down is freed")
        // 0.16: git backup status for projects outside the scanned folders.
        let parsed = parseRepoStatus(" M a.swift\n?? notes.txt\n!! build/\n!! private/\n!! .env\n!! app.log\n!! android/app/.cxx/\n")
        check(parsed.changes == 2 && parsed.unkeptIgnored == ["private/", ".env"], "status counts uncommitted files and lists only ignored items worth keeping")
        let clean = RepoBackup(hasRemote: true, unpushed: 0, changes: 0, stashes: 0, unkeptIgnored: [], lastCommit: nil)
        check(clean.fullyBackedUp && clean.summary == "Backed up: pushed and clean", "a pushed, clean checkout is backed up")
        var privateInputs = clean; privateInputs.unkeptIgnored = ["private/"]
        check(privateInputs.backedUp && !privateInputs.fullyBackedUp && privateInputs.summary == "Backed up: pushed and clean. Not in git: private/", "ignored private files keep a pushed checkout from counting as fully backed up")
        check(rebuildableName("build-ios-device/") && rebuildableName("cmake-build-debug/") && rebuildableName("macos-build/") && rebuildableName(".pytest_cache/CACHEDIR.TAG") && !rebuildableName("ref/") && !rebuildableName("ref/game.iso") && !rebuildableName("artifacts/"), "dated and per-platform build folders are build output; reference files are not")
        var worktree = clean; worktree.isWorktree = true; worktree.branch = "codex/fix"; worktree.unpushed = 3
        check(worktree.fullyBackedUp && worktree.summary == "Clean worktree: its 3 unpushed commits stay in the main repository on codex/fix", "a clean worktree on a branch loses nothing when its folder goes")
        var dirtyWorktree = worktree; dirtyWorktree.changes = 2
        check(!dirtyWorktree.backedUp && dirtyWorktree.summary.hasPrefix("Not backed up"), "a worktree with uncommitted changes is not backed up")
        var detached = worktree; detached.branch = nil
        check(!detached.backedUp, "a detached worktree with unpushed commits is not backed up")
        var ahead = clean; ahead.unpushed = 2; ahead.stashes = 1
        check(!ahead.backedUp && ahead.summary == "Not backed up: 2 commits not pushed, 1 stash", "unpushed commits and stashes are named")
        var local = clean; local.hasRemote = false
        check(!local.backedUp && local.summary.hasPrefix("Not backed up: no remote"), "a checkout with no remote is only on this Mac")
        var unknownStatus = clean; unknownStatus.changes = nil
        check(!unknownStatus.backedUp && unknownStatus.summary.hasPrefix("Backup unknown"), "a git timeout is never read as backed up")
        func place(_ name: String, _ backup: RepoBackup?, daysAgo: Double) -> ElsewhereItem {
            var e = ElsewhereItem(path: "/fixture/GitHub/" + name, name: name, bytes: 10 * gib, note: nil); e.backup = backup; e.modified = now.addingTimeInterval(-daysAgo * 86400); e.scannedInside = 2 * gib; return e
        }
        func used(_ backup: RepoBackup, daysAgo: Double) -> RepoBackup { var b = backup; b.lastActivity = now.addingTimeInterval(-daysAgo * 86400); return b }
        var shared = used(clean, daysAgo: 90); shared.worktrees = 2
        var touched = place("touched", used(clean, daysAgo: 90), daysAgo: 0); touched.modified = now
        let idle = idleBackedUp([place("old", used(clean, daysAgo: 60), daysAgo: 60), place("recent", used(clean, daysAgo: 3), daysAgo: 3), place("private", used(privateInputs, daysAgo: 90), daysAgo: 90),
                                 place("plain", nil, daysAgo: 90), place("shared", shared, daysAgo: 90), touched], now: now)
        check(idle.map(\.name) == ["old", "touched"] && idle.first?.totalBytes == 12 * gib,
              "only backed-up projects idle for a month are offered, with their build folders; file dates in .git don't count as use")
        check(!shared.removable && shared.line.hasSuffix("2 worktrees use it"), "a repository other worktrees use is never offered for the Trash")
        check(elsewhereAbout("/Users/x/.ollama", home: "/Users/x") != nil && elsewhereAbout("/Users/x/Library/Android", home: "/Users/x") != nil && elsewhereAbout("/Users/x/.gemini", home: "/Users/x") != nil,
              "known AI and Android folders are explained")
        check(elsewhereAbout("/Users/x/GoldenPadBackups", home: "/Users/x")?.contains("Backups") == true && elsewhereAbout("/Users/x/zzz", home: "/Users/x") == nil, "backup folders are recognized by name; unknown ones get no made-up text")
        // 0.16: Codex scratch, Ollama and Android emulators are scanned.
        check(Coverage.entries.contains { $0.relativePath == ".codex/scratch" && $0.kind == .children } && Coverage.entries.contains { $0.relativePath == ".ollama/models" } && Coverage.entries.contains { $0.relativePath == ".android/avd" },
              "coverage includes Codex scratch, Ollama models and Android emulators")
        let scratch = Classifier.profile(path: "/Users/x/.codex/scratch/padforge-mac-home", home: "/Users/x", readMetadata: false)
        let scratchBackup = Classifier.profile(path: "/Users/x/.codex/scratch/iphone-kartpad-backup-20260929", home: "/Users/x", readMetadata: false)
        check(scratch.category == .workspace && scratch.associatedApp == "Codex scratch" && scratchBackup.category == .backup, "scratch folders are named for the task; backups in scratch are backups")
        check(Classifier.profile(path: "/Users/x/.ollama/models", home: "/Users/x", readMetadata: false).name == "Ollama models"
              && Classifier.profile(path: "/Users/x/.android/avd/KartPad_API_36_ARM64.avd", home: "/Users/x", readMetadata: false).name == "KartPad API 36 ARM64 emulator", "Ollama models and emulators get plain names")
        var scratchItem = item("/Users/x/.codex/scratch/kp061", .workspace, 63 * gib); scratchItem.profile = scratch; scratchItem.latestModifiedAt = now.addingTimeInterval(-20 * 86400)
        let scratchAdvice = advice(for: scratchItem, policy: LocationPolicy(), devices: [:], now: now)
        check(scratchAdvice.verdict == .check && scratchAdvice.short == "Left by a Codex task" && scratchAdvice.reason.contains("Codex task"), "scratch is your call, said plainly")
        check(locationHint("/Users/x/.codex/scratch/kp061") == "Codex scratch", "scratch folders say where they live")
        var bee = item("/Users/x/.diffusionbee", .model, 70 * gib); bee.profile = Classifier.profile(path: "/Users/x/.diffusionbee", home: "/Users/x", readMetadata: false); bee.latestModifiedAt = now.addingTimeInterval(-40 * 86400)
        bee.contents = FolderContents(children: [ChildSummary(name: "images", directory: true, identity: "1", bytes: 60 * gib, files: 10, modifiedAt: now.addingTimeInterval(-40 * 86400))],
                                      fileTypes: [], listedChildren: 1, retainedLimit: 512, omittedEntries: 0)
        var hub = bee; hub.profile = Classifier.profile(path: "/Users/x/.cache/huggingface", home: "/Users/x", readMetadata: false)
        check(advice(for: bee, policy: LocationPolicy(), devices: [:], now: now).staleItems.isEmpty && !advice(for: hub, policy: LocationPolicy(), devices: [:], now: now).staleItems.isEmpty,
              "pictures made in DiffusionBee are never listed as old items; old downloaded models still are")
        // 0.17: one ranked list of what to move to the Trash.
        check(quietText(20 * 3600) == "20 hours" && quietText(3 * 86400) == "3 days" && quietText(20 * 86400) == "2 weeks" && quietText(600) == "under an hour", "quiet times read in hours first, then days")
        var goneRecord = record("gone", []); goneRecord.measurements = [item("/fixture/x", .workspace, nil, .missing)]
        check(scanOutcome(goneRecord, grew: 0) == "That folder is gone now", "rescanning a removed folder says it's gone, not \"Scanned 0 folders\"")
        func aged(_ path: String, _ category: FolderCategory, hours: Double, gib size: Int64 = 10) -> FolderMeasurement {
            var m = item(path, category, size * gib); m.latestModifiedAt = now.addingTimeInterval(-hours * 3600)
            m.profile = Classifier.profile(path: path, home: "/Users/x", readMetadata: false); m.profile.category = category; return m
        }
        let quietScratch = aged("/Users/x/.codex/scratch/padforge-mac-home", .workspace, hours: 30, gib: 64)
        let busyScratch = aged("/Users/x/.codex/scratch/kp061", .workspace, hours: 5, gib: 62)
        var openScratch = aged("/Users/x/.codex/scratch/live", .workspace, hours: 40); openScratch.processes = [ProcessEvidence(pid: 1, command: "zsh", access: "cwd", path: "/Users/x/.codex/scratch/live")]
        let nested = aged("/Users/x/.codex/scratch/padforge-mac-home/games", .workspace, hours: 30, gib: 60)
        let oldBuild = aged("/Users/x/GitHub/kr/build", .workspace, hours: 50, gib: 20)
        let idleCache = aged("/Users/x/.npm/_cacache", .packageCache, hours: 24 * 10, gib: 1)
        let keptOne = aged("/Users/x/.codex/scratch/keepme", .workspace, hours: 90)
        let removed = aged("/Users/x/.codex/scratch/removed", .workspace, hours: 90)
        var busyWork = aged("/Users/x/.codex/worktrees/kp/work", .workspace, hours: 2, gib: 70)
        busyWork.contents = FolderContents(children: [ChildSummary(name: "old-run", directory: true, identity: "1", bytes: 30 * gib, files: 9, modifiedAt: now.addingTimeInterval(-40 * 3600)),
                                                      ChildSummary(name: "today-run", directory: true, identity: "2", bytes: 30 * gib, files: 9, modifiedAt: now.addingTimeInterval(-3600))],
                                           fileTypes: [], listedChildren: 2, retainedLimit: 512, omittedEntries: 0)
        let pool = [quietScratch, busyScratch, openScratch, nested, oldBuild, idleCache, keptOne, removed, busyWork]
        func adviseFor(_ m: FolderMeasurement) -> Advice { advice(for: m, policy: m.profile.path.hasSuffix("keepme") ? LocationPolicy(kept: true) : LocationPolicy(), devices: [:], now: now) }
        let dayList = suggestions(pool, advice: adviseFor, gone: [removed.profile.path], quiet: 24 * 3600, now: now)
        check(dayList.map(\.name) == ["padforge-mac-home", "old-run", "kr · build", "npm download cache"],
              "a day's quiet lists quiet scratch, old runs inside a busy folder, idle builds and safe caches, biggest first; busy, open, kept, removed and nested folders stay out")
        check(dayList[0].cost == .check && dayList[0].why == "Left by a Codex task · untouched 30 hours" && dayList[1].owner == busyWork.profile.path && dayList[2].cost == .rebuild && dayList[3].cost == .safe,
              "each suggestion says what removing it costs and why, and old items open the folder they sit in")
        check(suggestions(pool, advice: adviseFor, gone: [], quiet: 3 * 86400, now: now).map(\.name).contains("padforge-mac-home") == false, "a longer quiet time leaves out folders touched more recently")
        // Backups are never called rebuildable, even inside build output, and are marked so Select All skips them.
        var generated = aged("/Users/x/GitHub/pr/generated", .workspace, hours: 1, gib: 20)
        generated.contents = FolderContents(children: [ChildSummary(name: "device-backups", directory: true, identity: "1", bytes: 6 * gib, files: 9, modifiedAt: now.addingTimeInterval(-50 * 3600)),
                                                       ChildSummary(name: "toolchains", directory: true, identity: "2", bytes: 1 * gib, files: 9, modifiedAt: now.addingTimeInterval(-50 * 3600))],
                                            fileTypes: [], listedChildren: 2, retainedLimit: 512, omittedEntries: 0)
        let phoneBackup = aged("/Users/x/.codex/scratch/iphone-ballpad-backup-20260929", .workspace, hours: 72, gib: 2)
        let recovery = aged("/Users/x/.codex/backups/paperpad-20260920", .backup, hours: 30, gib: 2)
        let backupList = suggestions([generated, phoneBackup, recovery], advice: adviseFor, gone: [], quiet: 24 * 3600, now: now)
        let deviceBackups = backupList.first { $0.name == "device-backups" }, toolchains = backupList.first { $0.name == "toolchains" }
        check(deviceBackups?.cost == .check && deviceBackups?.backup == true && deviceBackups?.why.hasPrefix("Looks like a backup") == true && toolchains?.cost == .rebuild && toolchains?.backup == false,
              "a backup inside build output is Review first and marked; the build next to it stays rebuildable")
        check(backupList.first { $0.name.contains("iphone-ballpad-backup") }?.backup == true && !backupList.contains { $0.path == recovery.profile.path },
              "a backup in scratch is marked, and a recovery copy waits three days before it's listed")
        check(suggestions([recovery], advice: adviseFor, gone: [], quiet: 24 * 3600, now: now.addingTimeInterval(3 * 86400)).first?.backup == true, "an old recovery copy is listed, marked as a backup")
        check(staleChildren(generated, now: now, days: 1).map(\.name) == ["toolchains"], "a folder's old items never include its backups")
        check(dayList.allSatisfy { $0.seen != nil }, "each suggestion keeps the newest change the scan saw, for the recheck before copying")
        // 0.19: whole Codex worktrees, judged by git.
        func kept(changes: Int? = 0, ignored: [String] = [], branch: String? = "codex/fix", main: String? = nil) -> RepoBackup {
            RepoBackup(hasRemote: true, unpushed: 2, changes: changes, stashes: 0, unkeptIgnored: ignored, lastCommit: nil, isWorktree: true, branch: branch, worktrees: 0, lastActivity: nil, mainRepository: main)
        }
        let cleanTree = aged("/Users/x/.codex/worktrees/kp-fix", .workspace, hours: 30, gib: 40)
        let oldTree = aged("/Users/x/.codex/worktrees/kp-old", .workspace, hours: 24 * 9, gib: 20)
        let dirtyTree = aged("/Users/x/.codex/worktrees/kp-dirty", .workspace, hours: 30, gib: 50)
        let dirtyBuild = aged("/Users/x/.codex/worktrees/kp-dirty/kartpad/build", .workspace, hours: 30, gib: 45)
        check(isWorktreeFolder(cleanTree.profile.path) && !isWorktreeFolder(dirtyBuild.profile.path) && !isWorktreeFolder("/Users/x/.codex/worktrees"), "only a folder directly in ~/.codex/worktrees is a whole worktree")
        check(worktreeAdvice(cleanTree, .read(kept()), now: now).verdict == .rebuild && worktreeAdvice(oldTree, .read(kept()), now: now).verdict == .safe && worktreeAdvice(oldTree, .read(kept()), now: now).short == "Clean worktree",
              "a clean worktree whose commits stay in its repository is rebuildable, and safe after a week untouched")
        check(worktreeAdvice(dirtyTree, .read(kept(changes: 3)), now: now).short == "3 not committed" && worktreeAdvice(cleanTree, .read(kept(ignored: ["ref"])), now: now).verdict == .check
              && worktreeAdvice(cleanTree, .read(kept(branch: nil)), now: now).verdict == .check && worktreeAdvice(cleanTree, .read(kept(changes: nil)), now: now).verdict == .check
              && worktreeAdvice(cleanTree, .read(kept(main: "/nonexistent/repository")), now: now).short == "Repository gone"
              && worktreeAdvice(cleanTree, .unread, now: now).short == "Checking git…" && worktreeAdvice(cleanTree, .noRepository, now: now).verdict == .check,
              "uncommitted work, files git doesn't keep, unpushed detached commits, a missing repository or no answer from git keep a worktree Review first")
        let states = [cleanTree.profile.path: kept(), oldTree.profile.path: kept(), dirtyTree.profile.path: kept(changes: 3)]
        let variants = [kept(), kept(changes: 2), kept(changes: nil), kept(ignored: ["ref/"]), kept(branch: nil), kept(main: "/nonexistent/repository"), kept(main: "/")]
        check(variants.allSatisfy { [.safe, .rebuild].contains(worktreeAdvice(cleanTree, .read($0), now: now).verdict) == $0.keepsEverything },
              "the check repeated before copying agrees with the Clean worktree answer in every case")
        func treeAdvice(_ m: FolderMeasurement) -> Advice {
            advice(for: m, policy: LocationPolicy(), devices: [:], worktree: isWorktreeFolder(m.profile.path) ? states[m.profile.path].map { .read($0) } ?? .noRepository : nil, now: now)
        }
        let treeList = suggestions([cleanTree, oldTree, dirtyTree, dirtyBuild], advice: treeAdvice, gone: [], quiet: 24 * 3600, now: now)
        check(treeList.map(\.path) == [dirtyBuild, cleanTree, oldTree].map(\.profile.path) && treeList[1].cost == .rebuild && treeList[2].cost == .safe && treeList[1].why == "Clean worktree · untouched 30 hours",
              "clean worktrees are listed whole; one with uncommitted work isn't, but its build folder is")
        check(suggestions([cleanTree], advice: treeAdvice, gone: [], quiet: 72 * 3600, now: now).isEmpty, "a clean worktree used more recently than the quiet time stays out")
        let own = exclusiveBytes([dirtyTree, dirtyBuild, cleanTree])
        check(own[dirtyTree.profile.path] == 5 * gib && own[dirtyBuild.profile.path] == 45 * gib && own[cleanTree.profile.path] == 40 * gib, "each byte counts once, for the innermost scanned folder that holds it")
        let pruned = trashCommand([oldTree.profile.path], prune: ["/Users/x/GitHub/kartpad"])
        check(pruned.contains("for r in '/Users/x/GitHub/kartpad'; do [ -d \"$r/.git\" ] && [ ! -L \"$r\" ] && git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C \"$r\" worktree prune") && pruned.range(of: "worktree prune")!.lowerBound > pruned.range(of: "done; ")!.lowerBound
              && !trashCommand(["/a"]).contains("worktree"), "moving worktrees tells their repository afterwards; other commands don't mention git")
        // 0.19: your temporary folder. Items nothing has used for 3 days are safe, as macOS itself treats them.
        let tmpRoot = Coverage.temporaryFolder ?? "/private/var/folders/xx/T"
        var temp = item(tmpRoot, .temporary, 30 * gib); temp.latestModifiedAt = now
        temp.contents = FolderContents(children: [ChildSummary(name: "trace.ktrace", directory: true, identity: "1", bytes: 12 * gib, files: 1, modifiedAt: now.addingTimeInterval(-6 * 86400)),
                                                  ChildSummary(name: "build-tmp", directory: true, identity: "2", bytes: 2 * gib, files: 9, modifiedAt: now.addingTimeInterval(-30 * 3600)),
                                                  ChildSummary(name: "live", directory: true, identity: "3", bytes: 9 * gib, files: 9, modifiedAt: now.addingTimeInterval(-600))],
                                       fileTypes: [], listedChildren: 3, retainedLimit: 512, omittedEntries: 0)
        let tempList = suggestions([temp], advice: { advice(for: $0, policy: LocationPolicy(), devices: [:], now: now) }, gone: [], quiet: 24 * 3600, now: now)
        check(tempList.map(\.name) == ["trace.ktrace", "build-tmp"] && tempList[0].cost == .safe && tempList[1].cost == .check && tempList[0].why == "Temporary item · untouched 6 days" && tempList[0].owner == tmpRoot,
              "old temporary items are listed: safe after 3 days, Review first before; anything used recently stays out")
        check(advice(for: temp, policy: LocationPolicy(), devices: [:], now: now).staleItems.map(\.name) == ["trace.ktrace"], "the temporary folder counts items untouched for 3 days as old")
        // 0.20: folders that take no space here, and Xcode build folders named after a feature.
        var cloud = item("/Users/x/Documents/Codex/2026-07-06", .workspace, 0); cloud.fileCount = 120
        var empty = item("/Users/x/.codex/scratch/vaultpad-out", .workspace, 0); empty.fileCount = 0
        var tiny = item("/Users/x/.codex/scratch/notes", .workspace, 4096); tiny.fileCount = 2
        let cloudAdvice = advice(for: cloud, policy: LocationPolicy(), devices: [:], now: now), emptyAdvice = advice(for: empty, policy: LocationPolicy(), devices: [:], now: now)
        check(cloudAdvice.verdict == .keep && cloudAdvice.short == "In iCloud only" && emptyAdvice.verdict == .safe && emptyAdvice.short == "Empty"
              && advice(for: tiny, policy: LocationPolicy(), devices: [:], now: now).verdict == .check,
              "files kept only in iCloud are Not for the Trash, an empty folder is Safe to remove, and a small folder with files still gets looked at")
        check(!looksIrreplaceable("DerivedData-iPhoneOS-duplicate-save-20260927") && !looksIrreplaceable("derived-audio-recovery-20260927") && looksIrreplaceable("iphone-backup") && looksIrreplaceable("private-ocr-live"),
              "Xcode build folders named after a save or recovery feature aren't mistaken for backups")
        var taskWork = aged("/Users/x/.codex/tasks/app/work", .workspace, hours: 1, gib: 20)
        taskWork.contents = FolderContents(children: [ChildSummary(name: "DerivedData-iPhoneOS-save-flow", directory: true, identity: "1", bytes: 2 * gib, files: 9, modifiedAt: now.addingTimeInterval(-9 * 86400)),
                                                      ChildSummary(name: "design-loop-3", directory: true, identity: "2", bytes: 3 * gib, files: 9, modifiedAt: now.addingTimeInterval(-9 * 86400))],
                                           fileTypes: [], listedChildren: 2, retainedLimit: 512, omittedEntries: 0)
        let workList = suggestions([taskWork], advice: adviseFor, gone: [], quiet: 24 * 3600, now: now)
        check(workList.first { $0.name.hasPrefix("DerivedData") }?.cost == .rebuild && workList.first { $0.name == "design-loop-3" }?.cost == .check,
              "inside a task's work folder, Xcode build output is Rebuildable and other old runs are Review first")
        var chats = aged("/Users/x/.codex/sessions", .history, hours: 1, gib: 30); chats.processes = [ProcessEvidence(pid: 1, command: "codex", access: "r", path: "/Users/x/.codex/sessions/a.jsonl")]
        check(advice(for: chats, policy: LocationPolicy(), devices: [:], now: now).verdict == .keep, "chat history is Not for the Trash even while its app has it open")
        var busyTemp = temp; busyTemp.processes = [ProcessEvidence(pid: 1, command: "xcodebuild", access: "r", path: tmpRoot + "/build-tmp/log.txt")]
        check(suggestions([busyTemp], advice: { advice(for: $0, policy: LocationPolicy(), devices: [:], now: now) }, gone: [], quiet: 24 * 3600, now: now).map(\.name) == ["trace.ktrace"],
              "apps holding files in the temporary folder leave out only the items they hold")
        // 0.21: Safe and Rebuildable form one Nothing lost group; kinds group the list; big or Review first copies ask first.
        let lossless = Suggestion(path: "/a", name: "a", place: nil, bytes: gib, cost: .rebuild, why: "Build output · untouched 2 days")
        let finished = Suggestion(path: "/b", name: "b", place: nil, bytes: gib, cost: .safe, why: "Project finished")
        let oldTemp = Suggestion(path: "/t/x", name: "x", place: "Inside Temporary files", bytes: gib, cost: .safe, why: "Temporary item · untouched 4 days", owner: "/t")
        let look = Suggestion(path: "/c", name: "c", place: nil, bytes: gib, cost: .check, why: "Left by a Codex task · untouched 2 days")
        check(lossless.losesNothing && finished.losesNothing && oldTemp.losesNothing && !look.losesNothing,
              "Safe to remove and Rebuildable both lose nothing; Review first doesn't")
        check(lossless.kind == "Build output" && finished.kind == "Not needed again" && oldTemp.kind == "Temporary item" && look.kind == "Left by a Codex task",
              "each item's kind is the first words of why it's listed, and whole folders that are safe group as Not needed again")
        check(trashConfirmation(count: 3, bytes: 12 * gib, review: 0, reviewBytes: 0) == nil, "a small command of things that lose nothing copies straight away")
        let bigAsk = trashConfirmation(count: 51, bytes: 198 * gib, review: 0, reviewBytes: 0)
        check(bigAsk?.hasPrefix("51 items, 198 GiB in one command.") == true && bigAsk?.hasSuffix("Copy anyway?") == true, "selecting a lot (51 items) asks once, with the count and size")
        check(trashConfirmation(count: 1, bytes: 120 * gib, review: 0, reviewBytes: 0) != nil && trashConfirmation(count: 19, bytes: 99 * gib, review: 0, reviewBytes: 0) == nil,
              "100 GiB or 20 items asks; just under both doesn't")
        let mixedAsk = trashConfirmation(count: 2, bytes: 3 * gib, review: 1, reviewBytes: gib)
        check(mixedAsk == "2 items, 3 GiB, including 1 Review first (1 GiB). Each may hold the only copy of something. Copy anyway?", "any Review first item asks, however small the command")
        check(trashConfirmation(count: 2, bytes: 3 * gib, review: 2, reviewBytes: 3 * gib)?.hasPrefix("2 items, 3 GiB, all Review first.") == true, "a command of only Review first items says so")
        // Security: commands you paste. Every name is quoted so the shell reads it as text, whatever it holds.
        func shellEcho(_ shell: String, _ script: String) -> String {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: shell); process.arguments = ["-f", "-c", script]
            process.standardOutput = pipe; process.standardError = pipe
            try? process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let nasty = ["it's", "$(echo ran)", "\u{60}echo ran\u{60}", "a\"b", "back\\slash", "wow!", "two\nlines", "*", "-n"]
        check(nasty.allSatisfy { shellEcho("/bin/zsh", "printf %s " + shellQuoted($0)) == $0 && shellEcho("/bin/bash", "printf %s " + shellQuoted($0)) == $0 },
              "quoted names reach zsh and bash exactly as written: quotes, $(…), backticks, backslashes, !, newlines and globs run nothing")
        let tree = ProjectActivity(root: "/Users/x/.codex/worktrees/$(echo ran)", isWorktree: true, mainRepository: "/Users/x/GitHub/it's", registered: true, branch: nil, defaultBranch: nil, lastCommit: nil, merged: nil, uncommitted: 0)
        check(tree.removeWorktreeCommand == "git -C '/Users/x/GitHub/it'\\''s' worktree remove '/Users/x/.codex/worktrees/$(echo ran)'", "the worktree command quotes both paths, so $(…) in a name stays text")
        check(simDeleteCommand("0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9") == "xcrun simctl delete 0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9" && simDeleteCommand("x; touch y") == nil && simDeleteCommand("") == nil,
              "a simulator command is offered only for a real device ID")
        check(forShell("( echo hi )", shell: "/bin/zsh") == "( echo hi )" && forShell("( echo 'hi' )", shell: "/opt/homebrew/bin/fish") == "/bin/zsh -c '( echo '\\''hi'\\'' )'"
              && shellEcho("/bin/zsh", forShell("( echo 'hi' )", shell: "/opt/homebrew/bin/fish")) == "hi\n", "bash and zsh get the command as written; other shells get it run by zsh, unchanged")
        // Which paths may be in a Trash command at all.
        let home = "/Users/x", tmp = "/private/var/folders/ab/cd/T"
        check(pathFitsCommand("/Users/x/.codex/scratch/pm028", home: home, temporary: tmp) && pathFitsCommand("/Users/x/Library/Developer/Xcode/DerivedData", home: home, temporary: tmp)
              && pathFitsCommand(tmp + "/build-tmp", home: home, temporary: tmp), "ordinary scratch, build and temporary items may be in a command")
        let refusedPaths = ["/Users/x", "/Users/x/GitHub", "/Users/x/Documents", "/Users/x/Library/Caches", "/Users/x/Library/Keychains/login.keychain-db", "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/a",
                            "/Users/x/.ssh/id", "/Users/x/.Trash/old", "/Users/y/build", "/", "/Applications/App.app", "/Users/x/a/../b", "/Users/x//a/b", "relative/path", tmp,
                            "/Users/x/a/new\nline", "/Users/x/a/evil\u{1B}[2J", "/Users/x/a/\u{202E}gnp.exe"]
        check(refusedPaths.allSatisfy { !pathFitsCommand($0, home: home, temporary: tmp) },
              "never in a command: home and its top-level folders, ~/Library's own folders, keychains, iCloud Drive, keys, the Trash, other users, outside home, .. or //, and names with control or invisible characters")
        // The command itself, run for real on things it must leave alone: a link, a missing path, and an expired command.
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cc-security-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let target = fixture.appendingPathComponent("keep me.txt"), link = fixture.appendingPathComponent("link $(echo ran)")
        try? Data("keep".utf8).write(to: target)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let soon = Date().addingTimeInterval(600)
        let linkRun = shellEcho("/bin/zsh", trashCommand([link.path, fixture.path + "/missing"], expires: soon))
        check(linkRun.contains("NOT moved: \(link.path) (a link; left alone)") && linkRun.contains("Already gone: \(fixture.path)/missing")
              && FileManager.default.fileExists(atPath: target.path) && (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil && !linkRun.contains("ran\n"),
              "a link is never moved, so what it points to is never touched; a missing path is reported, not acted on")
        let expiredRun = shellEcho("/bin/bash", trashCommand([target.path], expires: Date().addingTimeInterval(-1)))
        check(expiredRun.hasPrefix("This command is over an hour old, so nothing was moved.") && FileManager.default.fileExists(atPath: target.path),
              "an expired command moves nothing, so one pasted later from clipboard history is harmless")
        check(trashCommand(["/a"]).hasPrefix("( m=0") && trashCommand(["/a"], expires: soon).contains("-le \(Int(soon.timeIntervalSince1970)) ]"), "the clock check is in every copied command")
        // git never runs a program a repository's config names.
        let safety = gitSafetyArguments(filterKeys: ["filter.lfs.clean", "filter.lfs.process", "filter.a.b.smudge"]) ?? []
        check(safety.contains("core.fsmonitor=false") && safety.contains("log.showSignature=false") && safety.contains("filter.lfs.clean=") && safety.contains("filter.lfs.process=")
              && safety.contains("filter.a.b.smudge=") && safety.contains("filter.a.b.process=") && gitSafetyArguments(filterKeys: ["filter.x=y.clean"]) == nil,
              "fsmonitor, signature checks and every filter the config names are switched off; a filter name that can't be emptied safely stops git running")
        print("SUCCESS: \(count) overview checks; only a temporary fixture is written.")
    }
}
