import Foundation

/// One disk-capacity reading: a timestamp and two numbers. Reads no folders.
struct CapacityReading: Codable, Equatable { var date: Date; var total: Int64; var free: Int64 }
struct VolumeSnapshot {
    let date: Date
    let total: Int64
    let free: Int64
    var used: Int64 { max(0, total - free) }
    static func read() -> VolumeSnapshot? {
        guard let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = (a[.systemSize] as? NSNumber)?.int64Value,
              let free = (a[.systemFreeSize] as? NSNumber)?.int64Value, total > 0 else { return nil }
        return VolumeSnapshot(date: Date(), total: total, free: min(max(0, free), total))
    }
}
struct StorageGroup: Identifiable {
    let category: FolderCategory
    let bytes: Int64
    let count: Int
    var id: String { category.rawValue }
}
// Keep parents and descendants out of the same sum. These are saved observations,
// not a live whole-volume accounting and not a promise of reclaimable space.
func overviewGroups(_ measurements: [FolderMeasurement], preferences: Preferences) -> [StorageGroup] {
    var accepted: Set<String> = [], totals: [FolderCategory: (Int64, Int)] = [:]
    for item in measurements.sorted(by: { $0.profile.path.count == $1.profile.path.count ? $0.profile.path < $1.profile.path : $0.profile.path.count < $1.profile.path.count }) {
        let path = normalized(item.profile.path)
        guard item.state == .measured, let bytes = item.allocatedBytes, !preferences.excluded(item.profile.path),
              !hasAncestor(in: accepted, path) else { continue }
        accepted.insert(path)
        let old = totals[item.profile.category] ?? (0, 0)
        totals[item.profile.category] = (old.0 + bytes, old.1 + 1)
    }
    return totals.map { StorageGroup(category: $0.key, bytes: $0.value.0, count: $0.value.1) }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
}

/// A point on the "Space used" chart. Scan records and hourly capacity readings both contribute.
struct UsageReading: Identifiable, Equatable {
    let id: String
    let date: Date
    let used: Int64
    let total: Int64
    let isCurrent: Bool
    var free: Int64 { max(0, total - used) }
}
/// Combines scan-time free space, hourly capacity readings and the live reading.
/// Nothing is interpolated; one reading per timestamp, preferring the live one.
func usageReadings(records: [ScanRecord], capacity: [CapacityReading], current: VolumeSnapshot?) -> [UsageReading] {
    let fallbackTotal = current?.total ?? capacity.last?.total
    var points: [UsageReading] = []
    for (index, reading) in capacity.enumerated() where reading.total > 0 {
        points.append(UsageReading(id: "capacity-\(index)", date: reading.date, used: reading.total - min(max(0, reading.free), reading.total), total: reading.total, isCurrent: false))
    }
    if let fallbackTotal {
        for record in records {
            guard let free = record.freeBytes, free >= 0 else { continue }
            let total = capacity.last(where: { $0.date <= record.finishedAt })?.total ?? fallbackTotal
            points.append(UsageReading(id: "scan-" + record.id, date: record.finishedAt, used: total - min(free, total), total: total, isCurrent: false))
        }
    }
    if let current { points.append(UsageReading(id: "current", date: current.date, used: current.used, total: current.total, isCurrent: true)) }
    var unique: [UsageReading] = []
    for point in points.sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) {
        if let last = unique.last, abs(point.date.timeIntervalSince(last.date)) < 1 {
            if point.isCurrent { unique[unique.count - 1] = point }
            continue
        }
        unique.append(point)
    }
    return unique
}
/// Chart ranges. Windows are calendar-aligned so redraws never move the axis.
enum UsageRange: String, CaseIterable, Identifiable {
    case day = "24 hours", week = "7 days", month = "30 days"
    var id: String { rawValue }
    var bucket: Calendar.Component { self == .day ? .hour : .day }
    var bucketName: String { self == .day ? "hour" : "day" }
    /// Longest interval between readings that still draws a connected line. Longer gaps stay gaps.
    var gapLimit: TimeInterval {
        switch self {
        case .day: return 3 * 3600
        case .week: return 30 * 3600
        case .month: return 3 * 86400
        }
    }
    var phrase: String {
        switch self {
        case .day: return "in the last 24 hours"
        case .week: return "in the last 7 days"
        case .month: return "in the last 30 days"
        }
    }
    func window(endingAt latest: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        if self == .day {
            let end = calendar.dateInterval(of: .hour, for: latest)?.end ?? latest
            return end.addingTimeInterval(-86400)...end
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest))!
        return calendar.date(byAdding: .day, value: self == .week ? -7 : -30, to: end)!...end
    }
}
struct UsagePoint: Identifiable {
    let reading: UsageReading
    let segment: Int
    var id: String { reading.id }
}
/// Readings inside the window. A new segment starts after any gap longer than the limit.
func usageSeries(_ readings: [UsageReading], in window: ClosedRange<Date>, gapLimit: TimeInterval) -> [UsagePoint] {
    var points: [UsagePoint] = [], segment = 0, previous: Date?
    for reading in readings where window.contains(reading.date) {
        if let previous, reading.date.timeIntervalSince(previous) > gapLimit { segment += 1 }
        points.append(UsagePoint(reading: reading, segment: segment)); previous = reading.date
    }
    return points
}
struct UsageChange {
    let from: UsageReading
    let to: UsageReading
    var delta: Int64 { to.used - from.used }
}
/// Change in used space between the first and last readings inside a span.
func usageChange(_ readings: [UsageReading], from: Date, to: Date) -> UsageChange? {
    let inside = readings.filter { $0.date >= from && $0.date <= to }
    guard let first = inside.first, let last = inside.last, first.date < last.date else { return nil }
    return UsageChange(from: first, to: last)
}
struct UsageBucket: Identifiable {
    let start: Date
    let end: Date
    let delta: Int64?
    var id: Date { start }
}
/// Change per hour or day. Each bucket compares its last reading with the last reading before it began
/// (if that is no older than one bucket), otherwise with its own first reading. Empty buckets have no value.
func usageBuckets(_ readings: [UsageReading], window: ClosedRange<Date>, component: Calendar.Component, calendar: Calendar = .current) -> [UsageBucket] {
    var buckets: [UsageBucket] = [], start = window.lowerBound
    while start < window.upperBound, buckets.count < 800 {
        guard let end = calendar.date(byAdding: component, value: 1, to: start), end > start else { break }
        let inside = readings.filter { $0.date >= start && $0.date < end }
        var delta: Int64?
        if let last = inside.last {
            if let before = readings.last(where: { $0.date < start }), start.timeIntervalSince(before.date) <= end.timeIntervalSince(start) {
                delta = last.used - before.used
            } else if let first = inside.first, first.date < last.date {
                delta = last.used - first.used
            }
        }
        buckets.append(UsageBucket(start: start, end: end, delta: delta)); start = end
    }
    return buckets
}
/// Vertical axis in GiB. Always reaches capacity; starts low enough that recent change is visible.
func usageAxis(_ readings: [UsageReading]) -> ClosedRange<Double> {
    let gib = 1_073_741_824.0
    guard let total = readings.map(\.total).max(), total > 0, let minUsed = readings.map(\.used).min() else { return 0...1 }
    let capacity = Double(total) / gib, low = Double(minUsed) / gib
    let lower = max(0, low - max(2 * (capacity - low), capacity * 0.05))
    let step = niceStep((capacity - lower) / 4)
    return max(0, floor(lower / step) * step)...capacity
}
func niceStep(_ raw: Double) -> Double {
    guard raw > 0, raw.isFinite else { return 1 }
    let power = pow(10, floor(log10(raw))), m = raw / power
    return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * power
}
struct FolderGrowth: Identifiable {
    let path: String
    let name: String
    let category: FolderCategory
    let delta: Int64
    var id: String { path }
}
/// Scanned folders that grew inside a span. The baseline is the first comparable measurement in the span,
/// or one taken up to a day before it. Nested folders are counted once, under their outermost parent.
func folderGrowth(history: [String: [HistoryPoint]], profile: (String) -> FolderProfile?, from: Date, to: Date, limit: Int = 5) -> [FolderGrowth] {
    var found: [FolderGrowth] = []
    for (path, points) in history {
        let measured = points.filter { $0.state == .measured && $0.bytes != nil }
        guard let end = measured.last(where: { $0.date > from && $0.date <= to }) else { continue }
        let base = measured.last(where: { $0.date <= from && from.timeIntervalSince($0.date) <= 86400 })
            ?? measured.first(where: { $0.date >= from && $0.date < end.date })
        guard let base, base.scopeID == end.scopeID, let a = base.bytes, let b = end.bytes, b > a, let p = profile(path) else { continue }
        found.append(FolderGrowth(path: path, name: p.displayName, category: p.category, delta: b - a))
    }
    var accepted: [FolderGrowth] = []
    for item in found.sorted(by: { $0.path.count == $1.path.count ? $0.path < $1.path : $0.path.count < $1.path.count }) where !accepted.contains(where: { containsPath($0.path, item.path) }) {
        accepted.append(item)
    }
    return Array(accepted.sorted { $0.delta == $1.delta ? $0.path < $1.path : $0.delta > $1.delta }.prefix(limit))
}
/// The latest comparable run of measured sizes, for a sparkline. A scope change or failure starts a new run.
func sparklineValues(_ points: [HistoryPoint], limit: Int = 12) -> [Double] {
    var run: [HistoryPoint] = []
    for point in points where point.state != .cancelled {
        guard point.state == .measured, point.bytes != nil else { run = []; continue }
        if let last = run.last, last.scopeID != point.scopeID { run = [] }
        run.append(point)
    }
    return run.suffix(limit).map { Double($0.bytes!) }
}
/// One-line result shown after a scan finishes.
func scanOutcome(_ record: ScanRecord, grew: Int) -> String {
    let measured = record.measurements.filter { $0.state == .measured }.count
    let issues = record.measurements.filter { [.inaccessible, .limited, .missing, .failed].contains($0.state) }.count
    let target = record.requestedCount ?? record.measurements.count
    if !record.complete && record.wasStopped { return "Stopped after \(measured) of \(target) \(target == 1 ? "folder" : "folders")" }
    if measured == 0 && issues > 0 { return issues == 1 ? "1 folder couldn't be read" : "\(issues) folders couldn't be read" }
    var parts = [measured == 1 ? "Scanned 1 folder" : "Scanned \(measured) folders"]
    if grew > 0 { parts.append("\(grew) grew") }
    if issues > 0 { parts.append("\(issues) couldn't be read") }
    return parts.joined(separator: " · ")
}
extension ScanRecord {
    var folderSummary: String {
        if measurements.count == 1 { return measurements[0].profile.displayName }
        if scope.hasPrefix("Priority") { return "Scheduled folder check" }
        if scope == "Watched locations" { return "Watchlist scan" }
        if scope == "Immediate children" { return "Subfolder scan" }
        if scope == "Simulator apps and data" { return "Test device scan" }
        if legacySource != nil || scope.hasPrefix("Imported") { return "Imported folder scan" }
        return "Folder scan"
    }
    var resultSummary: String {
        let measured = measurements.filter { $0.state == .measured }.count
        let issues = measurements.filter { [.inaccessible, .limited, .missing, .failed].contains($0.state) }.count
        let target = requestedCount ?? measurements.count
        if !complete && wasStopped { return "Stopped · \(measured) of \(target) \(target == 1 ? "folder" : "folders") scanned" }
        if measured == 0 && issues > 0 { return issues == 1 ? "1 folder couldn't be read" : "\(issues) folders couldn't be read" }
        if issues > 0 { return "\(measured) scanned · \(issues) with issues" }
        return measured == 1 ? "1 folder scanned" : "\(measured) folders scanned"
    }
    /// True when the user stopped the scan, as opposed to folders that couldn't be read.
    var wasStopped: Bool {
        measurements.contains { $0.state == .cancelled } || measurements.count < (requestedCount ?? measurements.count)
    }
}


// MARK: - Can I remove it?

/// A plain answer for every folder. The app never acts on it; it tells you what you can do yourself.
enum Verdict: Int, Comparable, CaseIterable, Identifiable {
    case safe = 0, check = 1, keep = 2
    var id: Int { rawValue }
    static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }
    var title: String {
        switch self {
        case .safe: return "Safe to remove"
        case .check: return "Check first"
        case .keep: return "Keep"
        }
    }
}
/// A simulator as Xcode reports it (`xcrun simctl list devices -j`). Read-only.
struct SimDevice: Equatable {
    let udid: String
    let name: String
    let runtime: String
    let lastUsed: Date?
    let available: Bool
    let dataBytes: Int64?
}
func parseSimDevices(_ data: Data) -> [String: SimDevice] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let groups = root["devices"] as? [String: [[String: Any]]] else { return [:] }
    let iso = ISO8601DateFormatter()
    var out: [String: SimDevice] = [:]
    for (runtime, devices) in groups {
        let pretty = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "").replacingOccurrences(of: "-", with: " ")
        for device in devices {
            guard let udid = device["udid"] as? String else { continue }
            out[udid] = SimDevice(udid: udid, name: device["name"] as? String ?? udid, runtime: prettyRuntime(pretty),
                                  lastUsed: (device["lastUsedAt"] as? String).flatMap { iso.date(from: $0) },
                                  available: device["isAvailable"] as? Bool ?? true, dataBytes: (device["dataPathSize"] as? NSNumber)?.int64Value)
        }
    }
    return out
}
/// "iOS 26 5" → "iOS 26.5"
private func prettyRuntime(_ value: String) -> String {
    let parts = value.split(separator: " ").map(String.init)
    guard let first = parts.first else { return value }
    return parts.count > 1 ? first + " " + parts.dropFirst().joined(separator: ".") : first
}
/// Short, human age: "today", "yesterday", "3 days ago", "5 weeks ago", "4 months ago".
func ageText(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "unknown" }
    let days = Int(max(0, now.timeIntervalSince(date)) / 86400)
    if days == 0 { return "today" }
    if days == 1 { return "yesterday" }
    if days < 14 { return "\(days) days ago" }
    if days < 60 { return "\(days / 7) weeks ago" }
    return "\(days / 30) months ago"
}
struct Advice: Equatable {
    let verdict: Verdict
    /// Why, in one sentence.
    let reason: String
    /// How to remove it yourself, safely.
    let howTo: String
    /// Optional Terminal command the user may run themselves.
    let command: String?
    /// Best evidence of last use: Xcode's last-used date for simulators, otherwise the newest file change seen by a scan.
    let lastUsed: Date?
    /// Plain sentences behind the answer, for example what git says about the project.
    var evidence: [String] = []
}
/// Summary of the simulators Xcode knows about, for the Devices folder.
struct SimSummary: Equatable { var total = 0; var idle = 0; var idleBytes: Int64 = 0; var bytes: Int64 = 0; var unavailable = 0 }
func simSummary(_ devices: [String: SimDevice], now: Date = Date(), idleDays: Double = 30) -> SimSummary {
    var s = SimSummary()
    for d in devices.values {
        s.total += 1; s.bytes += d.dataBytes ?? 0
        if !d.available { s.unavailable += 1 }
        if !d.available || d.lastUsed == nil || now.timeIntervalSince(d.lastUsed!) >= idleDays * 86400 { s.idle += 1; s.idleBytes += d.dataBytes ?? 0 }
    }
    return s
}
/// Marks a size that came from Xcode's live device list rather than a scan.
let xcodeLiveScope = "xcode-live"
/// Shows Xcode's current simulator facts in place of an older or missing scan: the device's own name,
/// its size now, and for the Devices folder the current total. Display only; saved scans are never changed.
func withSimulatorFacts(_ m: FolderMeasurement, devices: [String: SimDevice], now: Date = Date()) -> FolderMeasurement {
    guard !devices.isEmpty, m.state == .measured || m.state == .pending else { return m }
    var live = m
    let path = m.profile.path
    if path.hasSuffix("/CoreSimulator/Devices") {
        let s = simSummary(devices, now: now)
        guard s.bytes > 0 else { return m }
        live.allocatedBytes = s.bytes
        if m.state == .measured, let old = m.allocatedBytes, abs(old - s.bytes) > max(Int64(1) << 30, s.bytes / 5) {
            live.diagnostic = "A scan \(ageText(m.observedAt, now: now)) measured \(byteLabel(old)) here; the size shown is Xcode's current count."
        } else { live.diagnostic = nil }
    } else if let root = SimulatorLocations.deviceRoot(path), root == path, let device = devices[URL(fileURLWithPath: root).lastPathComponent] {
        live.profile.name = device.name + " · " + device.runtime
        guard let bytes = device.dataBytes else { return live }
        live.allocatedBytes = bytes
        live.diagnostic = nil
    } else { return m }
    live.state = .measured
    live.observedAt = now
    live.logicalBytes = nil
    live.scopeID = xcodeLiveScope
    return live
}
/// "Size from 2 days ago", or "Size from Xcode, now" for live simulator facts.
func sizeSourceText(_ m: FolderMeasurement) -> String? {
    guard m.state == .measured else { return nil }
    return m.scopeID == xcodeLiveScope ? "size from Xcode, now" : "size from " + ageText(m.observedAt)
}
/// The verdict: your own choice first, then the folder rules, then what git says about its project.
func advice(for m: FolderMeasurement, policy: LocationPolicy, devices: [String: SimDevice], project: ProjectActivity? = nil, now: Date = Date()) -> Advice {
    if policy.isKept {
        return Advice(verdict: .keep, reason: "You chose to keep this, so it's never suggested for removal.", howTo: "Choose Stop Keeping to get suggestions for it again.", command: nil, lastUsed: [m.latestModifiedAt, project?.lastCommit].compactMap { $0 }.max())
    }
    var result = ruleAdvice(for: m, policy: policy, devices: devices, now: now)
    guard let project, [.workspace, .buildOutput].contains(m.profile.category), !m.profile.path.contains("/DerivedData"), m.state == .measured else { return result }
    let lastActivity = [m.latestModifiedAt, project.lastCommit].compactMap { $0 }.max()
    let label = project.isWorktree ? "Worktree \(project.name)" : "Project \(project.name)"
    let evidence = label + ": " + project.summary(now: now) + "."
    if project.active(now: now) {
        let reason = "You're still working on \(project.name): " + project.summary(now: now) + "."
        result = Advice(verdict: .check, reason: reason, howTo: result.verdict == .safe ? "Wait until you're done with \(project.name). " + result.howTo : result.howTo, command: result.command, lastUsed: lastActivity)
    } else if project.finished(now: now) {
        let whole = project.removeWorktreeCommand
        let reason = result.reason + " \(label) looks finished: " + project.summary(now: now) + "."
        let howTo = whole == nil ? result.howTo : "The whole worktree looks finished. Removing it with git keeps the repository tidy, and git refuses if anything is uncommitted. Or: " + result.howTo
        result = Advice(verdict: result.verdict, reason: reason, howTo: howTo, command: result.command ?? whole, lastUsed: lastActivity)
    } else {
        result = Advice(verdict: result.verdict, reason: result.reason, howTo: result.howTo, command: result.command, lastUsed: lastActivity)
    }
    result.evidence = [evidence]
    return result
}
/// The folder rules. Evidence first (open files, your own marks, last use), then what the folder is.
private func ruleAdvice(for m: FolderMeasurement, policy: LocationPolicy, devices: [String: SimDevice], now: Date) -> Advice {
    let path = m.profile.path
    let name = m.profile.displayName
    let trash = "Quit the app that uses it, then move it to the Trash in Finder. Empty the Trash when you're sure."
    let days: (Date?) -> Double? = { $0.map { now.timeIntervalSince($0) / 86400 } }
    // Simulators: Xcode knows best.
    if path.hasSuffix("/CoreSimulator/Devices") {
        let s = simSummary(devices, now: now)
        var reason = "Virtual iPhones and iPads for testing apps. Xcode didn't report any devices."
        if s.total > 0 {
            reason = "Holds \(s.total) test \(s.total == 1 ? "device" : "devices") using \(byteLabel(s.bytes)) now. "
            if s.idle == 0 { reason += "All of them were used in the last 30 days." }
            else {
                reason += "\(s.idle) \(s.idle == 1 ? "hasn't" : "haven't") been used in 30 days and \(s.idle == 1 ? "uses" : "use") \(byteLabel(s.idleBytes)); those are safe to remove."
                if s.idleBytes < s.bytes / 10 { reason += " Most of the space is in devices used this month, so check those first." }
            }
        }
        if m.scopeID == xcodeLiveScope, let note = m.diagnostic { reason += " " + note }
        return Advice(verdict: .check, reason: reason, howTo: "Don't remove this whole folder. Remove single devices in Xcode › Window › Devices and Simulators: select one, then press Delete.", command: s.unavailable > 0 ? "xcrun simctl delete unavailable" : nil, lastUsed: devices.values.compactMap(\.lastUsed).max() ?? m.latestModifiedAt)
    }
    if let root = SimulatorLocations.deviceRoot(path) {
        let udid = URL(fileURLWithPath: root).lastPathComponent
        let device = devices[udid]
        let deviceName = device.map { "“\($0.name)”" } ?? "this device"
        let how = "In Xcode, choose Window › Devices and Simulators, select \(deviceName), then press Delete. That removes the device and its apps and saves."
        if root != path {
            return Advice(verdict: .check, reason: "App data inside a test device. Deleting it alone can confuse the simulator.", howTo: "Delete the app inside the Simulator, or remove the whole device. " + how, command: nil, lastUsed: device?.lastUsed ?? m.latestModifiedAt)
        }
        guard let device else {
            return Advice(verdict: .check, reason: "Xcode doesn't list this device anymore, so it may be left over.", howTo: "Check Xcode › Window › Devices and Simulators. If it isn't there, it's safe to move this folder to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
        }
        let cmd = "xcrun simctl delete \(udid)"
        if !device.available { return Advice(verdict: .safe, reason: "\(device.name) needs \(device.runtime), which isn't installed, so it can't run anymore.", howTo: how, command: cmd, lastUsed: device.lastUsed) }
        guard let used = days(device.lastUsed) else { return Advice(verdict: .safe, reason: "\(device.name) (\(device.runtime)) has never been started.", howTo: how, command: cmd, lastUsed: nil) }
        if used >= 30 { return Advice(verdict: .safe, reason: "\(device.name) (\(device.runtime)) hasn't been used in \(Int(used)) days. Its apps and saves go with it.", howTo: how, command: cmd, lastUsed: device.lastUsed) }
        return Advice(verdict: .check, reason: "\(device.name) (\(device.runtime)) was used \(ageText(device.lastUsed, now: now)). Removing it loses its apps and saves.", howTo: how, command: cmd, lastUsed: device.lastUsed)
    }
    switch m.state {
    case .pending: return Advice(verdict: .check, reason: "Not scanned yet, so its size and last use are unknown.", howTo: "Scan it first.", command: nil, lastUsed: nil)
    case .missing: return Advice(verdict: .check, reason: "It's no longer on disk. Scan again to update the list.", howTo: "Nothing to do.", command: nil, lastUsed: nil)
    case .inaccessible, .limited, .failed: return Advice(verdict: .check, reason: "It couldn't be read completely, so what's inside is unknown.", howTo: "Open it in Finder and look before removing anything.", command: nil, lastUsed: m.latestModifiedAt)
    default: break
    }
    if !m.processes.isEmpty {
        let apps = Array(Set(m.processes.map(\.command))).sorted().prefix(2).joined(separator: " and ")
        return Advice(verdict: .check, reason: "\(apps) had files open here during the last scan.", howTo: "Quit \(apps) first. " + trash, command: nil, lastUsed: m.latestModifiedAt)
    }
    if policy.expected { return Advice(verdict: .keep, reason: "You marked its growth as expected.", howTo: "Change that in Tags and Notes if you want to review it.", command: nil, lastUsed: m.latestModifiedAt) }
    let idle = days(m.latestModifiedAt)
    let lastSeen = m.latestModifiedAt.map { " Last changed \(ageText($0, now: now))." } ?? ""
    let project = m.profile.project ?? "its project"
    /// Project build output: recreated by building again, but only call it safe once it's clearly idle.
    func projectBuild() -> Advice {
        guard let idle else { return Advice(verdict: .check, reason: "Build output for \(project), which a build recreates. When it was last used isn't known yet; scan it to find out.", howTo: trash, command: nil, lastUsed: nil) }
        if idle < 7 { return Advice(verdict: .check, reason: "Build output for \(project), changed \(ageText(m.latestModifiedAt, now: now)). You're probably still building it.", howTo: "Wait until you're done with \(project). " + trash, command: nil, lastUsed: m.latestModifiedAt) }
        return Advice(verdict: .safe, reason: "Build output for \(project). Building again recreates it.\(lastSeen)", howTo: "Move it to the Trash in Finder. The next build of \(project) takes longer.", command: nil, lastUsed: m.latestModifiedAt)
    }
    switch m.profile.category {
    case .packageCache:
        let cmd: String? = path.hasSuffix(".npm/_cacache") ? "npm cache clean --force" : path.hasSuffix("Caches/pip") ? "pip cache purge" : path.hasSuffix(".cache/uv") ? "uv cache clean" : path.hasSuffix("Caches/Homebrew") ? "brew cleanup --prune=all" : path.hasSuffix("Caches/Yarn") ? "yarn cache clean" : nil
        return Advice(verdict: .safe, reason: "A download cache. The tool downloads what it needs again, so the next install is a little slower.\(lastSeen)", howTo: cmd == nil ? trash : "Use the tool's own clean command, or: " + trash, command: cmd, lastUsed: m.latestModifiedAt)
    case .buildOutput:
        guard path.contains("/DerivedData") else { return projectBuild() }
        return Advice(verdict: .safe, reason: "Xcode rebuilds this. The next build of each project takes longer.\(lastSeen)", howTo: "Quit Xcode, then move the folder's contents to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    case .installCache:
        return Advice(verdict: .safe, reason: "Saved pieces from installing \(name.replacingOccurrences(of: " install cache", with: "")) on an iPhone or iPad. It's recreated on the next install.\(lastSeen)", howTo: trash, command: nil, lastUsed: m.latestModifiedAt)
    case .debugSymbols:
        if let idle, idle < 30 { return Advice(verdict: .check, reason: "Debug files for a device you connected \(ageText(m.latestModifiedAt, now: now)). Xcode copies them again if you remove them.", howTo: trash, command: nil, lastUsed: m.latestModifiedAt) }
        return Advice(verdict: .safe, reason: "Debug files for one iPhone or iPad and iOS version. Xcode copies them again the next time you connect it.\(lastSeen)", howTo: "Quit Xcode, then move this folder to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    case .workspace:
        let rebuildable = ["/build", "/generated", "/intermediates", "/.cxx"].contains { path.hasSuffix($0) }
        if rebuildable { return projectBuild() }
        if path.hasSuffix("/work") { return Advice(verdict: .check, reason: "A work folder for \(project). These can mix build files with inputs you made by hand.\(lastSeen)", howTo: "Look inside first. Remove what you know you can rebuild.", command: nil, lastUsed: m.latestModifiedAt) }
        return Advice(verdict: .check, reason: "Project files for \(project). Some may be the only copy of your work.\(lastSeen)", howTo: "Look inside first.", command: nil, lastUsed: m.latestModifiedAt)
    case .backup:
        return Advice(verdict: .check, reason: "A recovery copy made before a risky change. It may hold the only copy of unfinished work.\(lastSeen)", howTo: "Compare it with the project. If the project has everything, move this to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    case .history:
        return Advice(verdict: .keep, reason: "Your past conversations. Removing them loses that history for good.", howTo: "Archive old conversations in the app instead.", command: nil, lastUsed: m.latestModifiedAt)
    case .model:
        return Advice(verdict: .check, reason: "Downloaded AI models. You can download them again, but they're large.\(lastSeen)", howTo: "Remove models you don't use from inside \(m.profile.associatedApp).", command: nil, lastUsed: m.latestModifiedAt)
    case .appData:
        let app = m.profile.associatedApp
        return Advice(verdict: .keep, reason: "\(app)'s own library: things like games, saves and settings. Removing the folder can break \(app).", howTo: "Remove what you don't need from inside \(app) instead.", command: nil, lastUsed: m.latestModifiedAt)
    case .download:
        return Advice(verdict: .check, reason: "Files you downloaded. Old installers (.dmg, .pkg, .zip) are usually safe; documents may be your only copy.\(lastSeen)", howTo: "Sort by date in Finder and remove what you recognize.", command: nil, lastUsed: m.latestModifiedAt)
    case .simulator:
        return Advice(verdict: .check, reason: "Simulator data outside a device folder.\(lastSeen)", howTo: "Manage simulators in Xcode › Window › Devices and Simulators.", command: nil, lastUsed: m.latestModifiedAt)
    case .unknown:
        return Advice(verdict: .check, reason: "Context Cleaner doesn't know what this folder is.\(lastSeen)", howTo: "Look inside first.", command: nil, lastUsed: m.latestModifiedAt)
    }
}
/// Where a project folder lives, so identical project names can be told apart:
/// "Codex worktree kartpad-stabilization-20260918" or "GitHub/kartpad".
func locationHint(_ path: String) -> String? {
    let parts = path.split(separator: "/").map(String.init)
    if let i = parts.firstIndex(of: "worktrees"), i > 0, parts[i - 1] == ".codex", i + 1 < parts.count { return "Codex worktree " + parts[i + 1] }
    if let i = parts.firstIndex(of: "GitHub"), i + 1 < parts.count { return "GitHub/" + parts[i + 1] }
    if let i = parts.firstIndex(of: "backups"), i > 0, parts[i - 1] == ".codex", i + 1 < parts.count { return "Codex backup" }
    return nil
}
/// Paths that no longer exist on disk. Only reads metadata.
func missingPaths(_ paths: [String]) -> Set<String> {
    Set(paths.filter { path in var st = stat(); return lstat(path, &st) != 0 && (errno == ENOENT || errno == ENOTDIR) })
}
/// Known paths that are files rather than folders, such as Xcode's device_set.plist. Metadata only.
/// Places macOS guards with a one-time permission dialog: other apps' data and the Documents, Desktop and Downloads folders.
func protectedPlace(_ text: String) -> Bool {
    ["/Library/Containers/", "/Library/Group Containers/", "/Documents/", "/Desktop/", "/Downloads"].contains { text.contains($0) }
}
/// Saved folders a full scan should re-measure alongside what discovery found: each once, none already discovered.
func savedProfilesToRefresh(_ saved: [FolderProfile], discovered: [FolderProfile]) -> [FolderProfile] {
    var seen = Set(discovered.map { normalized($0.path) })
    return saved.filter { seen.insert(normalized($0.path)).inserted }
}
func fileOnlyPaths(_ paths: [String]) -> Set<String> {
    Set(paths.filter { path in var st = stat(); return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) != S_IFDIR })
}

// MARK: - Project evidence (read-only git metadata)

/// What git says about the project a folder belongs to. Read with read-only commands; nothing is written,
/// not even git's index (GIT_OPTIONAL_LOCKS=0).
struct ProjectActivity: Equatable {
    let root: String
    let isWorktree: Bool
    /// For a worktree: its main repository, and whether that repository still lists it.
    let mainRepository: String?
    let registered: Bool?
    let branch: String?
    let defaultBranch: String?
    let lastCommit: Date?
    /// True when the branch is already part of the default branch.
    let merged: Bool?
    /// Changed tracked files (capped at 999).
    let uncommitted: Int?
    var name: String { URL(fileURLWithPath: root).lastPathComponent }
    /// Committed to or edited in the last 7 days, or holding uncommitted changes.
    func active(now: Date = Date()) -> Bool {
        if let uncommitted, uncommitted > 0 { return true }
        if let lastCommit, now.timeIntervalSince(lastCommit) < 7 * 86400 { return true }
        return false
    }
    /// Branch merged (or worktree no longer listed), nothing uncommitted, and no commits for 14 days.
    func finished(now: Date = Date()) -> Bool {
        guard uncommitted == 0, let lastCommit, now.timeIntervalSince(lastCommit) >= 14 * 86400 else { return false }
        return merged == true || registered == false
    }
    /// One plain sentence, for example "Last commit 12 days ago on codex/fix · merged into main · nothing uncommitted".
    func summary(now: Date = Date()) -> String {
        var parts: [String] = []
        if let lastCommit { parts.append("Last commit " + ageText(lastCommit, now: now) + (branch.map { " on \($0)" } ?? "")) }
        if let merged, let branch, branch != defaultBranch, let defaultBranch { parts.append(merged ? "merged into \(defaultBranch)" : "not merged into \(defaultBranch)") }
        if let uncommitted { parts.append(uncommitted == 0 ? "nothing uncommitted" : "\(uncommitted >= 999 ? "999+" : String(uncommitted)) uncommitted \(uncommitted == 1 ? "change" : "changes")") }
        if registered == false { parts.append("its main repository no longer lists this worktree") }
        return parts.isEmpty ? "Git history couldn't be read." : parts.joined(separator: " · ")
    }
    /// The git command that removes a finished worktree the safe way. Git refuses if anything is uncommitted.
    var removeWorktreeCommand: String? {
        guard isWorktree, registered == true, let mainRepository else { return nil }
        return "git -C \"\(mainRepository)\" worktree remove \"\(root)\""
    }
}
/// The nearest folder at or above path that holds a .git entry. Metadata only; stops at the home folder.
func repositoryRoot(for path: String, home: String) -> String? {
    var current = normalized(path)
    while current.count > home.count, current.hasPrefix(home + "/") {
        var st = stat()
        if lstat(current + "/.git", &st) == 0 { return current }
        guard let slash = current.lastIndex(of: "/") else { return nil }
        current = String(current[..<slash])
    }
    return nil
}
/// Runs git read-only with a time limit. Returns trimmed output, or nil on failure.
func gitOutput(_ root: String, _ arguments: [String], timeout: TimeInterval = 10) -> String? {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root, "--no-optional-locks"] + arguments
    var environment = ProcessInfo.processInfo.environment; environment["GIT_OPTIONAL_LOCKS"] = "0"; environment["GIT_TERMINAL_PROMPT"] = "0"
    process.environment = environment
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let deadline = DispatchTime.now() + timeout
    DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
/// Reads a project's git activity. Read-only.
func readProjectActivity(_ root: String) -> ProjectActivity {
    var isWorktree = false, mainRepository: String?, registered: Bool?
    if let pointer = try? String(contentsOfFile: root + "/.git", encoding: .utf8), pointer.hasPrefix("gitdir:") {
        isWorktree = true
        let gitdir = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        var st = stat()
        registered = lstat(gitdir, &st) == 0
        if let range = gitdir.range(of: "/.git/worktrees/") { mainRepository = String(gitdir[..<range.lowerBound]) }
    }
    let branch = gitOutput(root, ["rev-parse", "--abbrev-ref", "HEAD"])
    let lastCommit = gitOutput(root, ["log", "-1", "--format=%ct"]).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    var defaultBranch = gitOutput(root, ["rev-parse", "--abbrev-ref", "origin/HEAD"])
    if defaultBranch == nil || defaultBranch == "origin/HEAD" {
        defaultBranch = ["main", "master"].first { gitOutput(root, ["rev-parse", "--verify", "--quiet", $0]) != nil }
    }
    var merged: Bool?
    if let defaultBranch { merged = gitOutput(root, ["merge-base", "--is-ancestor", "HEAD", defaultBranch]) != nil }
    let uncommitted = gitOutput(root, ["status", "--porcelain", "--untracked-files=no"]).map { $0.isEmpty ? 0 : min(999, $0.split(separator: "\n").count) }
    return ProjectActivity(root: root, isWorktree: isWorktree, mainRepository: mainRepository, registered: registered, branch: branch,
                           defaultBranch: defaultBranch.map { $0.hasPrefix("origin/") ? String($0.dropFirst(7)) : $0 }, lastCommit: lastCommit, merged: merged, uncommitted: uncommitted)
}
