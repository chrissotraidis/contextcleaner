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
        reloaded.section = .needsAttention
        check(reloaded.rows.count == 3, "unmeasured locations are discoverable in Needs Attention")
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
        print("SUCCESS: \(count) discovery/model checks. Preserved fixture: \(root.path)")
    }
}
