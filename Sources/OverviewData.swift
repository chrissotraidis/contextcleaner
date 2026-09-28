import Foundation

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

/// Calendar-aligned time window; chart redraws within a day cannot move the axis.
func freeSpaceWindow(at date: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    return calendar.date(byAdding: .day, value: -7, to: end)!...end
}
/// New observations may expand an axis, but never shrink or shift an existing range.
func freeSpaceRange(_ bytes: [Int64], preserving previous: ClosedRange<Double>? = nil) -> ClosedRange<Double> {
    let values = bytes.map { Double($0) / 1_073_741_824 }
    guard let minimum = values.min(), let maximum = values.max() else { return previous ?? 0...100 }
    let lower = max(0, floor(minimum / 10) * 10 - 10)
    let upper = max(lower + 20, ceil(maximum / 10) * 10 + 10)
    return min(previous?.lowerBound ?? lower, lower)...max(previous?.upperBound ?? upper, upper)
}
