import Foundation
@main struct DiscoveryTests {
    @MainActor static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); count += 1; print("PASS " + message) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let storage = try AppendStore(root: root.appendingPathComponent("store"))
        let home = root.appendingPathComponent("home").path
        let discovered = Classifier.profile(path: home + "/new-build-output", home: home, readMetadata: false)
        let selected = home + "/selected-but-not-scanned"
        try storage.saveDiscovery(Discovery(profiles: [discovered], notes: ["Fixture discovery"] ))
        let firstFile = try FileManager.default.contentsOfDirectory(at: storage.root.appendingPathComponent("discoveries"), includingPropertiesForKeys: nil)[0]
        let firstBytes = try Data(contentsOf: firstFile)
        let later = Classifier.profile(path: home + "/later-location", home: home, readMetadata: false)
        try storage.saveDiscovery(Discovery(profiles: [later], notes: ["Fixture later limited discovery"]))
        var prefs = Preferences(); prefs.customRoots = [selected]; prefs.lastDiscovery = Date(); prefs.dailyWhileOpen = false
        try storage.save(prefs)
        let reloaded = CleanerModel(home: home, dataRoot: storage.root)
        check(reloaded.records.isEmpty, "discovery does not fabricate a scan record")
        check(Set(reloaded.discovery.profiles.map(\.path)) == Set([discovered.path,later.path,selected]), "discovered and selected unmeasured locations survive model restart")
        check(reloaded.rows.allSatisfy { $0.measurement.state == .pending && $0.bytes == -1 && $0.status == "Not scanned" }, "unmeasured locations have no size or measured status")
        check(reloaded.rows.allSatisfy { historyPoints($0.id, records: reloaded.records).isEmpty }, "discovery never invents measurement history")
        reloaded.selection = [discovered.path, later.path]
        reloaded.search = "new-build-output"; reloaded.retainVisibleSelection()
        check(reloaded.selection == [discovered.path] && reloaded.selected == discovered.path, "filtering a multi-selection retains only visible rows and updates the inspector")
        reloaded.section = .watching; reloaded.retainVisibleSelection()
        check(reloaded.selection.isEmpty && reloaded.selected == nil && !reloaded.canRescanSelection, "switching views clears hidden selection and disables rescan")
        reloaded.search = ""
        reloaded.section = .needsAttention
        check(reloaded.rows.isEmpty && reloaded.attentionCount == 0, "unscanned folders are not scan errors")
        check(reloaded.overview.pendingCount == 3, "unscanned folders have a separate overview count")
        reloaded.section = .locations; reloaded.locationFilter = .unscanned
        check(reloaded.rows.count == 3, "unscanned folders remain available in their own filter")
        reloaded.policy(selected) { $0.excluded = true; $0.note = "Fixture exclusion" }
        check(!reloaded.rows.contains { $0.id == selected }, "exclusion still governs persisted discovery")
        let second = CleanerModel(home: home, dataRoot: storage.root)
        check(second.preferences.excluded(selected) && second.preferences.policy(selected).note == "Fixture exclusion", "policy edits survive alongside preserved discovery")
        check(try Data(contentsOf: firstFile) == firstBytes, "a later discovery never overwrites the earlier inventory")
        check(try FileManager.default.contentsOfDirectory(atPath: storage.root.appendingPathComponent("discoveries").path).count == 2, "discovery snapshots append without pruning")
        let token = Cancellation(); token.cancel()
        var callbacks = 0
        let cancelled = Inventory.discover(home: home, preferences: prefs, cancellation: token) { _ in callbacks += 1 }
        check(cancelled.complete == false && callbacks == 0, "pre-cancelled discovery avoids filesystem progress and records incompleteness")
        let before = second.discovery.profiles.count
        second.acceptDiscovery(Discovery(profiles: [], notes: ["Cancelled fixture"], complete: false))
        check(second.discovery.profiles.count == before, "partial discovery retains previously known locations")
        let date = second.preferences.lastDiscovery
        second.recordDiscovery()
        check(second.preferences.lastDiscovery == date, "partial discovery does not delay the next scheduled rediscovery")
        second.setAppearance("Light")
        let appearanceRestart = CleanerModel(home: home, dataRoot: storage.root)
        check(appearanceRestart.preferences.appearance == "Light", "appearance survives actual model restart")
        appearanceRestart.setAppearance("Unexpected")
        check(appearanceRestart.preferences.appearance == "Light", "unrecognized appearance does not corrupt saved preference")
        check(appearanceRestart.preferences.excluded(selected), "appearance update preserves unrelated exclusions")
        let grower = Classifier.profile(path: home + "/grower", home: home, readMetadata: false)
        let steady = Classifier.profile(path: home + "/steady", home: home, readMetadata: false)
        let expected = Classifier.profile(path: home + "/expected", home: home, readMetadata: false)
        func measure(_ profile: FolderProfile, _ bytes: Int64, _ date: Date) -> FolderMeasurement {
            var m = FolderMeasurement(profile: profile, observedAt: date, state: .measured, allocatedBytes: bytes, fileCount: 1, processes: [], activityCheckAvailable: true, elapsedSeconds: 0)
            m.scopeID = "metadata-v1:"; return m
        }
        let t0 = Date().addingTimeInterval(-86400), t1 = Date()
        let watchModel = CleanerModel(home: home, dataRoot: storage.root)
        watchModel.policy(expected.path) { $0.expected = true }
        let baseline = ScanRecord(id: "auto-baseline", startedAt: t0, finishedAt: t0, scope: "fixture", complete: true, measurements: [measure(grower, 1_000_000_000, t0), measure(steady, 5_000_000_000, t0), measure(expected, 1_000_000_000, t0)], discoveryNotes: [])
        let laterScan = ScanRecord(id: "auto-later", startedAt: t1, finishedAt: t1, scope: "fixture", complete: true, measurements: [measure(grower, 3_000_000_000, t1), measure(steady, 5_000_000_100, t1), measure(expected, 9_000_000_000, t1)], discoveryNotes: [])
        watchModel.records = [baseline, laterScan]
        watchModel.autoWatch(after: laterScan)
        check(watchModel.preferences.policy(grower.path).watched && watchModel.preferences.policy(grower.path).autoWatched == true, "a location that grew about 2 GB across comparable scans is watched automatically")
        check(watchModel.preferences.policy(grower.path).autoWatchedBytes == 2_000_000_000, "the growth that triggered watching is recorded")
        check(!watchModel.preferences.policy(steady.path).watched, "tiny growth below the floor is not auto-watched")
        check(!watchModel.preferences.policy(expected.path).watched, "expected growth is never auto-watched")
        watchModel.undoAutoWatch(grower.path)
        check(!watchModel.preferences.policy(grower.path).watched && watchModel.preferences.policy(grower.path).autoWatched == nil, "undo removes the automatic watch")
        let reopened = CleanerModel(home: home, dataRoot: storage.root)
        check(!reopened.preferences.policy(grower.path).watched && reopened.preferences.policy(expected.path).expected, "undo and expected flags persist across restart")
        // Warm each cache, then mutate data without changing the record or profile count.
        _ = watchModel.rows; _ = watchModel.overview; _ = watchModel.history(grower.path)
        watchModel.records[1].measurements[0].allocatedBytes = 4_000_000_000
        check(watchModel.latest.first { $0.profile.path == grower.path }?.allocatedBytes == 4_000_000_000, "same-count record updates invalidate latest measurements")
        check(watchModel.growthSummary(grower.path).delta == 3_000_000_000, "same-count updates invalidate cached growth")
        check(watchModel.history(grower.path).last?.bytes == 4_000_000_000, "same-count updates invalidate cached history")
        check(watchModel.rows.first { $0.id == grower.path }?.bytes == 4_000_000_000, "same-count updates invalidate table rows")
        check(watchModel.overview.measuredBySize.first { $0.profile.path == grower.path }?.allocatedBytes == 4_000_000_000, "same-count updates invalidate Overview")
        watchModel.discovery = Discovery(profiles: [discovered], notes: [])
        _ = watchModel.rows
        watchModel.discovery = Discovery(profiles: [later], notes: [])
        check(watchModel.rows.contains { $0.id == later.path } && !watchModel.rows.contains { $0.id == discovered.path }, "same-count discovery replacements invalidate rows")
        watchModel.running = true
        watchModel.partial = [measure(grower, 6_000_000_000, t1)]
        _ = watchModel.latest
        watchModel.partial[0].allocatedBytes = 7_000_000_000
        check(watchModel.latest.first { $0.profile.path == grower.path }?.allocatedBytes == 7_000_000_000, "same-count partial updates invalidate live measurements")
        watchModel.running = false
        check(watchModel.latest.first { $0.profile.path == grower.path }?.allocatedBytes == 4_000_000_000, "stopping a scan drops partial cache values")
        watchModel.selection = [grower.path]
        check(watchModel.canRescanSelection, "single included selection enables a folder rescan")
        watchModel.selection = [grower.path, steady.path]
        check(!watchModel.canRescanSelection, "multi-selection cannot accidentally rescan its first folder")
        watchModel.selection = [grower.path]
        watchModel.policy(grower.path) { $0.excluded = true }
        check(!watchModel.canRescanSelection, "excluded selection disables a folder rescan")
        watchModel.setAppearance("Dark"); watchModel.toggleAppearance()
        check(watchModel.preferences.appearance == "Light", "menu appearance toggle honors explicit dark preference")
        watchModel.toggleAppearance()
        check(watchModel.preferences.appearance == "Dark", "menu appearance toggle switches back to dark")
        var entry = Coverage.entries[0]; entry.relativePath = "store"
        check(Coverage.presence(entry, home: root.path) == .present, "coverage detects a present fixture directory")
        entry.relativePath = "absent-fixture"
        check(Coverage.presence(entry, home: root.path) == .missing, "coverage distinguishes a missing directory")
        entry.relativePath = String(repeating: "x", count: 300)
        check(Coverage.presence(entry, home: root.path) == .unavailable, "filesystem errors are never reported as a missing directory")
        var legacyWatch = LocationPolicy(recurring: true)
        check(legacyWatch.isWatched, "legacy Recurring preferences participate in Watching")
        legacyWatch.isWatched = false
        check(!legacyWatch.watched && !legacyWatch.recurring, "Stop Watching clears both legacy and current watch flags")
        legacyWatch.isWatched = true
        check(legacyWatch.watched && !legacyWatch.recurring, "new watch choices use one canonical stored flag")
        var failed = measure(steady, 0, t1); failed.state = .inaccessible; failed.allocatedBytes = nil
        var stoppedFolder = measure(expected, 0, t1); stoppedFolder.state = .cancelled; stoppedFolder.allocatedBytes = nil
        watchModel.records = [ScanRecord(id: "issue-test", startedAt: t1, finishedAt: t1, scope: "fixture", complete: false, measurements: [failed, stoppedFolder], discoveryNotes: [])]
        watchModel.section = .needsAttention
        check(watchModel.attentionCount == 1 && watchModel.rows.map(\.id) == [steady.path], "scan issues include access failures but not pending or user-stopped folders")
        // Hourly capacity readings: a timestamp and two numbers, appended, never removed.
        let capacityModel = CleanerModel(home: home, dataRoot: storage.root)
        let startCount = capacityModel.capacity.count
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        capacityModel.volume = VolumeSnapshot(date: base, total: 1_000, free: 400)
        capacityModel.recordCapacityIfDue()
        check(capacityModel.capacity.last == CapacityReading(date: base, total: 1_000, free: 400) && capacityModel.capacity.count == startCount + 1, "a capacity reading stores its time, total and free space")
        capacityModel.volume = VolumeSnapshot(date: base.addingTimeInterval(600), total: 1_000, free: 390)
        capacityModel.recordCapacityIfDue()
        check(capacityModel.capacity.count == startCount + 1, "a second reading within the hour is not stored")
        capacityModel.volume = VolumeSnapshot(date: base.addingTimeInterval(CleanerModel.capacityInterval), total: 1_000, free: 380)
        capacityModel.recordCapacityIfDue()
        check(capacityModel.capacity.count == startCount + 2, "the next reading is stored about an hour later")
        let capacityFiles = try FileManager.default.contentsOfDirectory(atPath: storage.root.appendingPathComponent("capacity").path)
        check(capacityFiles.count == capacityModel.capacity.count, "each reading is its own new file and none is removed")
        let capacityRestart = CleanerModel(home: home, dataRoot: storage.root)
        check(capacityRestart.capacity == capacityModel.capacity, "readings reload after a restart without being rewritten")
        check(capacityRestart.usage.contains { $0.date == base && $0.used == 600 }, "stored readings appear on the Space used chart")
        capacityRestart.volume = VolumeSnapshot(date: base.addingTimeInterval(7200), total: 1_000, free: 350)
        capacityRestart.lastResult = nil
        capacityRestart.open(grower.path)
        check(capacityRestart.section == .locations && capacityRestart.selected == grower.path && capacityRestart.locationFilter == .all, "opening a folder from Overview shows it selected in Folders")
        // Can I remove it? Safe folders are totalled and filtered; gone folders drop out of both.
        let verdictModel = CleanerModel(home: home, dataRoot: storage.root)
        var buildProfile = Classifier.profile(path: home + "/verdict/DerivedData", home: home, readMetadata: false); buildProfile.category = .buildOutput
        var oldBuild = measure(buildProfile, 5_000_000_000, t0); oldBuild.latestModifiedAt = Date().addingTimeInterval(-30 * 86400)
        var libraryProfile = Classifier.profile(path: home + "/verdict/Library", home: home, readMetadata: false); libraryProfile.category = .appData
        verdictModel.records = [ScanRecord(id: "verdicts", startedAt: t0, finishedAt: t0, scope: "fixture", complete: true, measurements: [oldBuild, measure(libraryProfile, 9_000_000_000, t0)], discoveryNotes: [])]
        verdictModel.gone = []
        check(verdictModel.overview.safe.map(\.profile.path) == [buildProfile.path] && verdictModel.overview.safeBytes == 5_000_000_000, "the Overview totals only folders that are safe to remove")
        verdictModel.section = .locations; verdictModel.locationFilter = .safe
        check(verdictModel.rows.map(\.id) == [buildProfile.path], "Safe to remove lists safe folders only")
        verdictModel.locationFilter = .keep
        check(verdictModel.rows.map(\.id) == [libraryProfile.path] && verdictModel.rows.first?.advice.verdict == .keep, "app libraries are listed under Keep")
        verdictModel.gone = [buildProfile.path]
        check(verdictModel.overview.safe.isEmpty && !verdictModel.overview.measuredBySize.contains { $0.profile.path == buildProfile.path }, "a folder that's gone leaves the Overview's totals")
        verdictModel.locationFilter = .all
        check(!verdictModel.rows.contains { $0.id == buildProfile.path } && verdictModel.gone.contains(buildProfile.path), "a folder that's no longer on disk is hidden from the list and counted as hidden")
        verdictModel.locationFilter = .safe
        check(verdictModel.rows.isEmpty, "a gone folder is never offered as safe to remove")
        // Keep: one choice takes a folder out of every suggestion and into Kept, with its size.
        verdictModel.gone = []
        verdictModel.policy(buildProfile.path) { $0.isKept = true }
        check(verdictModel.rows.isEmpty && verdictModel.overview.safe.isEmpty, "a kept folder is never suggested")
        verdictModel.section = .kept
        check(verdictModel.rows.first { $0.id == buildProfile.path }?.status == "Kept" && verdictModel.rows.allSatisfy { $0.policy.isKept || $0.policy.excluded }
              && verdictModel.keptSummary.keptBytes == 5_000_000_000 && verdictModel.keptSummary.kept.map(\.profile.path) == [buildProfile.path],
              "kept and turned-off folders share their own view, and kept ones have their own total")
        verdictModel.policy(buildProfile.path) { $0.isKept = false }
        verdictModel.section = .locations
        check(verdictModel.rows.map(\.id) == [buildProfile.path], "stopping keeping brings the suggestion back")
        let legacyPolicy = try? JSONDecoder().decode(LocationPolicy.self, from: Data(#"{"watched":false,"recurring":false,"expected":false,"excluded":false,"tags":[],"note":""}"#.utf8))
        check(legacyPolicy?.isKept == false, "preferences saved before Keep existed still load")
        // Gone folders are not problems to fix.
        var goneProfile = Classifier.profile(path: home + "/verdict/Removed", home: home, readMetadata: false); goneProfile.category = .appData
        var goneItem = measure(goneProfile, 1_000, t0); goneItem.state = .missing
        verdictModel.records.append(ScanRecord(id: "missing", startedAt: t0, finishedAt: t0.addingTimeInterval(1), scope: "fixture", complete: false, measurements: [goneItem], discoveryNotes: []))
        verdictModel.gone = [goneProfile.path]
        verdictModel.section = .needsAttention
        check(verdictModel.rows.isEmpty && verdictModel.attentionCount == 0, "a folder that's gone never shows up as a scan problem")
        // Default order: big folders you haven't used lately come first.
        let fresh = FolderRow(measurement: measure(libraryProfile, 50_000_000_000, t0), policy: LocationPolicy(), change: GrowthSummary(), advice: Advice(verdict: .check, reason: "", howTo: "", command: nil, lastUsed: Date()))
        let idle = FolderRow(measurement: measure(buildProfile, 10_000_000_000, t0), policy: LocationPolicy(), change: GrowthSummary(), advice: Advice(verdict: .check, reason: "", howTo: "", command: nil, lastUsed: Date().addingTimeInterval(-120 * 86400)))
        check(idle.idleScore > fresh.idleScore && fresh.idleScore == 0, "a 10 GB folder unused for four months outranks a 50 GB folder used today")
        // Git activity, read from a real throwaway repository inside the fixture folder.
        let repo = root.appendingPathComponent("gitfixture"), tree = root.appendingPathComponent("gitfixture-feature")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        func git(_ arguments: [String]) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", repo.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.com", "-c", "commit.gpgsign=false"] + arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try? process.run(); process.waitUntilExit()
        }
        git(["init", "-q", "-b", "main"])
        try Data("one".utf8).write(to: repo.appendingPathComponent("file.txt"))
        git(["add", "file.txt"]); git(["commit", "-qm", "one"])
        let clean = readProjectActivity(repo.path)
        check(clean.branch == "main" && clean.uncommitted == 0 && clean.lastCommit != nil && !clean.isWorktree && clean.active(), "git activity reads the branch, a fresh commit and a clean tree")
        try Data("two".utf8).write(to: repo.appendingPathComponent("file.txt"))
        check(readProjectActivity(repo.path).uncommitted == 1, "uncommitted changes are counted")
        git(["worktree", "add", "-q", "-b", "feature", tree.path])
        let worktree = readProjectActivity(tree.path)
        check(worktree.isWorktree && worktree.registered == true && worktree.merged == true && worktree.mainRepository == repo.path && worktree.branch == "feature",
              "a worktree is recognized, with its main repository and merge state")
        check(repositoryRoot(for: tree.path + "/build/intermediates", home: root.path) == tree.path && repositoryRoot(for: root.path + "/elsewhere", home: root.path) == nil, "a folder finds its project by looking for .git above it")
        print("SUCCESS: \(count) discovery/model checks. Preserved fixture: \(root.path)")
    }
}
