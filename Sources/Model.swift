import Foundation
import SwiftUI
import AppKit

struct FolderRow: Identifiable {
    var id: String { measurement.profile.path }
    var measurement: FolderMeasurement
    var policy: LocationPolicy
    var change: GrowthSummary
    var advice: Advice
    var gone = false
    var name: String { measurement.profile.displayName }
    var app: String { measurement.profile.project ?? measurement.profile.associatedApp }
    var bytes: Int64 { measurement.allocatedBytes ?? -1 }
    var delta: Int64 { change.delta ?? Int64.min }
    var category: String { measurement.profile.category.displayName }
    /// Sort keys: verdict (safe first) and last use (unknown last).
    var verdictRank: Int { gone ? 9 : advice.verdict.rawValue }
    var lastUsedKey: Double { advice.lastUsed?.timeIntervalSince1970 ?? 0 }
    /// Oldest use first; unknown use goes last.
    var unusedKey: Double { advice.lastUsed?.timeIntervalSince1970 ?? .greatestFiniteMagnitude }
    /// Days since last use, when known.
    var idleDays: Double? { advice.lastUsed.map { max(0, Date().timeIntervalSince($0) / 86400) } }
    /// Default order: big folders you haven't used in a while come first. Size is weighted by idle time
    /// (full weight after 90 days); recently used folders sink, unknown use counts a third, and folders
    /// an app manages (Keep) count a quarter.
    var idleScore: Double {
        guard bytes > 0 else { return 0 }
        let idle = idleDays.map { min($0, 90) / 90 } ?? 0.35
        return Double(bytes) * idle * (advice.verdict == .keep ? 0.25 : 1)
    }
    var growing: Bool { (change.delta ?? 0) > 0 && (change.delta ?? 0) >= (policy.growthThresholdBytes ?? 0) && !policy.expected }
    /// One plain word, shown only when it tells you something. Empty for an ordinary scanned folder.
    var status: String {
        if policy.excluded { return "Not scanned" }
        if policy.isKept { return "Kept" }
        if gone { return "Gone" }
        if measurement.state == .pending { return "Not scanned" }
        if measurement.state != .measured {
            switch measurement.state {
            case .inaccessible: return "Blocked"
            case .limited: return "Too large"
            case .missing: return "Missing"
            case .cancelled: return "Stopped"
            default: return "Failed"
            }
        }
        if (policy.reviewAfter ?? .distantPast) > Date() { return "Review later" }
        if policy.expected { return "Expected" }
        if growing { return "Growing" }
        if policy.isWatched { return "Watching" }
        if !measurement.processes.isEmpty { return "In use" }
        return ""
    }
    /// Status color per docs/DESIGN.md: red cannot-measure, orange growing, accent watching, otherwise secondary.
    var statusTint: Color {
        if policy.excluded { return .secondary }
        if [.pending, .cancelled, .excluded].contains(measurement.state) { return .secondary }
        if measurement.state != .measured { return .attention }
        if growing { return .growing }
        if policy.expected { return .stable }
        if policy.isWatched { return .accentColor }
        return .secondary
    }
}
@MainActor final class CleanerModel: ObservableObject {
    @Published var records: [ScanRecord] = [] { didSet { recordsVersion += 1 } }
    @Published var preferences = Preferences() { didSet { preferencesVersion += 1 } }
    @Published var discovery = Discovery(profiles: [], notes: []) { didSet { discoveryVersion += 1 } }
    @Published var selected: String? { didSet { if let s = selected { if selection != [s] { selection = [s] } } else if !selection.isEmpty { selection = [] } } }
    /// Table selection. One item drives the inspector; several show a summed summary.
    @Published var selection: Set<String> = [] { didSet { if selection.count == 1, selected != selection.first { selected = selection.first } else if selection.isEmpty, selected != nil { selected = nil } } }
    /// A changed view or filter must never leave actions targeting hidden rows.
    func retainVisibleSelection() {
        let visible = Set(rows.map(\.id))
        let retained = selection.intersection(visible)
        if retained != selection { selection = retained }
    }
    @Published var section: AppSection = .overview
    @Published var locationFilter: LocationFilter = .all
    @Published var editing: String?
    @Published var search = ""
    @Published var categoryFilter: FolderCategory?
    @Published var volume = VolumeSnapshot.read()
    /// Hourly disk-capacity readings for the Space used chart. Append-only.
    @Published var capacity: [CapacityReading] = []
    /// One-line result of the most recent scan, shown under the page header until dismissed.
    @Published var lastResult: String?
    /// Simulators as Xcode reports them, keyed by device ID. Read-only.
    @Published var simDevices: [String: SimDevice] = [:] { didSet { discoveryVersion += 1 } }
    /// Known folders that no longer exist on disk.
    @Published var gone: Set<String> = [] { didSet { discoveryVersion += 1 } }
    /// Discovered paths that are files, not folders. Hidden from the lists.
    @Published var fileOnly: Set<String> = [] { didSet { discoveryVersion += 1 } }
    /// Reads Xcode's simulator list in the background. Never changes simulators.
    func loadSimDevices() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "list", "devices", "-j"]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let devices = process.terminationStatus == 0 ? parseSimDevices(data) : [:]
            DispatchQueue.main.async { self.simDevices = devices }
        }
    }
    /// When each known folder was created, so new folders count fully in "where the space went". Metadata only.
    @Published var created: [String: Date] = [:] { didSet { discoveryVersion += 1 } }
    /// Checks which known folders are gone, and when each was created. Metadata only.
    func refreshGone() {
        let paths = Array(Set(discovery.profiles.map(\.path) + latest.map(\.profile.path)))
        DispatchQueue.global(qos: .utility).async {
            let missing = missingPaths(paths)
            let files = fileOnlyPaths(paths)
            var born: [String: Date] = [:]
            for path in paths where !missing.contains(path) {
                if let date = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.creationDateKey]).creationDate { born[path] = date }
            }
            DispatchQueue.main.async {
                if missing != self.gone { self.gone = missing }
                if files != self.fileOnly { self.fileOnly = files }
                if born != self.created { self.created = born }
            }
        }
    }
    /// Advice is read by rows, tiles and the Overview many times per update. It depends only on the folder's own
    /// measurement, its settings and discovery facts, so it survives scan progress and is keyed per measurement.
    private var adviceCache: (key: String, value: [String: Advice]) = ("", [:])
    func adviceFor(_ m: FolderMeasurement) -> Advice {
        let key = "\(preferencesVersion)|\(discoveryVersion)"
        if adviceCache.key != key { adviceCache = (key, [:]) }
        let itemKey = m.profile.path + "|\(m.state.rawValue)|\(m.observedAt.timeIntervalSinceReferenceDate)|\(m.allocatedBytes ?? -1)"
        if let cached = adviceCache.value[itemKey] { return cached }
        var value = advice(for: m, policy: preferences.policy(m.profile.path), devices: simDevices, project: project(for: m.profile.path))
        // Until git activity has been read, a project folder can't be called safe: it may be work in progress.
        if !projectsRead, value.verdict == .safe, [.workspace, .buildOutput].contains(m.profile.category), !m.profile.path.contains("/DerivedData") {
            var held = Advice(verdict: .check, reason: "Checking its project's git activity before answering. " + value.reason, howTo: value.howTo, command: value.command, lastUsed: value.lastUsed)
            held.evidence = value.evidence
            held.short = "Checking git…"
            value = held
        }
        adviceCache.value[itemKey] = value
        return value
    }
    /// Git activity for the projects that scanned folders belong to, keyed by project root. Read-only.
    @Published var projects: [String: ProjectActivity] = [:] { didSet { discoveryVersion += 1 } }
    /// Whether git activity has been read at least once since launch.
    private(set) var projectsRead = false
    private var projectRoots: [String: String] = [:]
    func project(for path: String) -> ProjectActivity? { projectRoots[path].flatMap { projects[$0] } }
    /// Reads git activity for every project folder in the background. Runs read-only git commands only.
    func refreshProjects() {
        let home = home
        let paths = Array(Set((latest.map(\.profile) + discovery.profiles).filter { [.workspace, .buildOutput].contains($0.category) && !$0.path.contains("/DerivedData") }.map(\.path)))
        DispatchQueue.global(qos: .utility).async {
            var roots: [String: String] = [:]
            for path in paths { if let root = repositoryRoot(for: path, home: home) { roots[path] = root } }
            var activity: [String: ProjectActivity] = [:]
            for root in Set(roots.values) {
                var project = readProjectActivity(root)
                project.ignored = ignoredByGit(root, paths: roots.filter { $0.value == root }.map(\.key))
                activity[root] = project
            }
            DispatchQueue.main.async { self.projectRoots = roots; self.projectsRead = true; self.projects = activity }
        }
    }
    func deviceAdvice(_ device: SimDevice) -> Advice {
        let profile = FolderProfile(path: home + "/Library/Developer/CoreSimulator/Devices/" + device.udid, name: device.name, category: .simulator, project: nil, associatedApp: "Apple CoreSimulator", explanation: "", consequence: "", evidence: [])
        return advice(for: FolderMeasurement(profile: profile, observedAt: Date(), state: .measured, fileCount: 0, processes: [], activityCheckAvailable: false, elapsedSeconds: 0), policy: LocationPolicy(), devices: simDevices)
    }
    func refreshVolume() { volume = VolumeSnapshot.read(); recordCapacityIfDue(); refreshTrash() }
    /// Space the Trash still holds. Nil until read, or when macOS doesn't allow reading it (Full Disk Access is off).
    @Published var trashBytes: Int64?
    /// Reads the Trash's size in the background. Metadata only; the Trash is never emptied or changed.
    func refreshTrash() {
        let url = URL(fileURLWithPath: home + "/.Trash")
        DispatchQueue.global(qos: .utility).async {
            let bytes = trashSize(url)
            DispatchQueue.main.async { if bytes != self.trashBytes { self.trashBytes = bytes } }
        }
    }
    /// Minimum spacing between stored capacity readings.
    static let capacityInterval: TimeInterval = 55 * 60
    /// Appends the current capacity reading when the previous one is at least 55 minutes older.
    /// Reads no folders and removes nothing.
    func recordCapacityIfDue() {
        guard let store, let v = volume else { return }
        if let last = capacity.last, v.date.timeIntervalSince(last.date) < Self.capacityInterval { return }
        let reading = CapacityReading(date: v.date, total: v.total, free: v.free)
        do { try store.appendCapacity(reading); capacity.append(reading) }
        catch { self.error = "A disk-space reading could not be saved: \(error.localizedDescription)" }
    }
    private var usageCache: (key: String, value: [UsageReading]) = ("", [])
    /// Used-space readings from scans, hourly checks and the live reading.
    var usage: [UsageReading] {
        let key = "\(recordsVersion)|\(capacity.count)|\(volume?.date.timeIntervalSince1970 ?? 0)"
        if usageCache.key == key { return usageCache.value }
        let value = usageReadings(records: records, capacity: capacity, current: volume)
        usageCache = (key, value)
        return value
    }
    /// Scanned folders that grew inside a span, excluding folders the user turned off.
    func foldersThatGrew(from: Date, to: Date, limit: Int = 5) -> [FolderGrowth] {
        refreshDerived()
        let profiles = Dictionary(latest.map { ($0.profile.path, $0.profile) }, uniquingKeysWith: { a, _ in a })
        return folderGrowth(history: derived.history, profile: { self.preferences.excluded($0) ? nil : profiles[$0] }, from: from, to: to, limit: limit)
    }
    func sparkline(_ path: String) -> [Double] { sparklineValues(history(path)) }
    /// A friendly name for any known folder, falling back to its last path component.
    func displayName(_ path: String) -> String {
        latest.first { $0.profile.path == path }?.profile.displayName
            ?? discovery.profiles.first { $0.path == path }?.displayName
            ?? URL(fileURLWithPath: path).lastPathComponent
    }
    /// Opens a folder in the Folders list with the inspector showing it.
    func open(_ path: String) {
        categoryFilter = nil; search = ""; locationFilter = .all; section = .locations; selected = path
    }
    @Published var running = false
    @Published var progress = "Ready"
    @Published var completed = 0
    @Published var targetCount = 0
    @Published var partial: [FolderMeasurement] = [] { didSet { partialVersion += 1 } }
    @Published var inspector = "Overview"
    @Published var children: [FolderMeasurement] = []
    @Published var inspecting = false
    @Published var discovering = false
    @Published var inspected: [String: FolderMeasurement] = [:]
    @Published var childrenParent: String?
    @Published var simulatorDevices: [FolderProfile] = []
    @Published var identifyingDevices = false
    @Published var simulatorDeviceParent: String?
    @Published var error: String?
    let home: String
    let store: AppendStore?
    var cancellation = Cancellation()
    var inspectionCancellation = Cancellation()
    init(home: String = NSHomeDirectory(), dataRoot: URL? = nil) {
        self.home = home
        do {
            let root = dataRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Context Cleaner")
            let storage = try AppendStore(root: root)
            let legacy = URL(fileURLWithPath: home + "/Library/Application Support/SpaceCheck/history.json")
            if FileManager.default.fileExists(atPath: legacy.path) { _ = try storage.importLegacy(legacy, home: home) }
            records = storage.records(); preferences = storage.preferences()
            capacity = storage.capacityReadings()
            discovery = storage.learnedDiscovery() ?? Discovery(profiles: [], notes: [])
            store = storage
            error = storage.warnings.isEmpty ? nil : storage.warnings.joined(separator: "\n")
        } catch { store = nil; self.error = "Storage unavailable; scanning is disabled to avoid losing history. \(error.localizedDescription)" }
        var saved = Dictionary(uniqueKeysWithValues: discovery.profiles.map { ($0.path, $0) })
        for path in preferences.customRoots where saved[path] == nil { saved[path] = Classifier.profile(path: path, home: home, readMetadata: false) }
        for record in records { for item in record.measurements { saved[item.profile.path] = item.profile } }
        discovery = Discovery(profiles: saved.values.sorted { $0.path < $1.path }, notes: ["Showing saved locations. Discovery runs only when requested. Coverage is recognized development/cache locations and your selected roots, not the whole disk."])
        recordCapacityIfDue()
        loadSimDevices()
        refreshGone()
        refreshProjects()
    }
    // Derived state is rebuilt only when its inputs change; SwiftUI reads these many times per frame.
    private struct Derived { var key = ""; var historyKey = -1; var saved: [String: FolderMeasurement] = [:]; var latest: [FolderMeasurement] = []; var history: [String: [HistoryPoint]] = [:]; var growth: [String: GrowthSummary] = [:] }
    private var derived = Derived()
    private var rowsCache: (key: String, validUntil: Date, rows: [FolderRow]) = ("", .distantPast, [])
    private var preferencesVersion = 0
    private var recordsVersion = 0
    private var discoveryVersion = 0
    private var partialVersion = 0
    private var derivedKey: String { "\(recordsVersion)|\(running ? partialVersion : -1)" }
    private var nextReviewDeadline: Date {
        let now = Date()
        return preferences.locations.values.compactMap(\.reviewAfter).filter { $0 > now }.min() ?? .distantFuture
    }
    private func refreshDerived() {
        let key = derivedKey
        guard derived.key != key else { return }
        // History, growth and the saved sizes change only when a scan is saved; progress during a scan only overlays partial results.
        if derived.historyKey != recordsVersion {
            var saved: [String: FolderMeasurement] = [:]
            for record in records.sorted(by: { $0.finishedAt < $1.finishedAt }) {
                for item in record.measurements where item.state != .cancelled { saved[item.profile.path] = item }
            }
            let history = historyIndex(records)
            derived.historyKey = recordsVersion; derived.saved = saved
            derived.history = history; derived.growth = history.mapValues { growth(points: $0) }
        }
        var byPath = derived.saved
        if running { for item in partial { byPath[item.profile.path] = item } }
        derived.key = key; derived.latest = Array(byPath.values)
    }
    var latest: [FolderMeasurement] { refreshDerived(); return derived.latest }
    /// Everything the Overview needs, computed once per change of records or preferences.
    struct OverviewSnapshot { var groups: [StorageGroup] = []; var total: Int64 = 0; var measuredBySize: [FolderMeasurement] = []; var growthCount = 0; var watchingCount = 0; var attentionCount = 0; var pendingCount = 0; var safe: [FolderMeasurement] = []; var safeBytes: Int64 = 0 }
    private var overviewCache: (key: String, validUntil: Date, value: OverviewSnapshot) = ("", .distantPast, OverviewSnapshot())
    var overview: OverviewSnapshot {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if overviewCache.key == key && Date() < overviewCache.validUntil { return overviewCache.value }
        let current = latest.map { withSimulatorFacts($0, devices: simDevices) }
        let excludedPaths = preferences.locations.filter { $0.value.excluded }.map { normalized($0.key) }
        func excluded(_ path: String) -> Bool { excludedPaths.contains { containsPath($0, path) } }
        let measured = current.filter { $0.state == .measured && !excluded($0.profile.path) && !gone.contains($0.profile.path) }
        let groups = overviewGroups(measured, preferences: Preferences())
        let now = Date()
        var growthCount = 0
        for item in measured {
            let policy = preferences.policy(item.profile.path), delta = growthSummary(item.profile.path).delta ?? 0
            if delta > 0 && delta >= (policy.growthThresholdBytes ?? 0) && !policy.expected && (policy.reviewAfter ?? .distantPast) <= now { growthCount += 1 }
        }
        var attention = Set<String>()
        // Folders that are gone aren't a problem to fix; they simply leave the lists.
        for item in current where !excluded(item.profile.path) && !gone.contains(item.profile.path) && [.inaccessible, .limited, .failed].contains(item.state) { attention.insert(item.profile.path) }
        let known = Set(current.map { $0.profile.path })
        let pendingCount = discovery.profiles.filter { !known.contains($0.path) && !excluded($0.path) && !fileOnly.contains($0.path) }.count
        let watching = preferences.locations.filter { ($0.value.isWatched) && !excluded($0.key) }.count
        let safe = verdictGroups[.safe] ?? []
        let snapshot = OverviewSnapshot(groups: groups, total: groups.reduce(0) { $0 + $1.bytes }, measuredBySize: measured.sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }, growthCount: growthCount, watchingCount: watching, attentionCount: attention.count, pendingCount: pendingCount, safe: safe, safeBytes: uniqueAllocatedTotal(safe))
        overviewCache = (key, nextReviewDeadline, snapshot)
        return snapshot
    }
    func history(_ path: String) -> [HistoryPoint] { refreshDerived(); return derived.history[path] ?? [] }
    func growthSummary(_ path: String) -> GrowthSummary { refreshDerived(); return derived.growth[path] ?? GrowthSummary() }
    var rows: [FolderRow] {
        let key = derivedKey + "|" + section.rawValue + "|" + locationFilter.rawValue + "|" + search + "|\(preferencesVersion)|\(categoryFilter?.rawValue ?? "")|\(discoveryVersion)"
        if rowsCache.key == key && Date() < rowsCache.validUntil { return rowsCache.rows }
        let result = computeRows()
        rowsCache = (key, nextReviewDeadline, result)
        return result
    }
    private func computeRows() -> [FolderRow] {
        return baseMeasures().map { FolderRow(measurement: $0, policy: preferences.policy($0.profile.path), change: growthSummary($0.profile.path), advice: adviceFor($0), gone: gone.contains($0.profile.path)) }.filter { row in
            let p = row.measurement.profile
            if let categoryFilter, p.category != categoryFilter { return false }
            guard search.isEmpty || (p.path + p.name + p.associatedApp + (p.project ?? "") + row.policy.tags.joined()).localizedCaseInsensitiveContains(search) else { return false }
            return include(row, p)
        }
    }
    /// Every known folder: saved sizes, discovered folders not yet scanned, and turned-off folders,
    /// with Xcode's live facts for simulators.
    private var baseCache: (key: String, value: [FolderMeasurement]) = ("", [])
    private func baseMeasures() -> [FolderMeasurement] {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if baseCache.key == key { return baseCache.value }
        var measures = latest
        var known = Set(measures.map { $0.profile.path })
        for profile in discovery.profiles where !fileOnly.contains(profile.path) && !known.contains(profile.path) {
            measures.append(FolderMeasurement(profile: profile, observedAt: Date(), state: .pending, fileCount: 0, processes: [], activityCheckAvailable: false, diagnostic: "Discovered; not yet measured.", elapsedSeconds: 0))
            known.insert(profile.path)
        }
        // Excluded locations remain manageable even if they have never been measured.
        for (path, policy) in preferences.locations where policy.excluded && !known.contains(path) {
            measures.append(FolderMeasurement(profile: Classifier.profile(path: path, home: home, readMetadata: false), observedAt: Date(), state: .excluded, fileCount: 0, processes: [], activityCheckAvailable: false, diagnostic: "Excluded by you.", elapsedSeconds: 0))
            known.insert(path)
        }
        let value = measures.map { withSimulatorFacts($0, devices: simDevices) }
        baseCache = (key, value)
        return value
    }
    /// Scanned, included folders still on disk, grouped by answer and sorted largest first.
    /// The Folders tiles, the Overview and the Safe to remove list all read this.
    private var verdictCache: (key: String, value: [Verdict: [FolderMeasurement]]) = ("", [:])
    var verdictGroups: [Verdict: [FolderMeasurement]] {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if verdictCache.key == key { return verdictCache.value }
        var groups: [Verdict: [FolderMeasurement]] = [:]
        for item in baseMeasures() where item.state == .measured && !preferences.excluded(item.profile.path) && !preferences.policy(item.profile.path).isKept && !gone.contains(item.profile.path) {
            groups[adviceFor(item).verdict, default: []].append(item)
        }
        let value = groups.mapValues { $0.sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) } }
        verdictCache = (key, value)
        return value
    }
    /// Count and size for one answer, nested folders counted once.
    private var totalsCache: (key: String, value: [Verdict: (count: Int, bytes: Int64)]) = ("", [:])
    func verdictTotal(_ verdict: Verdict) -> (count: Int, bytes: Int64) {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if totalsCache.key != key { totalsCache = (key, [:]) }
        if let cached = totalsCache.value[verdict] { return cached }
        let items = verdictGroups[verdict] ?? []
        let value = (items.count, uniqueAllocatedTotal(items))
        totalsCache.value[verdict] = value
        return value
    }
    private func include(_ row: FolderRow, _ p: FolderProfile) -> Bool {
        // Folders that are gone leave every list. Kept and turned-off folders live in their own view.
        if row.gone { return false }
        let off = preferences.excluded(p.path), kept = row.policy.isKept
        switch section {
        case .kept: return off || kept
        case .locations:
            if locationFilter == .excluded { return row.policy.excluded }
            guard !off, !kept else { return false }
            switch locationFilter {
            case .excluded, .all: return true
            case .safe: return row.measurement.state == .measured && row.advice.verdict == .safe
            case .rebuild: return row.measurement.state == .measured && row.advice.verdict == .rebuild
            case .check: return row.measurement.state == .measured && row.advice.verdict == .check
            case .keep: return row.measurement.state == .measured && row.advice.verdict == .keep
            case .unscanned: return row.measurement.state == .pending
            case .growing: return (row.change.delta ?? 0) > 0 && (row.change.delta ?? 0) >= (row.policy.growthThresholdBytes ?? 0) && !row.policy.expected && (row.policy.reviewAfter ?? .distantPast) <= Date()
            case .reviewLater: return (row.policy.reviewAfter ?? .distantPast) > Date()
            case .inside: return !row.advice.staleItems.isEmpty
            }
        case .watching: return !off && row.policy.isWatched
        case .needsAttention: return !off && [.inaccessible, .limited, .failed].contains(row.measurement.state)
        default: return !off
        }
    }
    /// Scanned size under each Coverage place, from saved scans. Used to list places biggest first.
    /// Scan progress doesn't change it; the sizes refresh when the scan is saved.
    private var coverageCache: (key: Int, value: [String: Int64]) = (-1, [:])
    var coverageSizes: [String: Int64] {
        refreshDerived()
        let key = recordsVersion &* 1_000_003 &+ discoveryVersion
        if coverageCache.key == key { return coverageCache.value }
        let measured = derived.saved.values.filter { $0.state == .measured && !gone.contains($0.profile.path) }
        var value: [String: Int64] = [:]
        for entry in Coverage.entries {
            let root = entry.path(home: home)
            value[entry.id] = uniqueAllocatedTotal(measured.filter { containsPath(root, $0.profile.path) })
        }
        coverageCache = (key, value)
        return value
    }
    /// Old items inside folders you're still using: how many folders hold them and how much space they take.
    private var insideCache: (key: String, value: (folders: Int, bytes: Int64, biggest: String?)) = ("", (0, 0, nil))
    var unusedInside: (folders: Int, bytes: Int64, biggest: String?) {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if insideCache.key == key { return insideCache.value }
        let found = (verdictGroups[.check] ?? []).map { ($0, adviceFor($0)) }.filter { !$0.1.staleItems.isEmpty }.sorted { $0.1.staleBytes > $1.1.staleBytes }
        let value = (found.count, found.reduce(Int64(0)) { $0 + $1.1.staleBytes }, found.first?.0.profile.displayName)
        insideCache = (key, value)
        return value
    }
    /// Scanned size of a Coverage group, counting only places that are turned on (the ones a scan reads).
    /// What you could get back, by answer. Old items inside folders are counted apart from their folder's answer.
    struct Reclaim {
        var safe: (count: Int, bytes: Int64) = (0, 0)
        var inside: (folders: Int, bytes: Int64) = (0, 0)
        var rebuild: (count: Int, bytes: Int64) = (0, 0)
        var check: (count: Int, bytes: Int64) = (0, 0)
        var keep: (count: Int, bytes: Int64) = (0, 0)
        /// Safe, old items inside, and rebuildable: everything that costs at most a rebuild.
        var total: Int64 { safe.bytes + inside.bytes + rebuild.bytes }
    }
    private var reclaimCache: (key: String, value: Reclaim) = ("", Reclaim())
    var reclaim: Reclaim {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if reclaimCache.key == key { return reclaimCache.value }
        var value = Reclaim()
        // Count each byte once: only the outermost scanned folder counts, whatever its answer.
        let all = Verdict.allCases.flatMap { v in (verdictGroups[v] ?? []).map { ($0, v) } }.sorted { $0.0.profile.path.count < $1.0.profile.path.count }
        var accepted: Set<String> = []
        for (m, verdict) in all {
            let path = normalized(m.profile.path)
            guard !hasAncestor(in: accepted, path) else { continue }
            accepted.insert(path)
            let bytes = m.allocatedBytes ?? 0, inside = adviceFor(m).staleBytes
            switch verdict {
            case .safe: value.safe.bytes += bytes
            case .rebuild: value.rebuild.bytes += bytes - inside
            case .check: value.check.bytes += bytes - inside
            case .keep: value.keep.bytes += bytes
            }
            if inside > 0 { value.inside.folders += 1; value.inside.bytes += inside }
        }
        value.safe.count = verdictGroups[.safe]?.count ?? 0
        value.rebuild.count = verdictGroups[.rebuild]?.count ?? 0
        value.check.count = verdictGroups[.check]?.count ?? 0
        value.keep.count = verdictGroups[.keep]?.count ?? 0
        reclaimCache = (key, value)
        return value
    }
    /// Folders holding old items, biggest amount first.
    private var insideListCache: (key: String, value: [FolderMeasurement]) = ("", [])
    var insideFolders: [FolderMeasurement] {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if insideListCache.key == key { return insideListCache.value }
        let value = ((verdictGroups[.rebuild] ?? []) + (verdictGroups[.check] ?? [])).map { ($0, adviceFor($0).staleBytes) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        insideListCache = (key, value)
        return value
    }
    /// Where used space went since from, by place; plus the disk's own change over the same span.
    struct SpaceWent { var from: Date; var diskChange: Int64?; var places: [SpaceChange]; var explained: Int64 { places.reduce(0) { $0 + $1.bytes } } }
    private var wentCache: (key: String, value: SpaceWent?) = ("", nil)
    func spaceWent(days: Double = 7) -> SpaceWent? {
        let key = "\(recordsVersion)|\(discoveryVersion)|\(preferencesVersion)|\(usage.count)|\(days)"
        if wentCache.key == key { return wentCache.value }
        refreshDerived()
        let readings = usage
        let start = Date().addingTimeInterval(-days * 86400)
        guard let first = readings.first(where: { $0.date >= start }), let last = readings.last else { wentCache = (key, nil); return nil }
        let current = derived.saved.values.filter { !preferences.excluded($0.profile.path) && !gone.contains($0.profile.path) }
        let places = spaceChanges(history: derived.history, latest: Array(current), created: created, from: first.date, home: home)
        let value = SpaceWent(from: first.date, diskChange: last.used - first.used, places: places)
        wentCache = (key, value)
        return value
    }
    func groupSize(_ group: CoverageGroup) -> Int64 {
        Coverage.entries.filter { $0.group == group && !preferences.excluded($0.path(home: home)) }.reduce(0) { $0 + (coverageSizes[$1.id] ?? 0) }
    }
    /// A span of time since last use, with the scanned space in it by answer.
    struct IdleBucket: Identifiable { let id: Int; let title: String; var bytes: [Verdict: Int64] = [:]; var total: Int64 { bytes.values.reduce(0, +) } }
    private var idleCache: (key: String, value: [IdleBucket]) = ("", [])
    /// Scanned space by how long it has gone unused, split by answer. Folders inside others count once.
    var idleBuckets: [IdleBucket] {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if idleCache.key == key { return idleCache.value }
        let titles = ["This week", "This month", "1–3 months", "3+ months", "Unknown"]
        var items: [[Verdict: [FolderMeasurement]]] = Array(repeating: [:], count: titles.count)
        let now = Date()
        for (verdict, group) in verdictGroups {
            for item in group {
                let days = adviceFor(item).lastUsed.map { now.timeIntervalSince($0) / 86400 }
                let index = days.map { $0 < 7 ? 0 : $0 < 30 ? 1 : $0 < 90 ? 2 : 3 } ?? 4
                items[index][verdict, default: []].append(item)
            }
        }
        let value = titles.enumerated().map { index, title in IdleBucket(id: index, title: title, bytes: items[index].mapValues { uniqueAllocatedTotal($0) }) }
        idleCache = (key, value)
        return value
    }
    /// Folders you keep or turned off, with their last known sizes: the Kept view's totals.
    struct KeptSummary { var kept: [FolderMeasurement] = []; var keptBytes: Int64 = 0; var off: [FolderMeasurement] = []; var offBytes: Int64 = 0 }
    private var keptCache: (key: String, value: KeptSummary) = ("", KeptSummary())
    var keptSummary: KeptSummary {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if keptCache.key == key { return keptCache.value }
        var summary = KeptSummary()
        for item in baseMeasures() where !gone.contains(item.profile.path) && item.allocatedBytes != nil {
            if preferences.excluded(item.profile.path) { summary.off.append(item) }
            else if preferences.policy(item.profile.path).isKept { summary.kept.append(item) }
        }
        // Turned-off folders keep their last scanned size; count it even though the state isn't "measured".
        summary.keptBytes = uniqueAllocatedTotal(summary.kept)
        summary.offBytes = uniqueAllocatedTotal(summary.off.map { var m = $0; m.state = .measured; return m })
        keptCache = (key, summary)
        return summary
    }
    /// Locations that could not be measured completely, for the sidebar badge.
    var attentionCount: Int { overview.attentionCount }
    /// Measurements for every selected row, with unique allocated bytes (nested folders counted once).
    var selectionSummary: (items: [FolderMeasurement], bytes: Int64, unmeasured: Int)? {
        guard selection.count > 1 else { return nil }
        let items = latest.filter { selection.contains($0.profile.path) }
        let measured = items.filter { $0.state == .measured }
        return (items, uniqueAllocatedTotal(measured), selection.count - measured.count)
    }
    /// Growth over a comparable pair that is large enough to matter: at least 1 GiB or the location's own threshold.
    static let autoWatchFloor: Int64 = 1_073_741_824
    /// Adds locations that grew across two comparable scans to Watching, remembering that the app did it so the user can undo.
    func autoWatch(after record: ScanRecord) {
        guard let store else { return }
        var next = preferences, added: [String] = []
        for item in record.measurements where item.state == .measured {
            let path = item.profile.path, policy = next.policy(path)
            guard !policy.isWatched, !policy.expected, !next.excluded(path), let delta = growthSummary(path).delta else { continue }
            guard delta >= max(Self.autoWatchFloor, policy.growthThresholdBytes ?? 0) else { continue }
            var updated = policy; updated.isWatched = true; updated.autoWatched = true; updated.autoWatchedBytes = delta
            next.locations[normalized(path)] = updated; added.append(path)
        }
        guard !added.isEmpty else { return }
        do { try store.save(next); preferences = next; lastAutoWatched = added }
        catch { self.error = "Watching could not be saved: \(error.localizedDescription)" }
    }
    @Published var lastAutoWatched: [String] = []
    func undoAutoWatch(_ path: String) { policy(path) { $0.isWatched = false; $0.autoWatched = nil; $0.autoWatchedBytes = nil }; lastAutoWatched.removeAll { $0 == path } }
    var chosen: FolderMeasurement? {
        guard let selected else { return nil }
        let saved = (latest.filter { $0.profile.path == selected } + [inspected[selected]].compactMap { $0 }).max { $0.observedAt < $1.observedAt } ?? rows.first(where: { $0.id == selected })?.measurement
        return saved.map { withSimulatorFacts($0, devices: simDevices) }
    }
    var lastScan: ScanRecord? { records.last }
    func policy(_ path: String, _ change: (inout LocationPolicy) -> Void) {
        guard let store else { error = "Preferences cannot be saved while storage is unavailable."; return }
        var next = preferences, p = next.policy(path); change(&p); next.locations[normalized(path)] = p
        do { try store.save(next); preferences = next }
        catch { self.error = "Preferences were not saved: \(error.localizedDescription)" }
    }
    func setAppearance(_ value: String) {
        guard ["System", "Light", "Dark"].contains(value), let store else { return }
        var next = preferences; next.appearance = value
        do { try store.save(next); preferences = next }
        catch { self.error = "Appearance could not be saved: \(error.localizedDescription)" }
    }
    func setDaily(_ value: Bool) { updatePreferences { $0.dailyWhileOpen = value; $0.schedule = value ? "daily" : "off" } }
    /// Single save path for every preference change; each save appends a new event.
    func updatePreferences(_ change: (inout Preferences) -> Void) {
        guard let store else { error = "Preferences cannot be saved while storage is unavailable."; return }
        var next = preferences; change(&next)
        do { try store.save(next); preferences = next } catch { self.error = "Preferences were not saved: \(error.localizedDescription)" }
    }
    var effectiveDarkAppearance: Bool {
        switch preferences.appearance ?? "System" {
        case "Dark": return true
        case "Light": return false
        default: return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
    func toggleAppearance() { setAppearance(effectiveDarkAppearance ? "Light" : "Dark") }
    var canRescanSelection: Bool {
        selection.count == 1 && selected != nil && !preferences.excluded(selected!) && !running && !inspecting && !discovering && store != nil
    }
    func toggleAppearance(current: ColorScheme) {
        setAppearance(current == .dark ? "Light" : "Dark")
    }
    func checkScheduledPass(now: Date = Date()) {
        guard let store, !running, !inspecting, !discovering, ScanPlanner.dailyDue(preferences, now: now) else { return }
        var next = preferences; next.lastScheduledAttempt = now
        do { try store.save(next); preferences = next }
        catch { self.error = "Daily attempt could not be recorded: \(error.localizedDescription)"; return }
        scan(priorityOnly: true)
    }
    func cancelWork() {
        cancellation.cancel()
        progress = "Stopping after the current filesystem request returns. A macOS permission prompt may need your response."
    }
    func acceptDiscovery(_ found: Discovery) {
        var known = Dictionary(uniqueKeysWithValues: discovery.profiles.map { ($0.path, $0) })
        for profile in found.profiles { known[profile.path] = profile }
        discovery = Discovery(profiles: known.values.sorted { $0.path < $1.path }, notes: found.notes, complete: found.complete)
    }
    func discover() {
        guard !running, !inspecting, !discovering else { return }
        discovering = true; cancellation = Cancellation(); let token = cancellation
        progress = "Discovering locations; macOS may request access…"
        let prefs = preferences, home = home
        DispatchQueue.global(qos: .utility).async {
            let result = Inventory.discover(home: home, preferences: prefs, cancellation: token) { path in
                DispatchQueue.main.async { if !token.stopped { self.progress = "Discovering: " + path + " · macOS may request access" } }
            }
            DispatchQueue.main.async { self.acceptDiscovery(result); self.discovering = false; self.recordDiscovery() }
        }
    }
    func recordDiscovery() {
        guard let store else { return }
        var next = preferences
        if discovery.complete != false { next.lastDiscovery = Date() }
        do { try store.saveDiscovery(discovery); try store.save(next); preferences = next } catch { self.error = "Discovery could not be fully saved: \(error.localizedDescription)" }
    }
    func addRoot() {
        guard let store else { error = "Preferences cannot be saved while storage is unavailable."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to scan. Context Cleaner only reads its size and never changes it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var next = preferences
        if !next.customRoots.contains(url.path) { next.customRoots.append(url.path) }
        do {
            try store.save(next); preferences = next
            if !preferences.excluded(url.path), !discovery.profiles.contains(where: { $0.path == url.path }) {
                discovery.profiles.append(Classifier.profile(path: url.path, home: home, readMetadata: false))
            }
            selected = url.path; categoryFilter = nil; section = .locations; locationFilter = .all; search = ""
        } catch { self.error = error.localizedDescription }
    }
    func scan(selectedOnly: Bool = false, watchedOnly: Bool = false, priorityOnly: Bool = false) {
        guard !running, !inspecting, !discovering, store != nil else { return }
        if selectedOnly, let selected, preferences.excluded(selected) { error = "This location is excluded. Include it again before scanning."; return }
        cancellation = Cancellation(); let token = cancellation, prefs = preferences, home = home, path = selected
        let known = discovery.profiles, history = records, now = Date()
        // A full scan also re-measures every saved folder that's still on disk (for example sizes imported from
        // SpaceCheck), so every row gets a fresh size and a last-changed date, not only newly discovered ones.
        let saved = latest.map(\.profile).filter { !gone.contains($0.path) && !fileOnly.contains($0.path) && !preferences.excluded($0.path) }
        running = true; partial = []; completed = 0; targetCount = 0
        progress = selectedOnly ? "Checking selected location…" : "Discovering locations; macOS may request access…"
        let scope = selectedOnly ? "Selected folder" : watchedOnly ? "Watched locations" : priorityOnly ? "Priority locations (up to \(preferences.effectivePriorityCount))" : "Known and selected locations"
        // A scan you start runs at normal priority; background checks stay low so they never slow your Mac.
        DispatchQueue.global(qos: priorityOnly ? .utility : .userInitiated).async {
            let found: Discovery
            if selectedOnly, let path { found = Discovery(profiles: [Classifier.profile(path: path, home: home, preferences: prefs)], notes: ["Selected folder only; exclusions apply."]) }
            else if watchedOnly {
                let paths = prefs.locations.filter { $0.value.isWatched && !prefs.excluded($0.key) }.map(\.key).sorted()
                found = Discovery(profiles: paths.map { Classifier.profile(path: $0, home: home, preferences: prefs) }, notes: ["Watchlist only; no broad discovery. Missing watched paths are recorded as missing."])
            } else if priorityOnly && !ScanPlanner.discoveryDue(prefs, now: now) {
                found = Discovery(profiles: known, notes: ["Priority pass over saved locations. Discovery is due every seven days while periodic checks are enabled."])
            } else { found = Inventory.discover(home: home, preferences: prefs, cancellation: token) { path in
                DispatchQueue.main.async { if !token.stopped { self.progress = "Discovering: " + path + " · macOS may request access" } }
            } }
            var candidates = found.profiles
            if !selectedOnly && !watchedOnly && !priorityOnly { candidates += savedProfilesToRefresh(saved, discovered: found.profiles) }
            let profiles = priorityOnly ? ScanPlanner.priority(found.profiles, preferences: prefs, records: history, now: now, limit: prefs.effectivePriorityCount) : candidates
            let rediscovered = !selectedOnly && !watchedOnly && (!priorityOnly || ScanPlanner.discoveryDue(prefs, now: now))
            DispatchQueue.main.async {
                if !selectedOnly && !watchedOnly { self.acceptDiscovery(found) }
                if rediscovered { self.recordDiscovery() }
                self.progress = "Preparing the folder scan…"
            }
            guard !profiles.isEmpty else {
                DispatchQueue.main.async { self.error = "No included locations match this scan. Add a location or change your filters."; self.running = false }
                return
            }
            // Ask macOS about protected folders before the timed scan starts, so a waiting dialog can't use up the time.
            for root in ["Documents", "Desktop", "Downloads"].map({ home + "/" + $0 }) where !token.stopped && profiles.contains(where: { containsPath(root, $0.path) }) {
                DispatchQueue.main.async { self.progress = "Asking macOS for access to " + root + "/" }
                _ = try? DirectoryCursor(root)
            }
            DispatchQueue.main.async { self.targetCount = profiles.count; self.progress = "Preparing the folder scan…" }
            // Finished folders reach the interface in small batches, so a fast scan doesn't redraw the window for every folder.
            let batch = ScanBatch()
            let record = ScanEngine.scan(profiles: profiles, preferences: prefs, scope: scope, notes: found.notes, cancellation: token, limits: priorityOnly ? .priority : prefs.manualLimits, totalSeconds: priorityOnly ? 90 : 1800, concurrency: priorityOnly ? 1 : 4) { item, done, total in
                guard batch.add(item, done: done) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    let (items, count) = batch.drain()
                    guard !items.isEmpty else { return }
                    self.partial.append(contentsOf: items); self.completed = max(self.completed, count); self.progress = items.last!.profile.name
                }
            }
            DispatchQueue.main.async {
                self.records.append(record); self.refreshVolume(); self.refreshGone(); self.loadSimDevices(); self.refreshProjects()
                do { try self.store?.append(record) }
                catch { self.error = "Scan is available in memory but could not be saved: \(error.localizedDescription)" }
                self.autoWatch(after: record)
                let grew = record.measurements.filter { $0.state == .measured && (self.growthSummary($0.profile.path).delta ?? 0) > 0 }.count
                self.lastResult = scanOutcome(record, grew: grew)
                self.running = false; self.progress = self.lastResult ?? record.resultSummary
            }
        }
    }
    func inspectChildren(_ item: FolderMeasurement, simulatorApps: Bool = false) {
        guard !inspecting, !running, store != nil, !preferences.excluded(item.profile.path) else { return }
        let prefs = preferences, home = home
        children = []; childrenParent = item.profile.path; inspected[item.profile.path] = item
        inspecting = true; inspectionCancellation = Cancellation(); let token = inspectionCancellation
        DispatchQueue.global(qos: .utility).async {
            do {
                let paths: [String]
                var listingNotes = ["Children of " + item.profile.path]
                if simulatorApps, let device = SimulatorLocations.deviceRoot(item.profile.path) {
                    paths = try SimulatorLocations.containers(device, preferences: prefs)
                } else {
                    let listing = DirectoryListing.read(item.profile.path, preferences: prefs, cancellation: token)
                    paths = listing.names.map { item.profile.path == "/" ? "/" + $0 : item.profile.path + "/" + $0 }
                    if let note = listing.note { listingNotes.append(note); DispatchQueue.main.async { self.error = note } }
                }
                let profiles = paths.map { Classifier.profile(path: $0, home: home, preferences: prefs) }
                let record = ScanEngine.scan(profiles: profiles, preferences: prefs, scope: simulatorApps ? "Simulator apps and data" : "Immediate children", notes: listingNotes, cancellation: token) { child,_,_ in
                    DispatchQueue.main.async { self.children.append(child); self.inspected[child.profile.path] = child }
                }
                DispatchQueue.main.async {
                    self.records.append(record); self.refreshVolume()
                    do { try self.store?.append(record) } catch { self.error = "Inspection could not be saved: \(error.localizedDescription)" }
                }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
            DispatchQueue.main.async { self.inspecting = false }
        }
    }
    func identifySimulatorDevices(_ item: FolderMeasurement) {
        let parent = item.profile.path
        guard parent.hasSuffix("/CoreSimulator/Devices"), !identifyingDevices, !preferences.excluded(parent) else { return }
        identifyingDevices = true; simulatorDevices = []; simulatorDeviceParent = parent
        let prefs = preferences, home = home
        DispatchQueue.global(qos: .utility).async {
            do {
                guard MetadataReader.hasNoSymlinkComponents(parent) else { throw CocoaError(.fileReadNoPermission) }
                let listing = DirectoryListing.read(parent, preferences: prefs)
                let names = listing.names
                if let note = listing.note { DispatchQueue.main.async { self.error = note } }
                let profiles = names.filter { UUID(uuidString: $0) != nil }.map { parent + "/" + $0 }.filter { !prefs.excluded($0) && MetadataReader.hasNoSymlinkComponents($0) }.map { Classifier.profile(path: $0, home: home, preferences: prefs) }
                DispatchQueue.main.async { self.simulatorDevices = profiles; self.identifyingDevices = false }
            } catch { DispatchQueue.main.async { self.error = "Device metadata could not be read: \(error.localizedDescription)"; self.identifyingDevices = false } }
        }
    }
    @Published var showingScanPlan = false
    @Published var reportPreview: String?
    /// Builds the cleanup checklist: safe items, unused items inside busy folders, check first, keep. Biggest first.
    func buildReport() -> String {
        let stamp = Date().formatted(date: .long, time: .shortened)
        var text = "# Context Cleaner cleanup list\n\n\(stamp)"
        if let v = volume { text += " · \(byteLabel(v.free)) free of \(byteLabel(v.total)) (\(usedPercentText(Double(v.used) / Double(max(v.total, 1)))) used)" }
        text += "\n\n"
        let week = UsageRange.week.window(endingAt: usage.last?.date ?? Date())
        if let change = usageChange(usage, from: week.lowerBound, to: week.upperBound) {
            text += "Free space in the last 7 days: \(byteLabel(change.from.free)) → \(byteLabel(change.to.free)).\n\n"
        }
        text += "Context Cleaner never deletes anything. Tick items off as you remove them yourself, in Finder or with the command shown. Space comes back when you empty the Trash. Sizes are from each folder's latest scan; folders inside others are counted once in totals.\n\n"
        func line(_ m: FolderMeasurement, _ a: Advice) -> String {
            "**\(m.profile.displayName.replacingOccurrences(of: "*", with: ""))** · \(m.allocatedBytes.map(byteLabel) ?? "size unknown") · \(a.short)"
        }
        let safe = verdictGroups[.safe] ?? [], rebuild = verdictGroups[.rebuild] ?? [], check = verdictGroups[.check] ?? [], keep = verdictGroups[.keep] ?? []
        text += "## 1. Safe to remove · \(byteLabel(uniqueAllocatedTotal(safe))) in \(safe.count) \(safe.count == 1 ? "folder" : "folders")\n\n"
        text += safe.isEmpty ? "Nothing yet. Scan again after a few days of normal work.\n\n" : ""
        for m in safe {
            let a = adviceFor(m)
            text += "- [ ] " + line(m, a) + "\n  `\(m.profile.path)`\n  \(a.howTo)" + (a.command.map { " `\($0)`" } ?? "") + "\n"
        }
        let inside = insideFolders.map { ($0, adviceFor($0)) }
        text += "\n## 2. Old items inside folders · \(byteLabel(inside.reduce(0) { $0 + $1.1.staleBytes }))\n\n"
        text += inside.isEmpty ? "None found.\n\n" : "Old builds, experiments and downloads that haven't changed in a week (project folders) or a month (caches). The folder itself is still in use.\n\n"
        for (m, a) in inside {
            text += "- [ ] **\(m.profile.displayName)** · \(byteLabel(a.staleBytes)) in \(a.staleItems.count) \(a.staleItems.count == 1 ? "item" : "items")\n"
            for item in a.staleItems.prefix(8) { text += "  - \(item.name) · \(byteLabel(item.bytes))\(item.modifiedAt.map { " · changed " + ageText($0) } ?? "")\n" }
            text += "  Move them to the Trash: `\(trashCommand(a.staleItems.map(\.path)))`\n"
        }
        text += "\n## 3. Rebuildable · \(byteLabel(uniqueAllocatedTotal(rebuild))) in \(rebuild.count) \(rebuild.count == 1 ? "folder" : "folders")\n\nIn use, but rebuilt or downloaded again if you remove them. Remove between builds.\n\n"
        for m in rebuild.prefix(40) {
            let a = adviceFor(m)
            text += "- [ ] " + line(m, a) + "\n  `\(m.profile.path)`\n"
        }
        text += "\n## 4. Your call · \(byteLabel(uniqueAllocatedTotal(check))) in \(check.count) \(check.count == 1 ? "folder" : "folders")\n\nMay hold the only copy of something. Look at each first. Biggest first.\n\n"
        for m in check.prefix(40) {
            let a = adviceFor(m)
            text += "- " + line(m, a) + "\n  \(a.reason)\n" + a.evidence.map { "  \($0)\n" }.joined() + "  `\(m.profile.path)`\n"
        }
        if check.count > 40 { text += "- and \(check.count - 40) more in the app\n" }
        let kept = keptSummary
        text += "\n## 5. Keep · \(byteLabel(uniqueAllocatedTotal(keep) + kept.keptBytes))\n\nApp libraries, chat history and folders you chose to keep. Manage these inside their own apps.\n\n"
        for m in keep + kept.kept { text += "- **\(m.profile.displayName)** · \(m.allocatedBytes.map(byteLabel) ?? "size unknown")\n" }
        return text
    }
    func exportReport() { reportPreview = buildReport() }
    func saveReport(_ text: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Cleanup list \(Date().formatted(.iso8601.year().month().day())).md"
        panel.message = "Saves your cleanup list as a Markdown checklist. An existing file with the same name is never replaced."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try writeNew(Data(text.utf8), to: url); reportPreview = nil }
        catch { self.error = "The cleanup list was not saved because a file already exists there. Choose a new name. \(error.localizedDescription)" }
    }
}
