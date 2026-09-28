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
