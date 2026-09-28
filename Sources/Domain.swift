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
func growth(_ path: String, records: [ScanRecord]) -> GrowthSummary {
    let points = historyPoints(path, records: records)
    guard let last = points.last, last.state == .measured else { return GrowthSummary() }
    // Do not bridge an excluded, missing or inaccessible observation as uninterrupted growth.
    guard points.count > 1 else { return GrowthSummary(current: last.bytes) }
    let prior = points[points.count - 2]
    guard prior.state == .measured, prior.scopeID == last.scopeID else { return GrowthSummary(current: last.bytes) }
    return GrowthSummary(previous: prior.bytes, current: last.bytes, interval: last.date.timeIntervalSince(prior.date))
}
func uniqueAllocatedTotal(_ measurements: [FolderMeasurement]) -> Int64 {
    var accepted: [String] = []
    return measurements.filter { $0.state == .measured }.sorted { $0.profile.path.count < $1.profile.path.count }.reduce(0) { sum, item in
        guard !accepted.contains(where: { containsPath($0, item.profile.path) }) else { return sum }
        accepted.append(item.profile.path)
        return sum + (item.allocatedBytes ?? 0)
    }
}
