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
        check(freeSpaceWindow(at: start.addingTimeInterval(60), calendar: calendar) == freeSpaceWindow(at: start.addingTimeInterval(40_000), calendar: calendar), "redraws within a calendar day retain the exact time axis")
        let window = freeSpaceWindow(at: start, calendar: calendar)
        check(window.upperBound.timeIntervalSince(window.lowerBound) == 7 * 86400, "free-space chart covers seven complete calendar days")
        let gib: Int64 = 1_073_741_824
        let axis = freeSpaceRange([200*gib, 240*gib])
        check(freeSpaceRange([220*gib], preserving: axis) == axis, "new points inside the axis cannot shrink or shift it")
        let expanded = freeSpaceRange([100*gib], preserving: axis)
        check(expanded.lowerBound < axis.lowerBound && expanded.upperBound == axis.upperBound, "out-of-range observations expand only the necessary bound")
        check(freeSpaceRange([], preserving: axis) == axis, "missing observations cannot reset the axis")
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
        let readings = freeSpaceReadings([sampleB, sampleA], current: live)
        check(readings.map(\.bytes) == [250*gib,220*gib,125*gib] && readings.last!.isCurrent, "chart includes the same latest capacity reading as the storage card")
        check(readingTimeRange(readings).lowerBound < start && readingTimeRange(readings).upperBound > live.date, "time bounds include both endpoint readings with visible padding")
        check(readingTimeRange(readings).upperBound.timeIntervalSince(readingTimeRange(readings).lowerBound) < 3*3600, "a few hours of readings are not compressed into an empty week")
        sampleA.finishedAt = start.addingTimeInterval(-8*86400)
        check(freeSpaceReadings([sampleA, sampleB], current: live).count == 2, "free-space history retains only readings in its recent window")
        sampleB.finishedAt = live.date
        check(freeSpaceReadings([sampleB], current: live).count == 1, "current reading replaces a duplicate timestamp")
        check(freeSpaceReadings([], current: nil).isEmpty, "empty history never invents a reading")
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
