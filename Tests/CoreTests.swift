import Foundation
import Darwin

@main struct CoreTests {
    static var checks = 0
    static func check(_ value: Bool, _ description: String) {
        precondition(value, description); checks += 1; print("PASS \(description)")
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        print("Preserved fixture: \(root.path)")
        let store = try AppendStore(root: root.appendingPathComponent("store"))
        let home = root.appendingPathComponent("home")
        let cache = home.appendingPathComponent(".npm/_cacache")
        let excluded = cache.appendingPathComponent("keep")
        try fm.createDirectory(at: excluded, withIntermediateDirectories: true)
        try writeNew(Data(repeating: 71, count: 1_048_576), to: cache.appendingPathComponent("first"))
        try writeNew(Data(repeating: 72, count: 2_097_152), to: excluded.appendingPathComponent("unique"))
        let original = try Data(contentsOf: excluded.appendingPathComponent("unique"))
        do { try writeNew(Data("replace".utf8), to: excluded.appendingPathComponent("unique")); preconditionFailure("Existing files must not be replaced") }
        catch StoreError.exists { }
        check(try! Data(contentsOf: excluded.appendingPathComponent("unique")) == original, "existing file remains byte-identical")
        var prefs = Preferences(); prefs.locations[excluded.path] = LocationPolicy(excluded: true)
        try store.save(prefs)
        prefs.locations[cache.path] = LocationPolicy(watched: true, recurring: true, expected: true, tags: ["Builds"], note: "Keep current toolchain")
        try store.save(prefs)
        check(try fm.contentsOfDirectory(atPath: store.root.appendingPathComponent("preferences").path).count == 2, "preferences append instead of replacing old state")
        check(store.preferences().policy(cache.path).tags == ["Builds"], "tags survive store reload")
        check(store.preferences().excluded(excluded.appendingPathComponent("unique").path), "descendant exclusion applies")
        check(!store.preferences().excluded(cache.appendingPathComponent("keeper").path), "exclusion respects path component boundary")
        let profile = Classifier.profile(path: cache.path, home: home.path)
        check(profile.category == .packageCache && profile.associatedApp == "npm", "package attribution is identified")
        check(profile.evidence.contains { $0.label == "Historical writer" && $0.level == .unknown }, "historical writer is explicitly unknown")
        let start = Date()
        var first = TreeMeasure.measure(profile, preferences: prefs, cancellation: Cancellation(), activity: [], activityAvailable: true)
        check(first.state == .measured && first.fileCount == 1, "excluded descendants are omitted from measurement")
        let excludedProfile = Classifier.profile(path: excluded.path, home: home.path)
        check(TreeMeasure.measure(excludedProfile, preferences: prefs, cancellation: Cancellation(), activity: [], activityAvailable: true).state == .excluded, "direct scan cannot bypass exclusion")
        try fm.createSymbolicLink(at: cache.appendingPathComponent("alias"), withDestinationURL: excluded)
        var afterAlias = TreeMeasure.measure(profile, preferences: prefs, cancellation: Cancellation(), activity: [], activityAvailable: true)
        check(afterAlias.fileCount == 1, "symlink does not bypass excluded subtree")
        try writeNew(Data(repeating: 73, count: 1_048_576), to: cache.appendingPathComponent("second"))
        var second = TreeMeasure.measure(profile, preferences: prefs, cancellation: Cancellation(), activity: [], activityAvailable: true)
        check(second.fileCount == 2 && second.allocatedBytes! > first.allocatedBytes!, "allocated growth is measured")
        first.observedAt = start; second.observedAt = start.addingTimeInterval(86400)
        let a = ScanRecord(id: UUID().uuidString, startedAt: start, finishedAt: start, scope: "fixture", complete: true, measurements: [first], discoveryNotes: [])
        let b = ScanRecord(id: UUID().uuidString, startedAt: second.observedAt, finishedAt: second.observedAt, scope: "fixture", complete: true, measurements: [second], discoveryNotes: [])
        try store.append(a); try store.append(b)
        check(growth(cache.path, records: store.records()).delta! > 0, "two real measurements produce growth")
        check(growth(cache.path, records: store.records()).interval == 86400, "growth rate uses actual observation interval")
        var changedScope = second; changedScope.scopeID = "other exclusions"
        var c = b; c.id = UUID().uuidString; c.measurements = [changedScope]
        check(growth(cache.path, records: [a,c]).delta == nil, "scope changes do not fabricate growth")
        var missing = second; missing.state = .missing; missing.allocatedBytes = nil
        c.measurements = [missing]
        check(growth(cache.path, records: [a,c]).delta == nil, "missing observation is not zero-sized cleanup")
        afterAlias.profile.path = cache.appendingPathComponent("child").path
        check(uniqueAllocatedTotal([first,afterAlias]) == first.allocatedBytes, "nested totals are not double counted")
        let cancel = Cancellation(); cancel.cancel()
        check(TreeMeasure.measure(profile, preferences: prefs, cancellation: cancel, activity: [], activityAvailable: true).state == .cancelled, "cancel does not return an apparently complete total")
        let parsed = ActivitySnapshot.parse("p123\ncjava\nf20\nau\nn\(cache.path)/first\np456\ncFinder\nf2\nar\nn/elsewhere\n")
        check(parsed.count == 2 && parsed[0].command == "java" && parsed[0].access == "read/write-capable handle", "process identity and handle mode are retained without write claim")
        let simulator = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/TEST")
        try fm.createDirectory(at: simulator, withIntermediateDirectories: true)
        try writeNew(PropertyListSerialization.data(fromPropertyList: ["name":"Fixture iPhone", "runtime":"iOS-fixture", "state":1], format: .xml, options: 0), to: simulator.appendingPathComponent("device.plist"))
        let sim = Classifier.profile(path: simulator.path, home: home.path)
        check(sim.name == "Fixture iPhone" && sim.category == .simulator, "simulator UUID becomes observed device name")
        let noReadSim = Classifier.profile(path: simulator.path, home: home.path, readMetadata: false)
        check(noReadSim.name == "Simulator data" && !noReadSim.evidence.contains { $0.label == "Device name" }, "saved and excluded path classification can avoid filesystem metadata reads")
        check(byteLabel(1_073_741_824) == "1 GiB" && byteLabel(0) == "0 B", "binary sizes have explicit units and zero is numeric")
        let mixed = Classifier.profile(path: home.path + "/.codex/worktrees/game/build", home: home.path)
        check(mixed.category == .workspace && !mixed.category.reproducible, "generic build folder stays mixed, not disposable")
        let legacy = LegacySnapshot(date: start, freeBytes: 123, items: [LegacyItem(path: cache.path, name: "Old", kind: "Rebuildable", reason: "old", bytes: 2000, active: true)])
        let legacyURL = root.appendingPathComponent("history-original.json")
        let legacyData = try JSONEncoder().encode([legacy]); try writeNew(legacyData, to: legacyURL)
        check(try store.importLegacy(legacyURL, home: home.path) == 1, "legacy history imports")
        check(try store.importLegacy(legacyURL, home: home.path) == 0, "repeat import is idempotent")
        check(try Data(contentsOf: legacyURL) == legacyData, "legacy source remains byte-identical")
        check(store.records().contains { $0.legacySource != nil && !$0.measurements[0].activityCheckAvailable }, "legacy process evidence is not invented")
        let discovery = Inventory.discover(home: home.path, preferences: prefs)
        check(!discovery.profiles.contains { containsPath(excluded.path, $0.path) }, "discovery honors exclusions")
        check(try Data(contentsOf: excluded.appendingPathComponent("unique")) == original, "all scan and migration tests preserve original fixture data")
        check(terminalApps.first?.id == "com.apple.Terminal" && terminalApps.contains { $0.id == "com.mitchellh.ghostty" && $0.name == "Ghostty" }, "Terminal is the default and Ghostty is offered")
        check(chosenTerminal("com.mitchellh.ghostty", installed: { _ in true }).name == "Ghostty" && chosenTerminal("com.mitchellh.ghostty", installed: { $0 == "com.apple.Terminal" }).name == "Terminal"
              && chosenTerminal(nil, installed: { _ in true }).name == "Terminal" && chosenTerminal("com.example.unknown", installed: { _ in true }).name == "Terminal",
              "the chosen terminal is used while installed; otherwise, or if unknown, Terminal")
        print("SUCCESS: \(checks) non-destructive checks. Every fixture and previous record remains at \(root.path)")
    }
}
