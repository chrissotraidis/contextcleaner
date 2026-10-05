import Foundation
@main struct PlannerTests {
    static func main() {
        var count = 0
        func check(_ okay: Bool, _ message: String) { precondition(okay, message); count += 1; print("PASS " + message) }
        let now = Date(timeIntervalSince1970: 1_000_000), home = "/fixture"
        let profiles = (0..<20).map { Classifier.profile(path: home + "/folder\($0)", home: home, readMetadata: false) }
        let measured = profiles.map { FolderMeasurement(profile: $0, observedAt: now.addingTimeInterval(-86400), state: .measured, allocatedBytes: 100, fileCount: 1, processes: [], activityCheckAvailable: true, elapsedSeconds: 1) }
        var records = [ScanRecord(id: "baseline", startedAt: now.addingTimeInterval(-86400), finishedAt: now.addingTimeInterval(-86400), scope: "synthetic planner test", complete: true, measurements: measured, discoveryNotes: [])]
        var prefs = Preferences(); prefs.locations[profiles[15].path] = LocationPolicy(watched: true)
        check(ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now).count == 12, "priority pass limits selected roots")
        check(ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now).first?.path == profiles[15].path, "watch status prioritizes equally old observations")
        prefs.locations[profiles[15].path]!.excluded = true
        check(!ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now).contains { $0.path == profiles[15].path }, "priority pass respects exclusion")
        prefs.locations[profiles[0].path] = LocationPolicy(reviewAfter: now.addingTimeInterval(3600))
        check(!ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now).contains { $0.path == profiles[0].path }, "review later postpones priority checks")
        var grown = measured[13]; grown.observedAt = now.addingTimeInterval(-43200); grown.allocatedBytes = 1000
        records.append(ScanRecord(id: "growth", startedAt: grown.observedAt, finishedAt: grown.observedAt, scope: "synthetic", complete: true, measurements: [grown], discoveryNotes: []))
        check(ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now).first?.path == profiles[13].path, "measured growth prioritizes a location")
        var failure = grown; failure.observedAt = now; failure.state = .inaccessible; failure.allocatedBytes = nil
        records.append(ScanRecord(id: "failure", startedAt: now, finishedAt: now, scope: "synthetic", complete: true, measurements: [failure], discoveryNotes: []))
        check(ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now).first?.path != profiles[13].path, "recent permission failure does not monopolize repeated checks")
        check(ScanPlanner.discoveryDue(prefs, now: now), "no discovery date makes discovery due")
        prefs.lastDiscovery = now.addingTimeInterval(-6*86400)
        check(!ScanPlanner.discoveryDue(prefs, now: now), "discovery is not repeated before seven days")
        prefs.lastDiscovery = now.addingTimeInterval(-7*86400)
        check(ScanPlanner.discoveryDue(prefs, now: now), "periodic rediscovery becomes due after seven days")
        check(ScanPlanner.priority(profiles + profiles, preferences: prefs, records: records, now: now, limit: 100).count == 18, "duplicate roots are not scheduled twice")
        let parent = Classifier.profile(path: "/fixture/parent", home: home, readMetadata: false)
        let child = Classifier.profile(path: "/fixture/parent/child", home: home, readMetadata: false)
        let neighbor = Classifier.profile(path: "/fixture/parent2", home: home, readMetadata: false)
        check(ScanPlanner.priority([parent, child, neighbor], preferences: Preferences(), records: [], now: now).count == 2, "priority pass avoids overlapping ancestor and child scans without dropping neighbors")
        var schedule = Preferences()
        check(!ScanPlanner.dailyDue(schedule, now: now), "no schedule means no scheduled pass")
        schedule.schedule = "weekly"; schedule.lastScheduledAttempt = now.addingTimeInterval(-3 * 86400)
        check(!ScanPlanner.dailyDue(schedule, now: now), "weekly schedule is not due after three days")
        schedule.lastScheduledAttempt = now.addingTimeInterval(-8 * 86400)
        check(ScanPlanner.dailyDue(schedule, now: now), "weekly schedule is due after eight days")
        schedule.schedule = nil; schedule.dailyWhileOpen = true; schedule.lastScheduledAttempt = now.addingTimeInterval(-2 * 86400)
        check(schedule.effectiveSchedule == "daily" && ScanPlanner.dailyDue(schedule, now: now), "legacy daily preference still maps to a daily schedule")
        schedule.priorityCount = 1000; schedule.perLocationSeconds = 1; schedule.perLocationEntries = 1
        check(schedule.effectivePriorityCount == 48 && schedule.manualLimits.seconds == 30 && schedule.manualLimits.entries == 100_000, "allowances are clamped to safe bounds")
        check(ScanPlanner.priority(profiles, preferences: prefs, records: records, now: now, limit: 4).count == 4, "priority pass honors a configured location count")
        var recurring = Preferences(); recurring.locations[profiles[15].path] = LocationPolicy(recurring: true)
        check(ScanPlanner.priority(profiles, preferences: recurring, records: [records[0]], now: now).first?.path == profiles[15].path, "legacy Recurring locations receive Watching priority")
        recurring.locations[profiles[15].path]!.isWatched = false
        check(ScanPlanner.priority(profiles, preferences: recurring, records: [records[0]], now: now).first?.path != profiles[15].path, "Stop Watching removes legacy scheduling priority")
        var nextSchedule = Preferences(); nextSchedule.schedule = "daily"; nextSchedule.lastScheduledAttempt = now
        check(ScanPlanner.nextCheck(nextSchedule) == now.addingTimeInterval(86400) && ScanPlanner.dailyDue(nextSchedule, now: now.addingTimeInterval(86400)) && !ScanPlanner.dailyDue(nextSchedule, now: now.addingTimeInterval(3600)),
              "a daily check is due a day after the last one, not before")
        var weekly = nextSchedule; weekly.schedule = "weekly"
        check(ScanPlanner.nextCheck(weekly) == now.addingTimeInterval(7 * 86400) && ScanPlanner.nextCheck(Preferences()) == nil, "a weekly check waits a week; none when checks are off")
        print("SUCCESS: \(count) planner checks; no filesystem mutations.")
    }
}
