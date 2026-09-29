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
    var growing: Bool { (change.delta ?? 0) > 0 && (change.delta ?? 0) >= (policy.growthThresholdBytes ?? 0) && !policy.expected }
    /// One plain word, shown only when it tells you something. Empty for an ordinary scanned folder.
    var status: String {
        if policy.excluded { return "Excluded" }
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
    /// Checks which known folders are gone. Metadata only.
    func refreshGone() {
        let paths = Array(Set(discovery.profiles.map(\.path) + latest.map(\.profile.path)))
        DispatchQueue.global(qos: .utility).async {
            let missing = missingPaths(paths)
            let files = fileOnlyPaths(paths)
            DispatchQueue.main.async {
                if missing != self.gone { self.gone = missing }
                if files != self.fileOnly { self.fileOnly = files }
            }
        }
    }
    func adviceFor(_ m: FolderMeasurement) -> Advice { advice(for: m, policy: preferences.policy(m.profile.path), devices: simDevices) }
    func deviceAdvice(_ device: SimDevice) -> Advice {
        let profile = FolderProfile(path: home + "/Library/Developer/CoreSimulator/Devices/" + device.udid, name: device.name, category: .simulator, project: nil, associatedApp: "Apple CoreSimulator", explanation: "", consequence: "", evidence: [])
        return advice(for: FolderMeasurement(profile: profile, observedAt: Date(), state: .measured, fileCount: 0, processes: [], activityCheckAvailable: false, elapsedSeconds: 0), policy: LocationPolicy(), devices: simDevices)
    }
    func refreshVolume() { volume = VolumeSnapshot.read(); recordCapacityIfDue() }
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
    }
    // Derived state is rebuilt only when its inputs change; SwiftUI reads these many times per frame.
    private struct Derived { var key = ""; var latest: [FolderMeasurement] = []; var history: [String: [HistoryPoint]] = [:]; var growth: [String: GrowthSummary] = [:] }
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
        var byPath: [String: FolderMeasurement] = [:]
        for record in records.sorted(by: { $0.finishedAt < $1.finishedAt }) {
            for item in record.measurements where item.state != .cancelled { byPath[item.profile.path] = item }
        }
        if running { for item in partial { byPath[item.profile.path] = item } }
        let history = historyIndex(records)
        derived = Derived(key: key, latest: Array(byPath.values), history: history, growth: history.mapValues { growth(points: $0) })
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
        for item in current where !excluded(item.profile.path) && [.inaccessible, .limited, .missing, .failed].contains(item.state) { attention.insert(item.profile.path) }
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
    private func baseMeasures() -> [FolderMeasurement] {
        var measures = latest
        for profile in discovery.profiles where !fileOnly.contains(profile.path) && !measures.contains(where: { $0.profile.path == profile.path }) {
            measures.append(FolderMeasurement(profile: profile, observedAt: Date(), state: .pending, fileCount: 0, processes: [], activityCheckAvailable: false, diagnostic: "Discovered; not yet measured.", elapsedSeconds: 0))
        }
        // Excluded locations remain manageable even if they have never been measured.
        for (path, policy) in preferences.locations where policy.excluded && !measures.contains(where: { $0.profile.path == path }) {
            measures.append(FolderMeasurement(profile: Classifier.profile(path: path, home: home, readMetadata: false), observedAt: Date(), state: .excluded, fileCount: 0, processes: [], activityCheckAvailable: false, diagnostic: "Excluded by you.", elapsedSeconds: 0))
        }
        return measures.map { withSimulatorFacts($0, devices: simDevices) }
    }
    /// Scanned, included folders still on disk, grouped by answer and sorted largest first.
    /// The Folders tiles, the Overview and the Safe to remove list all read this.
    private var verdictCache: (key: String, value: [Verdict: [FolderMeasurement]]) = ("", [:])
    var verdictGroups: [Verdict: [FolderMeasurement]] {
        let key = derivedKey + "|\(preferencesVersion)|\(discoveryVersion)"
        if verdictCache.key == key { return verdictCache.value }
        var groups: [Verdict: [FolderMeasurement]] = [:]
        for item in baseMeasures() where item.state == .measured && !preferences.excluded(item.profile.path) && !gone.contains(item.profile.path) {
            groups[adviceFor(item).verdict, default: []].append(item)
        }
        let value = groups.mapValues { $0.sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) } }
        verdictCache = (key, value)
        return value
    }
    /// Count and size for one answer, nested folders counted once.
    func verdictTotal(_ verdict: Verdict) -> (count: Int, bytes: Int64) {
        let items = verdictGroups[verdict] ?? []
        return (items.count, uniqueAllocatedTotal(items))
    }
    private func include(_ row: FolderRow, _ p: FolderProfile) -> Bool {
            switch section {
            case .locations:
                switch locationFilter {
                case .excluded: return row.policy.excluded
                case .all: return !preferences.excluded(p.path) && !row.gone
                case .safe: return !preferences.excluded(p.path) && !row.gone && row.measurement.state == .measured && row.advice.verdict == .safe
                case .check: return !preferences.excluded(p.path) && !row.gone && row.measurement.state == .measured && row.advice.verdict == .check
                case .keep: return !preferences.excluded(p.path) && !row.gone && row.measurement.state == .measured && row.advice.verdict == .keep
                case .unscanned: return !preferences.excluded(p.path) && !row.gone && row.measurement.state == .pending
                case .growing: return !preferences.excluded(p.path) && !row.gone && (row.change.delta ?? 0) > 0 && (row.change.delta ?? 0) >= (row.policy.growthThresholdBytes ?? 0) && !row.policy.expected && (row.policy.reviewAfter ?? .distantPast) <= Date()
                case .reviewLater: return !preferences.excluded(p.path) && (row.policy.reviewAfter ?? .distantPast) > Date()
                }
            case .watching: return !preferences.excluded(p.path) && (row.policy.isWatched)
            case .needsAttention: return !preferences.excluded(p.path) && [.inaccessible, .limited, .missing, .failed].contains(row.measurement.state)
            default: return !preferences.excluded(p.path)
            }
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
        running = true; partial = []; completed = 0; targetCount = 0
        progress = selectedOnly ? "Checking selected location…" : "Discovering locations; macOS may request access…"
        let scope = selectedOnly ? "Selected folder" : watchedOnly ? "Watched locations" : priorityOnly ? "Priority locations (up to \(preferences.effectivePriorityCount))" : "Known and selected locations"
        DispatchQueue.global(qos: .utility).async {
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
            let profiles = priorityOnly ? ScanPlanner.priority(found.profiles, preferences: prefs, records: history, now: now, limit: prefs.effectivePriorityCount) : found.profiles
            let rediscovered = !selectedOnly && !watchedOnly && (!priorityOnly || ScanPlanner.discoveryDue(prefs, now: now))
            DispatchQueue.main.async {
                if !selectedOnly && !watchedOnly { self.acceptDiscovery(found) }
                if rediscovered { self.recordDiscovery() }
                self.targetCount = profiles.count; self.progress = "Preparing the folder scan…"
            }
            guard !profiles.isEmpty else {
                DispatchQueue.main.async { self.error = "No included locations match this scan. Add a location or change your filters."; self.running = false }
                return
            }
            let record = ScanEngine.scan(profiles: profiles, preferences: prefs, scope: scope, notes: found.notes, cancellation: token, limits: priorityOnly ? .priority : prefs.manualLimits, totalSeconds: priorityOnly ? 90 : 900) { item, index, total in
                DispatchQueue.main.async { self.partial.append(item); self.completed = index; self.progress = item.profile.name }
            }
            DispatchQueue.main.async {
                self.records.append(record); self.refreshVolume(); self.refreshGone(); self.loadSimDevices()
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
    /// Builds the Markdown report for the current view: every visible location, largest first.
    func buildReport() -> String {
        let stamp = Date().formatted(date: .long, time: .shortened)
        var text = "# Context Cleaner report\n\n\(stamp) · \(section == .overview || section == .history ? "All included folders" : section.rawValue)\(section == .locations ? " · \(locationFilter.rawValue)" : "")\(search.isEmpty ? "" : " · matching “\(search)”")\n\n"
        if let v = volume { text += "Disk: \(byteLabel(v.free)) free of \(byteLabel(v.total)), checked \(v.date.formatted(date: .omitted, time: .shortened)).\n\n" }
        let week = UsageRange.week.window(endingAt: usage.last?.date ?? Date())
        if let change = usageChange(usage, from: week.lowerBound, to: week.upperBound) {
            text += "Space used in the last 7 days: \(signedBytes(change.delta)) (\(byteLabel(change.from.used)) on \(change.from.date.formatted(date: .abbreviated, time: .shortened)) → \(byteLabel(change.to.used)) on \(change.to.date.formatted(date: .abbreviated, time: .shortened))).\n\n"
        }
        text += "Context Cleaner never deletes files. Sizes are estimates from the latest scan of each folder. A folder inside another may appear in both rows, and APFS shares storage between files, so removing a folder can free less than its size.\n\n"
        let listed = rows.sorted(by: { $0.bytes > $1.bytes })
        text += "| Folder | Size | Change | Status | App or project |\n|---|---:|---:|---|---|\n"
        for row in listed {
            let change = row.change.delta.map { "\($0 >= 0 ? "+" : "−")\(byteLabel(abs($0)))" } ?? "—"
            text += "| \(row.name.replacingOccurrences(of: "|", with: "/")) | \(row.bytes >= 0 ? byteLabel(row.bytes) : "not measured") | \(change) | \(row.status.isEmpty ? "Scanned" : row.status) | \(row.app) |\n"
        }
        text += "\n"
        for row in listed {
            let p = row.measurement.profile
            text += "## \(p.name)\n\n`\(p.path)`\n\n\(row.bytes >= 0 ? byteLabel(row.bytes) : "Not measured") · \(row.category) · \(row.status.isEmpty ? "Scanned" : row.status)\n\n\(p.explanation)\n\nBefore any manual change: \(p.consequence)\n\n"
            for e in p.evidence { text += "- \(e.level.rawValue): \(e.label) — \(e.value)\n" }
            let policy = preferences.policy(p.path)
            if !policy.tags.isEmpty { text += "\nTags: \(policy.tags.joined(separator: ", "))\n" }
            if !policy.note.isEmpty { text += "\nNote: \(policy.note)\n" }
            text += "\n"
        }
        return text
    }
    func exportReport() { reportPreview = buildReport() }
    func saveReport(_ text: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Context Cleaner report \(Date().formatted(.iso8601.year().month().day())).md"
        panel.message = "Saves a Markdown report. An existing file with the same name is never replaced."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try writeNew(Data(text.utf8), to: url); reportPreview = nil }
        catch { self.error = "The report was not saved because a file already exists there. Choose a new name. \(error.localizedDescription)" }
    }
}
