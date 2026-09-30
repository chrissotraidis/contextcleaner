import Foundation

/// Absolute path without "." or ".." parts, repeated slashes or a trailing slash. Stored paths are almost always
/// already in this form, so they're returned as-is; only unusual ones go through URL standardization.
func normalized(_ path: String) -> String {
    isCleanAbsolutePath(path) ? path : URL(fileURLWithPath: path).standardizedFileURL.path
}
/// Byte-level check: starts with "/", and no empty, "." or ".." component and no trailing slash (except "/" itself).
func isCleanAbsolutePath(_ path: String) -> Bool {
    let bytes = path.utf8
    guard bytes.first == 0x2F else { return false }
    if bytes.count == 1 { return true }
    var length = 0, dots = 0
    for byte in bytes.dropFirst() {
        if byte == 0x2F {
            if length == 0 || (dots == length && length <= 2) { return false }
            length = 0; dots = 0
        } else { length += 1; if byte == 0x2E { dots += 1 } }
    }
    return !(length == 0 || (dots == length && length <= 2))
}
/// True when the set holds this path or any folder above it. Paths must be normalized. Walks up at most one step per component.
func hasAncestor(in set: Set<String>, _ path: String) -> Bool {
    if set.isEmpty { return false }
    var current = Substring(path)
    while true {
        if set.contains(String(current)) { return true }
        guard let slash = current.utf8.lastIndex(of: 0x2F) else { return false }
        if slash == current.startIndex { return current.count > 1 && set.contains("/") }
        current = current[..<slash]
    }
}
func containsPath(_ parent: String, _ path: String) -> Bool {
    let p = normalized(parent), c = normalized(path)
    if p == c { return true }
    if p == "/" { return c.utf8.first == 0x2F }
    let parentBytes = p.utf8, childBytes = c.utf8
    guard childBytes.count > parentBytes.count, childBytes.starts(with: parentBytes) else { return false }
    return childBytes[childBytes.index(childBytes.startIndex, offsetBy: parentBytes.count)] == 0x2F
}
/// A path with the home folder shown as ~.
func abbreviatedPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}
func byteLabel(_ bytes: Int64) -> String {
    let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
    var amount = Double(bytes), index = 0
    while abs(amount) >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
    return amount.formatted(.number.precision(.fractionLength(0...2))) + " " + units[index]
}
func signedBytes(_ delta: Int64) -> String { (delta > 0 ? "+" : delta < 0 ? "−" : "") + byteLabel(abs(delta)) }
func elapsedLabel(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter(); formatter.allowedUnits = [.day, .hour, .minute, .second]
    formatter.maximumUnitCount = 2; formatter.unitsStyle = .abbreviated
    return formatter.string(from: max(1, interval)) ?? "less than a second"
}

enum FolderCategory: String, Codable, CaseIterable {
    case packageCache = "Package cache", buildOutput = "Build output", installCache = "Installation cache"
    case simulator = "Simulator data", debugSymbols = "Debugging symbols", workspace = "Mixed workspace"
    case backup = "Recovery backup", history = "Conversation history", model = "Model library"
    case appData = "Application data", download = "Downloads", virtualMachine = "Virtual machine", unknown = "Unclassified"
    var displayName: String {
        switch self {
        case .workspace: return "Project files"
        case .appData: return "App libraries"
        case .simulator: return "Test devices"
        case .backup: return "Recovery copies"
        case .installCache: return "Device install cache"
        case .buildOutput: return "Build files"
        case .model: return "AI models"
        case .history: return "Chat history"
        case .packageCache: return "Package downloads"
        case .debugSymbols: return "Debug files"
        case .download: return "Downloads"
        case .virtualMachine: return "Virtual machines"
        case .unknown: return "Other files"
        }
    }
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
    var displayName: String {
        if ["build", "work", "generated"].contains(name), let project { return project + " · " + name }
        return name
    }
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
    /// Older Recurring preferences participate in the single Watching feature.
    var isWatched: Bool {
        get { watched || recurring }
        set {
            watched = newValue; recurring = false
            if !newValue { autoWatched = nil; autoWatchedBytes = nil }
        }
    }
    var expected = false
    var excluded = false
    var reviewAfter: Date? = nil
    var growthThresholdBytes: Int64? = nil
    var tags: [String] = []
    var note = ""
    /// Set when the app added this location to Watching because it grew; cleared by the user's undo.
    var autoWatched: Bool? = nil
    var autoWatchedBytes: Int64? = nil
    /// You chose to keep this folder: never suggested for removal. Optional so older saved preferences still load.
    var kept: Bool? = nil
    var isKept: Bool { get { kept == true } set { kept = newValue ? true : nil } }
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
    /// Scans you start: 5 minutes and 5 million files per folder by default, so caches like DerivedData finish.
    var manualLimits: ScanLimits { ScanLimits(seconds: TimeInterval(min(max(perLocationSeconds ?? 300, 30), 900)), entries: min(max(perLocationEntries ?? 5_000_000, 100_000), 10_000_000)) }
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
    var accepted: Set<String> = []
    return measurements.filter { $0.state == .measured }.sorted { $0.profile.path.utf8.count < $1.profile.path.utf8.count }.reduce(0) { sum, item in
        let path = normalized(item.profile.path)
        guard !hasAncestor(in: accepted, path) else { return sum }
        accepted.insert(path)
        return sum + (item.allocatedBytes ?? 0)
    }
}

struct ScanChange { var path: String; var name: String; var delta: Int64 }
/// Per-location size changes between a scan and the previous completed scan of the same scope.
func scanDelta(_ record: ScanRecord, previous: ScanRecord?) -> (grew: [ScanChange], shrank: [ScanChange])? {
    guard let previous else { return nil }
    let before = Dictionary(previous.measurements.filter { $0.state == .measured }.map { ($0.profile.path, $0) }, uniquingKeysWith: { a, _ in a })
    var grew: [ScanChange] = [], shrank: [ScanChange] = [], comparable = 0
    var accepted: [String] = []
    for item in record.measurements.sorted(by: { $0.profile.path.utf8.count < $1.profile.path.utf8.count }) where item.state == .measured {
        guard let old = before[item.profile.path], old.scopeID == item.scopeID, let a = old.allocatedBytes, let b = item.allocatedBytes else { continue }
        // A comparable parent already includes its children in both snapshots.
        guard !accepted.contains(where: { containsPath($0, item.profile.path) }) else { continue }
        accepted.append(item.profile.path)
        comparable += 1
        guard a != b else { continue }
        let change = ScanChange(path: item.profile.path, name: item.profile.name, delta: b - a)
        if change.delta > 0 { grew.append(change) } else { shrank.append(change) }
    }
    guard comparable > 0 else { return nil }
    return (grew.sorted { $0.delta > $1.delta }, shrank.sorted { $0.delta < $1.delta })
}
