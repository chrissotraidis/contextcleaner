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
        check(finishedAdvice.reason.contains("looks finished") && finishedAdvice.command == #"git -C "/fixture/kartpad" worktree remove "/fixture/wt/kartpad-diag""# && finishedAdvice.evidence.first?.contains("merged into main") == true,
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
        check(freshCache.verdict == .rebuild && freshCache.short == "Used today" && freshCache.reason.contains("next run is slower"), "a cache a tool used today is rebuildable, never safe")
        var derived = folder("/fixture/Library/Developer/Xcode/DerivedData", .buildOutput, lastChanged: 0.1)
        derived.contents = FolderContents(children: [
            ChildSummary(name: "OldGame-abc", directory: true, identity: "1", bytes: 3 * gib, files: 10, modifiedAt: now.addingTimeInterval(-60 * 86400)),
            ChildSummary(name: "Current-def", directory: true, identity: "2", bytes: 5 * gib, files: 10, modifiedAt: now),
            ChildSummary(name: "Tiny-ghi", directory: true, identity: "3", bytes: 1_000, files: 1, modifiedAt: now.addingTimeInterval(-90 * 86400))],
            fileTypes: [], listedChildren: 3, retainedLimit: 512, omittedEntries: 0)
        let derivedAdvice = advice(for: derived, policy: LocationPolicy(), devices: [:], now: now)
        check(derivedAdvice.verdict == .rebuild && derivedAdvice.staleItems.map(\.name) == ["OldGame-abc"] && derivedAdvice.staleBytes == 3 * gib && derivedAdvice.staleDays == 30 && derivedAdvice.short == "3 GiB old inside",
              "a busy cache points at the old items inside it, ignoring tiny ones")
        check(trashCommand(["/a/it's \"here\"", "/b\\c"]) == #"osascript -e 'tell application "Finder" to delete {POSIX file "/a/it'\''s \"here\"" as alias, POSIX file "/b\\c" as alias}' >/dev/null"#,
              "the Trash command asks Finder, escaping each path for AppleScript and the whole script for the shell")
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
          {"udid":"OLD","name":"iPhone Old","isAvailable":true,"lastUsedAt":"2026-05-01T00:00:00Z","dataPathSize":5000000000},
          {"udid":"NEW","name":"iPhone New","isAvailable":true,"lastUsedAt":"\(ISO8601DateFormatter().string(from: now.addingTimeInterval(-86400)))","dataPathSize":2000000000},
          {"udid":"NEVER","name":"iPad Fresh","isAvailable":true,"dataPathSize":4096}],
          "com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"GONE","name":"iPhone 15","isAvailable":false,"lastUsedAt":"2026-09-20T00:00:00Z","dataPathSize":1000}]}}
        """
        let sims = parseSimDevices(Data(json.utf8))
        check(sims.count == 4 && sims["OLD"]?.runtime == "iOS 26.5" && sims["GONE"]?.available == false, "Xcode's device list is parsed with readable runtimes")
        func device(_ udid: String) -> Advice { advice(for: folder("/Users/x/Library/Developer/CoreSimulator/Devices/\(udid)", .simulator, lastChanged: nil), policy: LocationPolicy(), devices: sims, now: now) }
        check(device("OLD").verdict == .safe && device("OLD").reason.contains("iPhone Old") && device("OLD").command == "xcrun simctl delete OLD", "an unused simulator is safe, named, and removed through Xcode")
        check(device("NEW").verdict == .check, "a simulator used yesterday is check first")
        check(device("GONE").verdict == .safe && device("GONE").reason.contains("iOS 17.0"), "a simulator whose iOS is gone is safe")
        check(device("NEVER").verdict == .safe && device("NEVER").reason.contains("never been started"), "a never-started simulator is safe")
        let simRoot = advice(for: folder("/Users/x/Library/Developer/CoreSimulator/Devices", .simulator, lastChanged: nil), policy: LocationPolicy(), devices: sims, now: now)
        check(simRoot.verdict == .check && simRoot.reason.contains("4 test devices") && simRoot.command == "xcrun simctl delete unavailable", "the Devices folder is never removed whole; it summarizes devices from Xcode")
        check(simSummary(sims, now: now).idle == 3, "idle devices: unused, never started, or unable to run")
        var pendingDevice = folder("/Users/x/Library/Developer/CoreSimulator/Devices/OLD", .simulator, lastChanged: nil); pendingDevice.state = .pending; pendingDevice.allocatedBytes = nil
        let liveDevice = withSimulatorFacts(pendingDevice, devices: sims, now: now)
        check(liveDevice.state == .measured && liveDevice.allocatedBytes == 5_000_000_000 && liveDevice.profile.displayName == "iPhone Old · iOS 26.5" && sizeSourceText(liveDevice) == "size from Xcode, now", "a device row uses Xcode's name and current size; no scan needed")
        let staleRoot = withSimulatorFacts(folder("/Users/x/Library/Developer/CoreSimulator/Devices", .simulator, lastChanged: nil), devices: sims, now: now)
        let staleAdvice = advice(for: staleRoot, policy: LocationPolicy(), devices: sims, now: now)
        check(staleRoot.allocatedBytes == simSummary(sims, now: now).bytes && staleAdvice.reason.contains("measured 10 GiB"), "the Devices folder shows Xcode's current total and names the older scanned size")
        let plain = folder("/fixture/.npm/_cacache", .packageCache, lastChanged: 3)
        let unchanged = withSimulatorFacts(plain, devices: sims, now: now)
        check(unchanged.allocatedBytes == plain.allocatedBytes && unchanged.scopeID == plain.scopeID && unchanged.observedAt == plain.observedAt, "other folders keep their scanned size")
        check(withSimulatorFacts(pendingDevice, devices: [:], now: now).state == .pending, "without Xcode's list, a device row stays unscanned")
        check(ageText(now.addingTimeInterval(-3600), now: now) == "today" && ageText(now.addingTimeInterval(-86400 * 1.5), now: now) == "yesterday" && ageText(now.addingTimeInterval(-86400 * 20), now: now) == "2 weeks ago" && ageText(nil, now: now) == "unknown", "ages read like a person would say them")
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
        check(locationHint("/Users/x/.codex/worktrees/kartpad-stab/android/app/build") == "Codex worktree kartpad-stab" && locationHint("/Users/x/GitHub/kartpad/build") == "GitHub/kartpad" && locationHint("/tmp/x") == nil, "same-named projects are told apart by where they live")
        let single = record("single", [cache])
        check(single.folderSummary == cache.profile.displayName, "single-folder scan history identifies the folder")
        var stopped = single; stopped.complete = false; stopped.requestedCount = 4
        check(stopped.resultSummary == "Stopped · 1 of 4 folders scanned", "stopped history distinguishes scanned folders from requested coverage")
        let workspace = FolderProfile(path: "/fixture/project/build", name: "build", category: .workspace, project: "Project A", associatedApp: "Compiler", explanation: "", consequence: "", evidence: [])
        check(workspace.displayName == "Project A · build", "generic build folders identify their project")
        check(FolderCategory.workspace.rawValue == "Mixed workspace" && FolderCategory.workspace.displayName == "Project files", "plain labels preserve stored category identifiers")
        print("SUCCESS: \(count) overview checks; no filesystem mutations.")
    }
}
