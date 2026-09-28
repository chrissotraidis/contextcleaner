import Foundation

func normalized(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
func containsPath(_ parent: String, _ path: String) -> Bool {
    let p = normalized(parent), c = normalized(path)
    return p == c || (p == "/" ? c.hasPrefix("/") : c.hasPrefix(p + "/"))
}
func byteLabel(_ bytes: Int64) -> String {
    let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
    var amount = Double(bytes), index = 0
    while abs(amount) >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
    return amount.formatted(.number.precision(.fractionLength(0...2))) + " " + units[index]
}
func elapsedLabel(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter(); formatter.allowedUnits = [.day, .hour, .minute, .second]
    formatter.maximumUnitCount = 2; formatter.unitsStyle = .abbreviated
    return formatter.string(from: max(1, interval)) ?? "less than a second"
}

enum FolderCategory: String, Codable, CaseIterable {
    case packageCache = "Package cache", buildOutput = "Build output", installCache = "Installation cache"
    case simulator = "Simulator data", debugSymbols = "Debugging symbols", workspace = "Mixed workspace"
    case backup = "Recovery backup", history = "Conversation history", model = "Model library"
    case appData = "Application data", download = "Downloads", unknown = "Unclassified"
    var reproducible: Bool { [.packageCache, .buildOutput, .installCache].contains(self) }
}
enum EvidenceLevel: String, Codable { case observed = "Observed", inferred = "Inferred", unknown = "Unknown" }
struct Evidence: Codable, Hashable, Identifiable {
    var id: String { label + value + source }
    var label: String
    var value: String
    var level: EvidenceLevel
    var source: String
}
struct FolderProfile: Codable, Identifiable {
    var id: String { path }
    var path: String
    var name: String
    var category: FolderCategory
    var project: String?
    var associatedApp: String
    var explanation: String
    var consequence: String
    var evidence: [Evidence]
}
struct ProcessEvidence: Codable, Hashable {
    var pid: Int
    var command: String
    var access: String
    var path: String
    // Open descriptor modes do not prove that a write occurred.
}
enum MeasurementState: String, Codable { case pending, measured, inaccessible, missing, excluded, cancelled, limited, failed }
struct FolderMeasurement: Codable, Identifiable {
    var id: String { profile.path }
    var profile: FolderProfile
    var observedAt: Date
    var state: MeasurementState
    var allocatedBytes: Int64?
    var logicalBytes: Int64?
    var fileCount: Int
    var latestModifiedAt: Date?
    var processes: [ProcessEvidence]
    var activityCheckAvailable: Bool
    var diagnostic: String?
    var elapsedSeconds: Double
    var scopeID: String = "legacy-du"
    var contents: FolderContents? = nil
}
struct ScanRecord: Codable, Identifiable {
    var schema = 1
    var id: String
    var startedAt: Date
    var finishedAt: Date
    var scope: String
    var complete: Bool
    var freeBytes: Int64?
    var measurements: [FolderMeasurement]
    var discoveryNotes: [String]
    var legacySource: String?
    var requestedCount: Int? = nil
    var stopReason: String? = nil
}
struct LocationPolicy: Codable, Equatable {
    var watched = false
    var recurring = false
    var expected = false
    var excluded = false
    var reviewAfter: Date? = nil
    var growthThresholdBytes: Int64? = nil
    var tags: [String] = []
    var note = ""
    /// Set when the app added this location to Watching because it grew; cleared by the user's undo.
    var autoWatched: Bool? = nil
    var autoWatchedBytes: Int64? = nil
}
struct Preferences: Codable {
    var schema = 1
    var locations: [String: LocationPolicy] = [:]
    var customRoots: [String] = []
    var dailyWhileOpen = false
    var lastDiscovery: Date? = nil
    var lastScheduledAttempt: Date? = nil
    var appearance: String? = nil
    /// "off", "daily" or "weekly". Scheduled checks only run while the app is open.
    var schedule: String? = nil
    var priorityCount: Int? = nil
    var perLocationSeconds: Int? = nil
    var perLocationEntries: Int? = nil
    var effectiveSchedule: String { schedule ?? (dailyWhileOpen ? "daily" : "off") }
    var effectivePriorityCount: Int { min(max(priorityCount ?? 12, 4), 48) }
    var manualLimits: ScanLimits { ScanLimits(seconds: TimeInterval(min(max(perLocationSeconds ?? 120, 30), 900)), entries: min(max(perLocationEntries ?? 1_000_000, 100_000), 10_000_000)) }
    func policy(_ path: String) -> LocationPolicy { locations[normalized(path)] ?? LocationPolicy() }
    func excluded(_ path: String) -> Bool {
        locations.contains { $0.value.excluded && containsPath($0.key, path) }
    }
    func exclusionWithin(_ path: String) -> Bool {
        locations.contains { $0.value.excluded && containsPath(path, $0.key) }
    }
}
struct HistoryPoint: Identifiable {
    var id: String { recordID + path }
    var recordID: String
    var path: String
    var date: Date
    var bytes: Int64?
    var state: MeasurementState
    var scopeID: String
}
struct GrowthSummary {
    var previous: Int64?
    var current: Int64?
    var interval: TimeInterval?
    var delta: Int64? { guard let a = previous, let b = current else { return nil }; return b - a }
    var bytesPerDay: Double? { guard let d = delta, let t = interval, t > 0 else { return nil }; return Double(d) * 86400 / t }
    var percent: Double? { guard let d = delta, let p = previous, p > 0 else { return nil }; return Double(d) / Double(p) * 100 }
}
func historyPoints(_ path: String, records: [ScanRecord]) -> [HistoryPoint] {
    records.flatMap { record in record.measurements.filter { $0.profile.path == path }.map {
        HistoryPoint(recordID: record.id, path: path, date: $0.observedAt, bytes: $0.state == .measured ? $0.allocatedBytes : nil, state: $0.state, scopeID: $0.scopeID)
    }}.sorted { $0.date < $1.date }
}
/// One pass over every record, producing the per-path point series the model caches.
func historyIndex(_ records: [ScanRecord]) -> [String: [HistoryPoint]] {
    var index: [String: [HistoryPoint]] = [:]
    for record in records { for item in record.measurements {
        index[item.profile.path, default: []].append(HistoryPoint(recordID: record.id, path: item.profile.path, date: item.observedAt, bytes: item.state == .measured ? item.allocatedBytes : nil, state: item.state, scopeID: item.scopeID))
    }}
    for key in index.keys { index[key]!.sort { $0.date < $1.date } }
    return index
}
func growth(points: [HistoryPoint]) -> GrowthSummary {
    guard let last = points.last, last.state == .measured else { return GrowthSummary() }
    guard points.count > 1 else { return GrowthSummary(current: last.bytes) }
    let prior = points[points.count - 2]
    guard prior.state == .measured, prior.scopeID == last.scopeID else { return GrowthSummary(current: last.bytes) }
    return GrowthSummary(previous: prior.bytes, current: last.bytes, interval: last.date.timeIntervalSince(prior.date))
}
func growth(_ path: String, records: [ScanRecord]) -> GrowthSummary {
    growth(points: historyPoints(path, records: records))
}
func uniqueAllocatedTotal(_ measurements: [FolderMeasurement]) -> Int64 {
    var accepted: [String] = []
    return measurements.filter { $0.state == .measured }.sorted { $0.profile.path.count < $1.profile.path.count }.reduce(0) { sum, item in
        guard !accepted.contains(where: { containsPath($0, item.profile.path) }) else { return sum }
        accepted.append(item.profile.path)
        return sum + (item.allocatedBytes ?? 0)
    }
}

struct ScanChange { var path: String; var name: String; var delta: Int64 }
/// Per-location size changes between a scan and the previous completed scan of the same scope.
func scanDelta(_ record: ScanRecord, previous: ScanRecord?) -> (grew: [ScanChange], shrank: [ScanChange])? {
    guard let previous else { return nil }
    let before = Dictionary(previous.measurements.filter { $0.state == .measured }.map { ($0.profile.path, $0) }, uniquingKeysWith: { a, _ in a })
    var grew: [ScanChange] = [], shrank: [ScanChange] = [], comparable = 0
    for item in record.measurements where item.state == .measured {
        guard let old = before[item.profile.path], old.scopeID == item.scopeID, let a = old.allocatedBytes, let b = item.allocatedBytes else { continue }
        comparable += 1
        guard a != b else { continue }
        let change = ScanChange(path: item.profile.path, name: item.profile.name, delta: b - a)
        if change.delta > 0 { grew.append(change) } else { shrank.append(change) }
    }
    guard comparable > 0 else { return nil }
    return (grew.sorted { $0.delta > $1.delta }, shrank.sorted { $0.delta < $1.delta })
}
