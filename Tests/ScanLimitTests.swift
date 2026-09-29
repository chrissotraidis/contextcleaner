import Foundation
import Darwin

@main struct ScanLimitTests {
    static func main() throws {
        var count = 0
        func check(_ okay: Bool, _ message: String) { precondition(okay, message); count += 1; print("PASS " + message) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let wide = root.appendingPathComponent("wide")
        try FileManager.default.createDirectory(at: wide, withIntermediateDirectories: true)
        for index in (0..<520).reversed() { try writeNew(Data([UInt8(index % 255)]), to: wide.appendingPathComponent(String(format: "%04d.bin", index))) }
        let original = try Data(contentsOf: wide.appendingPathComponent("0000.bin"))
        let profile = Classifier.profile(path: wide.path, home: root.path)
        func measure(_ limits: ScanLimits, prefs: Preferences = Preferences(), token: Cancellation = Cancellation()) -> FolderMeasurement {
            TreeMeasure.measure(profile, preferences: prefs, cancellation: token, activity: [], activityAvailable: false, limits: limits)
        }
        let full = measure(.manual)
        check(full.state == .measured && full.fileCount == 520, "streaming traversal completely measures a wide folder")
        check(full.contents?.listedChildren == 520 && full.contents?.children.count == 512, "child retention is bounded independently of traversal width")
        let expectedNames = Set((0..<512).map { String(format: "%04d.bin", $0) })
        check(Set(full.contents!.children.map(\.name)) == expectedNames, "retained child names are the alphabetically first 512 regardless of enumeration order")
        let limited = measure(ScanLimits(seconds: 120, entries: 10))
        check(limited.state == .limited && limited.allocatedBytes == nil && limited.logicalBytes == nil && limited.contents == nil, "entry limit never publishes a partial size or detail as complete")
        check(limited.diagnostic?.contains("Entry allowance") == true, "entry-limit reason is actionable")
        check(measure(ScanLimits(seconds: 0, entries: 1000)).state == .limited, "expired time allowance stops before traversal")
        let token = Cancellation(); token.cancel()
        check(measure(.manual, token: token).state == .cancelled, "cancellation is distinct from an allowance limit")
        let nested = root.appendingPathComponent("deep/a/b/c")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeNew(Data([1]), to: nested.appendingPathComponent("keep"))
        let deepProfile = Classifier.profile(path: root.appendingPathComponent("deep").path, home: root.path)
        let deep = TreeMeasure.measure(deepProfile, preferences: Preferences(), cancellation: Cancellation(), activity: [], activityAvailable: false, limits: ScanLimits(seconds: 120, entries: 100, depth: 2))
        check(deep.state == .limited && deep.diagnostic?.contains("depth") == true, "deep trees respect the directory-handle bound")
        let before = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        for _ in 0..<30 { _ = measure(ScanLimits(seconds: 120, entries: 3)) }
        let after = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        check(after <= before + 1, "early returns close directory handles without descriptor growth")
        let listing = DirectoryListing.read(wide.path, preferences: Preferences(), limit: 7)
        check(listing.names.count == 7 && !listing.complete && listing.note != nil, "wide-directory listing marks its bounded result incomplete")
        let completeListing = DirectoryListing.read(wide.path, preferences: Preferences(), limit: 1000)
        check(completeListing.complete && completeListing.names.count == 520, "complete directory listing retains all included names")
        var excluded = Preferences(); excluded.locations[wide.path] = LocationPolicy(excluded: true)
        check(DirectoryListing.read(wide.path, preferences: excluded).names.isEmpty, "listing refuses an excluded root")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: wide)
        check(!DirectoryListing.read(alias.path, preferences: Preferences()).complete, "bounded listing refuses symbolic-link roots")
        let date = Date()
        func record(_ item: FolderMeasurement, at: Date) -> ScanRecord {
            var item = item; item.observedAt = at
            return ScanRecord(id: UUID().uuidString, startedAt: at, finishedAt: at, scope: "fixture", complete: item.state == .measured, measurements: [item], discoveryNotes: [])
        }
        let history = [record(full, at: date), record(limited, at: date.addingTimeInterval(60)), record(full, at: date.addingTimeInterval(120))]
        check(growth(wide.path, records: history).delta == nil, "a limited observation breaks growth comparisons")
        let store = try AppendStore(root: root.appendingPathComponent("records"))
        for record in history { try store.append(record) }
        check(store.records().count == 3 && store.records()[1].measurements[0].state == .limited, "limited attempts survive append-only roundtrip")
        let early = ActivitySnapshot.capture(cancellation: token)
        check(!early.available && early.observations.isEmpty, "pre-cancelled activity lookup returns without a helper")
        let stopped = ScanEngine.scan(profiles: [profile], preferences: Preferences(), scope: "cancel fixture", notes: [], cancellation: token) { _,_,_ in preconditionFailure("Cancelled engine cannot deliver a measurement") }
        check(!stopped.complete && stopped.measurements.isEmpty && stopped.requestedCount == 1 && stopped.stopReason == "Cancelled by you", "cancelled pass preserves requested coverage and explicit stop reason")
        let stoppedParallel = ScanEngine.scan(profiles: [profile, deepProfile], preferences: Preferences(), scope: "cancel fixture", notes: [], cancellation: token, concurrency: 4) { _,_,_ in preconditionFailure("Cancelled engine cannot deliver a measurement") }
        check(stoppedParallel.measurements.isEmpty && stoppedParallel.stopReason == "Cancelled by you", "a cancelled parallel pass delivers nothing")
        let folders = ["wide", "deep", "deep/a", "deep/a/b", "deep/a/b/c"].map { Classifier.profile(path: root.appendingPathComponent($0).path, home: root.path) }
        let serial = ScanEngine.scan(profiles: folders, preferences: Preferences(), scope: "serial", notes: [], cancellation: Cancellation(), concurrency: 1) { _,_,_ in }
        let deliveries = NSLock(); var delivered = 0, highest = 0
        let parallel = ScanEngine.scan(profiles: folders, preferences: Preferences(), scope: "parallel", notes: [], cancellation: Cancellation(), concurrency: 4) { _, done, _ in
            deliveries.lock(); delivered += 1; highest = max(highest, done); deliveries.unlock()
        }
        check(parallel.measurements.map(\.profile.path) == folders.map(\.path) && zip(serial.measurements, parallel.measurements).allSatisfy { $0.allocatedBytes == $1.allocatedBytes && $0.fileCount == $1.fileCount && $0.state == $1.state },
              "four workers measure the same sizes as one, reported in list order")
        check(delivered == folders.count && highest == folders.count && parallel.complete, "each folder is reported once and the pass completes")
        var preferences = Preferences(); preferences.dailyWhileOpen = true
        check(ScanPlanner.dailyDue(preferences, now: date), "first enabled daily attempt is due")
        preferences.lastScheduledAttempt = date
        check(!ScanPlanner.dailyDue(preferences, now: date.addingTimeInterval(300)), "failed or incomplete daily attempt does not spin every five minutes")
        check(ScanPlanner.dailyDue(preferences, now: date.addingTimeInterval(86400)), "daily attempts resume after their actual interval")
        preferences.dailyWhileOpen = false
        check(!ScanPlanner.dailyDue(preferences, now: date.addingTimeInterval(172800)), "disabled scheduling stays disabled")
        check(try Data(contentsOf: wide.appendingPathComponent("0000.bin")) == original && FileManager.default.fileExists(atPath: nested.appendingPathComponent("keep").path), "all fixture payloads remain intact")
        let denied = root.appendingPathComponent("denied-fixture")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try writeNew(Data("Preserve even during denied access test".utf8), to: denied.appendingPathComponent("keep.txt"))
        let permissionProfile = Classifier.profile(path: denied.path, home: root.path, readMetadata: false)
        guard chmod(denied.path, 0) == 0 else { preconditionFailure("Cannot prepare own permission fixture") }
        let permissionResult = TreeMeasure.measure(permissionProfile, preferences: Preferences(), cancellation: Cancellation(), activity: [], activityAvailable: false)
        let listingResult = DirectoryListing.read(denied.path, preferences: Preferences())
        guard chmod(denied.path, 0o700) == 0 else { preconditionFailure("Cannot restore own fixture permissions") }
        check(permissionResult.state == .inaccessible && permissionResult.allocatedBytes == nil, "permission-denied traversal withholds its partial total")
        check(!listingResult.complete && listingResult.names.isEmpty, "permission-denied listing is explicitly incomplete")
        check(try Data(contentsOf: denied.appendingPathComponent("keep.txt")) == Data("Preserve even during denied access test".utf8), "permission fixture is restored with its original payload")
        print("SUCCESS: \(count) bounded-scan checks. Preserved fixture: \(root.path)")
    }
}
