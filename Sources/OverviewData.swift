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
    var accepted: [String] = [], totals: [FolderCategory: (Int64, Int)] = [:]
    for item in measurements.sorted(by: { $0.profile.path.count == $1.profile.path.count ? $0.profile.path < $1.profile.path : $0.profile.path.count < $1.profile.path.count }) {
        guard item.state == .measured, let bytes = item.allocatedBytes, !preferences.excluded(item.profile.path),
              !accepted.contains(where: { containsPath($0, item.profile.path) }) else { continue }
        accepted.append(item.profile.path)
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
