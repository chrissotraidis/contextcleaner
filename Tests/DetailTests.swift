import Foundation

@main struct DetailTests {
    static var count = 0
    static func check(_ value: Bool, _ note: String) { precondition(value,note); count += 1; print("PASS " + note) }
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        let root = base.appendingPathComponent("files")
        try fm.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let payload = Data(repeating: 97, count: 8_192)
        try writeNew(payload, to: root.appendingPathComponent("nested/first.log"))
        try writeNew(payload, to: root.appendingPathComponent("root.txt"))
        let profile = Classifier.profile(path: root.path, home: base.path)
        var a = TreeMeasure.measure(profile, preferences: Preferences(), cancellation: Cancellation(), activity: [], activityAvailable: true)
        check(a.contents?.children.count == 2, "immediate children are captured in the original traversal")
        check(a.contents?.children.first { $0.name == "nested" }?.files == 1, "nested bytes and counts aggregate beneath immediate child")
        check(a.contents?.fileTypes.first { $0.kind == ".log" }?.files == 1, "file extensions summarized without payload reads")
        check(a.contents?.exhaustive == true, "complete small-directory scope is explicit")
        try writeNew(payload, to: root.appendingPathComponent("nested/second.log"))
        try writeNew(payload, to: root.appendingPathComponent("new.dat"))
        var b = TreeMeasure.measure(profile, preferences: Preferences(), cancellation: Cancellation(), activity: [], activityAvailable: true)
        a.observedAt = Date(timeIntervalSince1970: 100); b.observedAt = Date(timeIntervalSince1970: 200)
        func record(_ m: FolderMeasurement) -> ScanRecord { ScanRecord(id: UUID().uuidString, startedAt: m.observedAt, finishedAt: m.observedAt, scope: "explicit fixture", complete: true, measurements: [m], discoveryNotes: []) }
        let changes = childChanges(root.path, records: [record(a),record(b)])!
        check(changes.contains { $0.name == "nested" && ($0.delta ?? 0) > 0 }, "real appended child output is measured as growth")
        check(changes.contains { $0.name == "new.dat" && $0.event == "Newly observed" }, "newly observed child is distinct from byte growth")
        var limited = a; limited.contents!.listedChildren = 513
        check(childChanges(root.path, records: [record(limited),record(b)])!.contains { $0.name == "new.dat" && $0.event == "Not in previous retained detail" }, "truncated history cannot claim a new child")
        var omitted = b; omitted.contents!.children = omitted.contents!.children.filter { $0.name != "root.txt" }
        check(childChanges(root.path, records: [record(a),record(omitted)])!.contains { $0.name == "root.txt" && $0.event == "No longer observed; cause unknown" }, "synthetic absence never claims deletion")
        var renamed = a; renamed.observedAt = b.observedAt
        renamed.contents!.children[0].name = "renamed-fixture"
        check(childChanges(root.path, records: [record(a),record(renamed)])!.contains { $0.event.hasPrefix("Possible rename") }, "synthetic identity match is labeled possible rename only")
        var failed = b; failed.state = .inaccessible
        check(childChanges(root.path, records: [record(a),record(failed)]) == nil, "failed measurement cannot fabricate child changes")
        var scoped = b; scoped.scopeID = "changed scope"
        check(childChanges(root.path, records: [record(a),record(scoped)]) == nil, "different exclusions cannot fabricate child changes")
        let store = try AppendStore(root: base.appendingPathComponent("store")); try store.append(record(b))
        check(store.records().first?.measurements.first?.contents?.children.count == 3, "detail survives append-only history roundtrip")
        let device = base.appendingPathComponent("Library/Developer/CoreSimulator/Devices/FIXTURE")
        let container = device.appendingPathComponent("data/Containers/Data/Application/UUID")
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        let plistURL = container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        let metadata = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "example.fixture.game"], format: .binary, options: 0)
        try writeNew(metadata, to: plistURL)
        let sim = Classifier.profile(path: container.path, home: base.path)
        check(sim.name == "example.fixture.game · app data", "simulator data UUID resolves to observed app identifier")
        check(sim.evidence.contains { $0.label == "Container identifier" && $0.level == .observed }, "container identity retains exact metadata evidence")
        try writeNew(PropertyListSerialization.data(fromPropertyList: ["name": "Fixture Test iPad", "runtime": "fixture-runtime"], format: .binary, options: 0), to: device.appendingPathComponent("device.plist"))
        let linkedDevice = Classifier.profile(path: container.path, home: base.path)
        check(linkedDevice.evidence.contains { $0.label == "Device name" && $0.value == "Fixture Test iPad" && $0.level == .observed }, "container retains its observed parent device identity")
        var deviceExcluded = Preferences(); deviceExcluded.locations[device.appendingPathComponent("device.plist").path] = LocationPolicy(excluded: true)
        check(!Classifier.profile(path: container.path, home: base.path, preferences: deviceExcluded).evidence.contains { $0.label == "Device name" }, "device identity respects excluded parent metadata")

        check(sim.evidence.contains { $0.label == "Historical writer" && $0.level == .unknown }, "container identity is not promoted to writer proof")
        var prefs = Preferences(); prefs.locations[plistURL.path] = LocationPolicy(excluded: true)
        check(Classifier.profile(path: container.path, home: base.path, preferences: prefs).associatedApp == "Apple CoreSimulator", "excluded metadata is not read for attribution")
        prefs.locations[container.path] = LocationPolicy(excluded: true)
        check(try SimulatorLocations.containers(device.path, preferences: prefs).isEmpty, "simulator discovery respects excluded container")
        let alias = base.appendingPathComponent("metadata-alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: plistURL)
        check(MetadataReader.data(alias.path, preferences: Preferences()) == nil, "metadata reader refuses symlink files")
        let parentAlias = base.appendingPathComponent("parent-alias")
        try fm.createSymbolicLink(at: parentAlias, withDestinationURL: root)
        let aliasProfile = Classifier.profile(path: parentAlias.appendingPathComponent("nested").path, home: base.path, readMetadata: false)
        check(TreeMeasure.measure(aliasProfile, preferences: Preferences(), cancellation: Cancellation(), activity: [], activityAvailable: false).state == .excluded, "scan cannot traverse a symbolic-link ancestor")
        check(try Data(contentsOf: plistURL) == metadata && Data(contentsOf: root.appendingPathComponent("nested/first.log")) == payload, "original metadata and payload remain byte-identical")
        print("SUCCESS: \(count) detail checks; all fixtures preserved at \(base.path)")
    }
}
