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
    let issues = record.measurements.filter { [.inaccessible, .limited, .failed].contains($0.state) }.count
    let gone = record.measurements.filter { $0.state == .missing }.count
    let target = record.requestedCount ?? record.measurements.count
    if !record.complete && record.wasStopped { return "Stopped after \(measured) of \(target) \(target == 1 ? "folder" : "folders")" }
    if measured == 0 && issues > 0 { return issues == 1 ? "1 folder couldn't be read" : "\(issues) folders couldn't be read" }
    var parts = [measured == 1 ? "Scanned 1 folder" : "Scanned \(measured) folders"]
    if grew > 0 { parts.append("\(grew) grew") }
    if issues > 0 { parts.append("\(issues) couldn't be read") }
    if gone > 0 { parts.append("\(gone) no longer on disk") }
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
        // Folders you deleted aren't problems; they're reported plainly and never in red.
        let issues = measurements.filter { [.inaccessible, .limited, .failed].contains($0.state) }.count
        let gone = measurements.filter { $0.state == .missing }.count
        let target = requestedCount ?? measurements.count
        if !complete && wasStopped { return "Stopped · \(measured) of \(target) \(target == 1 ? "folder" : "folders") scanned" }
        if measured == 0 && issues > 0 { return issues == 1 ? "1 folder couldn't be read" : "\(issues) folders couldn't be read" }
        var parts = [measured == 1 ? "1 folder scanned" : "\(measured) folders scanned"]
        if issues > 0 { parts.append("\(issues) couldn't be read") }
        if gone > 0 { parts.append("\(gone) no longer on disk") }
        return parts.joined(separator: " · ")
    }
    /// True when the user stopped the scan, as opposed to folders that couldn't be read.
    var wasStopped: Bool {
        measurements.contains { $0.state == .cancelled } || measurements.count < (requestedCount ?? measurements.count)
    }
}


// MARK: - Can I remove it?

/// A plain answer for every folder. The app never acts on it; it tells you what you can do yourself.
enum Verdict: Int, Comparable, CaseIterable, Identifiable {
    /// Ranked by what removing costs: nothing, a rebuild, possibly your only copy, or the app itself.
    case safe = 0, rebuild = 1, check = 2, keep = 3
    var id: Int { rawValue }
    static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }
    var title: String {
        switch self {
        case .safe: return "Safe to remove"
        case .rebuild: return "Rebuildable"
        case .check: return "Your call"
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
    var reason: String
    /// How to remove it yourself, safely.
    let howTo: String
    /// Optional Terminal command the user may run themselves.
    let command: String?
    /// Best evidence of last use: Xcode's last-used date for simulators, otherwise the newest file change seen by a scan.
    let lastUsed: Date?
    /// Plain sentences behind the answer, for example what git says about the project.
    var evidence: [String] = []
    /// A few words for the list: "Used today", "Open in Parallels Desktop", "12 GiB unused inside".
    var short: String = ""
    /// Items inside a folder you're still using that haven't changed in 30+ days. You may remove these yourself.
    var staleItems: [StaleItem] = []
    var staleBytes: Int64 { staleItems.reduce(0) { $0 + $1.bytes } }
    /// How long the stale items have gone unchanged: 7 days for project output, 30 for caches.
    var staleDays = 30
}
struct StaleItem: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let bytes: Int64
    let modifiedAt: Date?
}
/// A command that moves items to the Trash (reversible; nothing is erased). Context Cleaner only copies it.
func trashCommand(_ paths: [String]) -> String {
    let quoted = paths.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    return "mv -n " + quoted.joined(separator: " ") + " ~/.Trash/"
}
/// Readable names for processes that hold files open.
func friendlyApp(_ command: String) -> String {
    let c = command.lowercased()
    if c.hasPrefix("prl_") || c.contains("parallels") { return "Parallels Desktop" }
    if c.contains("docker") || c.hasPrefix("com.docke") || c == "vpnkit" || c.contains("virtualization") { return "Docker Desktop" }
    if c == "java" { return "Gradle or Android Studio" }
    if c.hasPrefix("xcode") || c == "xcbbuildservice" || c == "sourcekit-lsp" { return "Xcode" }
    if c.contains("simulator") || c == "launchd_sim" { return "Simulator" }
    if c.hasPrefix("lm studio") || c.hasPrefix("lmstudio") { return "LM Studio" }
    if c.hasPrefix("steam") { return "Steam" }
    return command
}
/// Items at the top level of a folder that haven't changed in 30+ days, biggest first. From the last scan's contents.
func staleChildren(_ m: FolderMeasurement, now: Date, days: Double = 30, minimum: Int64 = 50 * 1_048_576) -> [StaleItem] {
    guard let children = m.contents?.children else { return [] }
    return children.filter { child in
        guard child.bytes >= minimum, let modified = child.modifiedAt else { return false }
        return now.timeIntervalSince(modified) >= days * 86400
    }.sorted { $0.bytes > $1.bytes }.map { StaleItem(path: m.profile.path + "/" + $0.name, name: $0.name, bytes: $0.bytes, modifiedAt: $0.modifiedAt) }
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
        var kept = Advice(verdict: .keep, reason: "You chose to keep this. It's never suggested for removal.", howTo: "Choose Stop Keeping to get suggestions for it again.", command: nil, lastUsed: [m.latestModifiedAt, project?.lastCommit].compactMap { $0 }.max())
        kept.short = "Kept by you"
        return kept
    }
    var result = projectAdvice(for: m, policy: policy, devices: devices, project: project, now: now)
    // A folder you're still using may hold old items that tools recreate. Point at those instead of the whole folder.
    let rebuildable: Bool = {
        switch m.profile.category {
        case .packageCache, .installCache, .buildOutput, .debugSymbols, .model: return true
        case .workspace: return ["/build", "/generated", "/intermediates", "/.cxx"].contains { m.profile.path.hasSuffix($0) }
        default: return false
        }
    }()
    // Project build and scratch folders hold one subfolder per build or experiment; a week untouched means it's done.
    let projectOutput = isProjectOutput(m.profile.path) || (m.profile.category == .buildOutput && !m.profile.path.contains("/DerivedData"))
    if [.rebuild, .check].contains(result.verdict), rebuildable || projectOutput, m.state == .measured {
        let days: Double = projectOutput ? 7 : 30
        let stale = staleChildren(m, now: now, days: days)
        let total = stale.reduce(Int64(0)) { $0 + $1.bytes }
        if total >= 1 << 30 {
            result.reason += " \(byteLabel(total)) inside hasn't changed in \(Int(days))+ days (\(stale.count) \(stale.count == 1 ? "item" : "items"))."
            result.staleItems = stale
            result.staleDays = Int(days)
        }
    }
    result.short = shortReason(result, m: m, project: project, now: now)
    return result
}
/// A few words for the Folders list, matching the reason.
private func shortReason(_ a: Advice, m: FolderMeasurement, project: ProjectActivity?, now: Date) -> String {
    if !a.staleItems.isEmpty { return "\(byteLabel(a.staleBytes)) old inside" }
    if !m.processes.isEmpty, let app = m.processes.first.map({ friendlyApp($0.command) }) { return "Open in \(app)" }
    let idle = a.lastUsed.map { now.timeIntervalSince($0) / 86400 }
    if a.verdict == .rebuild { return a.lastUsed.map { "Used " + ageText($0, now: now) } ?? "Rebuilt when needed" }
    if let project, [.workspace, .buildOutput].contains(m.profile.category) {
        if let u = project.uncommitted, u > 0, a.verdict == .check { return "Uncommitted work" }
        if project.finished(now: now) { return "Project finished" }
        if project.active(now: now), a.verdict == .check { return "Active project" }
    }
    switch a.verdict {
    case .rebuild: return "Rebuilt when needed"
    case .safe:
        guard let idle, idle >= 2 else { return "Its tool recreates it" }
        return "Unused for " + ageText(a.lastUsed, now: now).replacingOccurrences(of: " ago", with: "")
    case .keep:
        switch m.profile.category {
        case .history: return "Your chat history"
        case .appData: return "App's own library"
        default: return "Growth expected"
        }
    case .check:
        if let idle, idle < 7 { return "Used " + ageText(a.lastUsed, now: now) }
        switch m.profile.category {
        case .backup: return "May be the only copy"
        case .workspace: return m.profile.path.hasSuffix("/work") ? "Scratch, not in git" : "Project files"
        case .model: return "Re-download to restore"
        case .download: return "Your downloads"
        case .virtualMachine: return "Whole computer"
        case .simulator: return "Apps and saves"
        default: return m.state == .pending ? "Not scanned yet" : "Look inside"
        }
    }
}
/// The folder rules plus what git says about the project.
private func projectAdvice(for m: FolderMeasurement, policy: LocationPolicy, devices: [String: SimDevice], project: ProjectActivity?, now: Date) -> Advice {
    var result = ruleAdvice(for: m, policy: policy, devices: devices, now: now)
    guard let project, [.workspace, .buildOutput].contains(m.profile.category), !m.profile.path.contains("/DerivedData"), m.state == .measured else { return result }
    let lastActivity = [m.latestModifiedAt, project.lastCommit].compactMap { $0 }.max()
    let label = project.isWorktree ? "Worktree \(project.name)" : "Project \(project.name)"
    var evidence = [label + ": " + project.summary(now: now) + "."]
    let ignored = project.ignored[m.profile.path]
    if ignored == true { evidence.append("Git ignores this folder, so the repository doesn't need it.") }
    if ignored == false && isProjectBuildOutput(m.profile.path) {
        // A folder named build that git tracks may be source; don't treat it as output.
        result = Advice(verdict: .check, reason: "Git tracks files in this folder, so it may hold source, not just build output.", howTo: "Look inside first.", command: nil, lastUsed: lastActivity)
        evidence.append("Git tracks this folder.")
    } else if project.active(now: now) {
        if [.safe, .rebuild].contains(result.verdict) {
            // Uncommitted changes live in tracked files, not in ignored build output.
            result = Advice(verdict: .rebuild, reason: "Build output for \(project.name), which you're still working on. The next build recreates it.", howTo: "Move it to the Trash between builds. The next build of \(project.name) takes longer.", command: nil, lastUsed: lastActivity)
        } else {
            result = Advice(verdict: .check, reason: result.reason + " \(label) is still active.", howTo: result.howTo, command: result.command, lastUsed: lastActivity)
        }
    } else if project.finished(now: now) {
        let whole = project.removeWorktreeCommand
        let reason = result.reason + " \(label) looks finished: merged, clean and quiet for two weeks."
        let howTo = whole == nil ? result.howTo : "Remove the whole worktree with git (it refuses if anything is uncommitted), or just this folder: " + result.howTo.prefix(1).lowercased() + result.howTo.dropFirst()
        result = Advice(verdict: result.verdict, reason: reason, howTo: howTo, command: result.command ?? whole, lastUsed: lastActivity)
    } else {
        result = Advice(verdict: result.verdict, reason: result.reason, howTo: result.howTo, command: result.command, lastUsed: lastActivity)
    }
    result.evidence = evidence
    return result
}
/// Build output inside a project: recreated by building again.
func isProjectBuildOutput(_ path: String) -> Bool { ["/build", "/generated", "/intermediates", "/.cxx"].contains { path.hasSuffix($0) } }
/// Build output or a scratch work folder: each holds one subfolder per build or experiment.
func isProjectOutput(_ path: String) -> Bool { isProjectBuildOutput(path) || path.hasSuffix("/work") }
/// The folder rules. Evidence first (open files, your own marks, last use), then what the folder is.
private func ruleAdvice(for m: FolderMeasurement, policy: LocationPolicy, devices: [String: SimDevice], now: Date) -> Advice {
    let path = m.profile.path
    let name = m.profile.displayName
    let trash = "Quit the app that uses it, then move it to the Trash."
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
    let openApps = Array(Set(m.processes.map { friendlyApp($0.command) })).sorted().prefix(2).joined(separator: " and ")
    if !m.processes.isEmpty && m.profile.category != .virtualMachine {
        return Advice(verdict: .check, reason: "\(openApps) had files open here at the last scan.", howTo: "Quit \(openApps), then move it to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    }
    if policy.expected { return Advice(verdict: .keep, reason: "You said its growth is normal.", howTo: "Right-click it and choose Warn Me When It Grows to get suggestions again.", command: nil, lastUsed: m.latestModifiedAt) }
    let idle = days(m.latestModifiedAt)
    // The card shows when it was last used, so reasons don't repeat it.
    let project = m.profile.project ?? "its project"
    /// Project build output: recreated by building again, but only call it safe once it's clearly idle.
    func projectBuild() -> Advice {
        guard let idle else { return Advice(verdict: .rebuild, reason: "Build output for \(project). The next build recreates it.", howTo: trash, command: nil, lastUsed: nil) }
        if idle < 7 { return Advice(verdict: .rebuild, reason: "Build output for \(project), changed \(ageText(m.latestModifiedAt, now: now)). The next build recreates it.", howTo: "Move it to the Trash between builds. The next build of \(project) takes longer.", command: nil, lastUsed: m.latestModifiedAt) }
        return Advice(verdict: .safe, reason: "Build output for \(project), last changed \(ageText(m.latestModifiedAt, now: now)). Building again recreates it.", howTo: "Move it to the Trash. The next build of \(project) takes longer.", command: nil, lastUsed: m.latestModifiedAt)
    }
    /// Caches a tool used this week: removing them now just means downloading or rebuilding what you're using.
    func recentlyUsed(_ what: String) -> Advice? {
        guard let idle, idle < 7 else { return nil }
        return Advice(verdict: .rebuild, reason: "\(what), still in use. Remove it and the next run is slower while it's rebuilt.", howTo: trash, command: nil, lastUsed: m.latestModifiedAt)
    }
    switch m.profile.category {
    case .packageCache:
        if let recent = recentlyUsed("This download cache") { return recent }
        let cmd: String? = path.hasSuffix(".npm/_cacache") ? "npm cache clean --force" : path.hasSuffix("Caches/pip") ? "pip cache purge" : path.hasSuffix(".cache/uv") ? "uv cache clean" : path.hasSuffix("Caches/Homebrew") ? "brew cleanup --prune=all" : path.hasSuffix("Caches/Yarn") ? "yarn cache clean" : nil
        return Advice(verdict: .safe, reason: "A download cache. The tool fetches what it needs again.", howTo: cmd == nil ? trash : "Run the tool's own clean command, or: " + trash.lowercased(), command: cmd, lastUsed: m.latestModifiedAt)
    case .buildOutput:
        guard path.contains("/DerivedData") else { return projectBuild() }
        if let recent = recentlyUsed("Xcode's build data") { return recent }
        return Advice(verdict: .safe, reason: "Xcode's build data. Xcode rebuilds it; the next build takes longer.", howTo: "Quit Xcode, then move the folder's contents to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    case .installCache:
        if let recent = recentlyUsed("This install cache") { return recent }
        return Advice(verdict: .safe, reason: "Left over from installing \(name.replacingOccurrences(of: " install cache", with: "")) on an iPhone or iPad. The next install recreates it.", howTo: trash, command: nil, lastUsed: m.latestModifiedAt)
    case .debugSymbols:
        if let idle, idle < 30 { return Advice(verdict: .rebuild, reason: "Debug files for a device you connected \(ageText(m.latestModifiedAt, now: now)). Xcode copies them again the next time you connect it.", howTo: trash, command: nil, lastUsed: m.latestModifiedAt) }
        return Advice(verdict: .safe, reason: "Debug files for one device and iOS version. Xcode copies them again when you connect it.", howTo: "Quit Xcode, then move this folder to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    case .workspace:
        let rebuildable = ["/build", "/generated", "/intermediates", "/.cxx"].contains { path.hasSuffix($0) }
        if rebuildable { return projectBuild() }
        if path.hasSuffix("/work") { return Advice(verdict: .check, reason: "Scratch space for \(project): logs, test installs and experiments. It can also hold files you made by hand.", howTo: "Remove the experiment folders you're done with. Keep anything you made by hand.", command: nil, lastUsed: m.latestModifiedAt) }
        return Advice(verdict: .check, reason: "Files in the \(project) project. Some may be your only copy.", howTo: "Look inside before removing anything.", command: nil, lastUsed: m.latestModifiedAt)
    case .backup:
        return Advice(verdict: .check, reason: "Codex copied this before a risky change. Once that work is safely in the project, you don't need it.", howTo: "Open the project and check the change is there. Then move this copy to the Trash.", command: nil, lastUsed: m.latestModifiedAt)
    case .history:
        return Advice(verdict: .keep, reason: "Your past conversations. Removing them loses them for good.", howTo: "Archive old conversations in the app instead.", command: nil, lastUsed: m.latestModifiedAt)
    case .model:
        return Advice(verdict: .check, reason: "AI models you downloaded. You can get them again, but they're large.", howTo: "Remove models you don't use from inside \(m.profile.associatedApp).", command: nil, lastUsed: m.latestModifiedAt)
    case .appData:
        let app = m.profile.associatedApp
        return Advice(verdict: .keep, reason: "\(app)'s own library: games, saves and settings. Removing the folder can break \(app).", howTo: "Remove what you don't need from inside \(app).", command: nil, lastUsed: m.latestModifiedAt)
    case .download:
        return Advice(verdict: .check, reason: "Files you downloaded. Old installers (.dmg, .pkg, .zip) are usually safe to remove; documents may be your only copy.", howTo: "In Finder, sort by date and remove what you recognize.", command: nil, lastUsed: m.latestModifiedAt)
    case .virtualMachine:
        let app = m.profile.associatedApp
        let docker = app == "Docker Desktop"
        let howTo = docker ? "In Docker Desktop, remove images and containers you no longer need, or lower the disk limit in Settings › Resources. This command shows how much is reclaimable:"
            : app == "Parallels Desktop" ? "In Parallels Desktop's Control Center, delete old snapshots or use Reclaim Disk Space to shrink it. To remove the whole machine, right-click it › Remove."
            : "Remove or shrink it inside \(app)."
        let running = m.processes.isEmpty ? "" : " It's running right now."
        return Advice(verdict: .check, reason: "A whole virtual computer in \(app). Removing it deletes everything inside.\(running)", howTo: howTo, command: docker ? "docker system df" : nil, lastUsed: m.latestModifiedAt)
    case .simulator:
        return Advice(verdict: .check, reason: "Simulator data outside a device folder.", howTo: "Manage simulators in Xcode › Window › Devices and Simulators.", command: nil, lastUsed: m.latestModifiedAt)
    case .unknown:
        return Advice(verdict: .check, reason: "Context Cleaner doesn't recognize this folder.", howTo: "Look inside before removing anything.", command: nil, lastUsed: m.latestModifiedAt)
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
    /// For scanned folders inside this project: whether git ignores them. Missing means not checked.
    var ignored: [String: Bool] = [:]
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
func gitOutput(_ root: String, _ arguments: [String], timeout: TimeInterval = 10, okStatuses: Set<Int32> = [0]) -> String? {
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
    guard okStatuses.contains(process.terminationStatus) else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
/// Which of these folders git ignores, read-only. Paths outside the project, or a git failure, give no answer.
func ignoredByGit(_ root: String, paths: [String]) -> [String: Bool] {
    let relative = paths.filter { $0.hasPrefix(root + "/") }.map { String($0.dropFirst(root.count + 1)) }
    guard !relative.isEmpty, let output = gitOutput(root, ["check-ignore", "-v", "-n", "--"] + relative, okStatuses: [0, 1]) else { return [:] }
    var result: [String: Bool] = [:]
    for line in output.split(separator: "\n") {
        guard let tab = line.firstIndex(of: "\t") else { continue }
        result[root + "/" + line[line.index(after: tab)...]] = !line.hasPrefix("::")
    }
    return result
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

/// Share of the disk in use, never rounded up to a full disk: 18 GiB free on 3.6 TiB reads "99.5%", not "100%".
func usedPercentText(_ fraction: Double) -> String {
    let clamped = min(max(fraction, 0), 1)
    let digits = clamped >= 0.99 && clamped < 1 ? 1 : 0
    let scale = digits == 1 ? 1000.0 : 100.0
    let value = (clamped * scale).rounded(.down) / scale
    return value.formatted(.percent.precision(.fractionLength(digits)))
}


// MARK: - Where the space went

/// One place's share of a change in used space: a Coverage place such as "Codex · Worktrees", or an app.
struct SpaceChange: Identifiable, Equatable {
    var id: String { title }
    let title: String
    var bytes: Int64 = 0
    /// Folders in this place that were created inside the span; their whole size counts as growth.
    var newFolders = 0
    /// Biggest contributors, largest first: display name and change.
    var examples: [(name: String, path: String, bytes: Int64)] = []
    static func == (a: SpaceChange, b: SpaceChange) -> Bool { a.title == b.title && a.bytes == b.bytes && a.newFolders == b.newFolders }
}
/// Splits growth since from across places. A folder counts if it was scanned before from (the change since),
/// or was created after from (its whole size). Folders first scanned later but older than from are unknown and skipped.
/// Nested folders count once, through their outermost scanned folder.
func spaceChanges(history: [String: [HistoryPoint]], latest: [FolderMeasurement], created: [String: Date], from: Date, to: Date? = nil, home: String) -> [SpaceChange] {
    let measured = latest.filter { $0.state == .measured && $0.allocatedBytes != nil }.sorted { $0.profile.path.count < $1.profile.path.count }
    var accepted: Set<String> = []
    var groups: [String: SpaceChange] = [:]
    for item in measured {
        let path = normalized(item.profile.path)
        guard !hasAncestor(in: accepted, path) else { continue }
        accepted.insert(path)
        // The size at the end of the span: the latest scan, or the last scan before the span ended.
        var now = item.allocatedBytes ?? 0
        if let to, item.observedAt > to {
            guard let atEnd = history[item.profile.path]?.last(where: { $0.date <= to && $0.bytes != nil })?.bytes else { continue }
            now = atEnd
        }
        var delta: Int64, isNew = false
        if let before = history[item.profile.path]?.last(where: { $0.date <= from && $0.bytes != nil })?.bytes { delta = now - before }
        else if let born = created[item.profile.path], born >= from, born <= (to ?? .distantFuture) { delta = now; isNew = true }
        else { continue }
        guard delta != 0 else { continue }
        let title = changePlace(item, home: home)
        var group = groups[title] ?? SpaceChange(title: title)
        group.bytes += delta
        if isNew { group.newFolders += 1 }
        group.examples.append((item.profile.displayName, item.profile.path, delta))
        groups[title] = group
    }
    return groups.values.map { g in var g = g; g.examples = g.examples.sorted { g.bytes >= 0 ? $0.bytes > $1.bytes : $0.bytes < $1.bytes }.prefix(5).map { $0 }; return g }
        .sorted { $0.bytes > $1.bytes }
}
/// The place a folder belongs to, for grouping changes: its Coverage place, or its app.
func changePlace(_ m: FolderMeasurement, home: String) -> String {
    let match = Coverage.entries.filter { containsPath($0.path(home: home), m.profile.path) }.max { $0.path(home: home).count < $1.path(home: home).count }
    guard let match else { return m.profile.associatedApp }
    switch match.writer {
    case "You": return "Downloads"
    case "Your projects": return "GitHub projects"
    default: return match.writer + " · " + match.name
    }
}
