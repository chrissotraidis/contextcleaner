import Foundation
import SwiftUI
import AppKit

struct FolderRow: Identifiable {
    var id: String { measurement.profile.path }
    var measurement: FolderMeasurement
    var policy: LocationPolicy
    var change: GrowthSummary
    var name: String { measurement.profile.name }
    var app: String { measurement.profile.project ?? measurement.profile.associatedApp }
    var bytes: Int64 { measurement.allocatedBytes ?? -1 }
    var delta: Int64 { change.delta ?? Int64.min }
    var category: String { measurement.profile.category.rawValue }
    var status: String {
        if policy.excluded { return "Excluded" }
        if measurement.state == .pending { return "Not scanned" }
        if measurement.state != .measured { return measurement.state.rawValue.capitalized }
        if (policy.reviewAfter ?? .distantPast) > Date() { return "Review later" }
        if policy.expected { return "Expected" }
        if !measurement.processes.isEmpty { return "Open handles" }
        
        if policy.recurring { return "Recurring review" }
        if policy.watched { return "Watching" }
        return "Measured"
    }
}
@MainActor final class CleanerModel: ObservableObject {
    @Published var records: [ScanRecord] = []
    @Published var preferences = Preferences()
    @Published var discovery = Discovery(profiles: [], notes: [])
    @Published var selected: String?
    @Published var section: AppSection = .overview
    @Published var locationFilter: LocationFilter = .all
    @Published var editing: String?
    @Published var search = ""
    @Published var categoryFilter: FolderCategory?
    @Published var volume = VolumeSnapshot.read()
    func refreshVolume() { volume = VolumeSnapshot.read() }
    @Published var running = false
    @Published var progress = "Ready"
    @Published var completed = 0
    @Published var targetCount = 0
    @Published var partial: [FolderMeasurement] = []
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
            discovery = storage.learnedDiscovery() ?? Discovery(profiles: [], notes: [])
            store = storage
            error = storage.warnings.isEmpty ? nil : storage.warnings.joined(separator: "\n")
        } catch { store = nil; self.error = "Storage unavailable; scanning is disabled to avoid losing history. \(error.localizedDescription)" }
        var saved = Dictionary(uniqueKeysWithValues: discovery.profiles.map { ($0.path, $0) })
        for path in preferences.customRoots where saved[path] == nil { saved[path] = Classifier.profile(path: path, home: home, readMetadata: false) }
        for record in records { for item in record.measurements { saved[item.profile.path] = item.profile } }
        discovery = Discovery(profiles: saved.values.sorted { $0.path < $1.path }, notes: ["Showing saved locations. Discovery runs only when requested. Coverage is recognized development/cache locations and your selected roots, not the whole disk."])
    }
    var latest: [FolderMeasurement] {
        var byPath: [String: FolderMeasurement] = [:]
        for record in records.sorted(by: { $0.finishedAt < $1.finishedAt }) {
            for item in record.measurements where item.state != .cancelled { byPath[item.profile.path] = item }
        }
        if running { for item in partial { byPath[item.profile.path] = item } }
        return Array(byPath.values)
    }
    var rows: [FolderRow] {
        var measures = latest
        for profile in discovery.profiles where !measures.contains(where: { $0.profile.path == profile.path }) {
            measures.append(FolderMeasurement(profile: profile, observedAt: Date(), state: .pending, fileCount: 0, processes: [], activityCheckAvailable: false, diagnostic: "Discovered; not yet measured.", elapsedSeconds: 0))
        }
        // Excluded locations remain manageable even if they have never been measured.
        for (path, policy) in preferences.locations where policy.excluded && !measures.contains(where: { $0.profile.path == path }) {
            measures.append(FolderMeasurement(profile: Classifier.profile(path: path, home: home, readMetadata: false), observedAt: Date(), state: .excluded, fileCount: 0, processes: [], activityCheckAvailable: false, diagnostic: "Excluded by you.", elapsedSeconds: 0))
        }
        return measures.map { FolderRow(measurement: $0, policy: preferences.policy($0.profile.path), change: growth($0.profile.path, records: records)) }.filter { row in
            let p = row.measurement.profile
            if let categoryFilter, p.category != categoryFilter { return false }
            guard search.isEmpty || (p.path + p.name + p.associatedApp + (p.project ?? "") + row.policy.tags.joined()).localizedCaseInsensitiveContains(search) else { return false }
            switch section {
            case .locations:
                switch locationFilter {
                case .excluded: return row.policy.excluded
                case .all: return !preferences.excluded(p.path)
                case .growing: return !preferences.excluded(p.path) && (row.change.delta ?? 0) > 0 && (row.change.delta ?? 0) >= (row.policy.growthThresholdBytes ?? 0) && !row.policy.expected && (row.policy.reviewAfter ?? .distantPast) <= Date()
                case .reviewLater: return !preferences.excluded(p.path) && (row.policy.reviewAfter ?? .distantPast) > Date()
                case .rebuildable: return !preferences.excluded(p.path) && p.category.reproducible && row.measurement.state == .measured && row.measurement.activityCheckAvailable && row.measurement.processes.isEmpty && !row.policy.expected && (row.policy.reviewAfter ?? .distantPast) <= Date()
                }
            case .watching: return !preferences.excluded(p.path) && (row.policy.watched || row.policy.recurring)
            case .needsAttention: return !preferences.excluded(p.path) && [.inaccessible, .limited, .missing, .failed, .pending].contains(row.measurement.state)
            default: return !preferences.excluded(p.path)
            }
        }
    }
    /// Locations that could not be measured completely, for the sidebar badge.
    var attentionCount: Int {
        var paths = Set<String>()
        let current = latest
        for item in current where !preferences.excluded(item.profile.path) && [.inaccessible, .limited, .missing, .failed].contains(item.state) { paths.insert(item.profile.path) }
        for profile in discovery.profiles where !preferences.excluded(profile.path) && !current.contains(where: { $0.profile.path == profile.path }) { paths.insert(profile.path) }
        return paths.count
    }
    var chosen: FolderMeasurement? {
        guard let selected else { return nil }
        return (latest.filter { $0.profile.path == selected } + [inspected[selected]].compactMap { $0 }).max { $0.observedAt < $1.observedAt } ?? rows.first(where: { $0.id == selected })?.measurement
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
    func setDaily(_ value: Bool) {
        guard let store else { error = "Preferences cannot be saved while storage is unavailable."; return }
        var next = preferences; next.dailyWhileOpen = value
        do { try store.save(next); preferences = next } catch { self.error = error.localizedDescription }
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
        panel.message = "Choose a location to inspect. Context Cleaner never deletes its contents."
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
        let scope = selectedOnly ? "Selected folder" : watchedOnly ? "Watched locations" : priorityOnly ? "Priority locations (up to 12)" : "Known and selected locations"
        DispatchQueue.global(qos: .utility).async {
            let found: Discovery
            if selectedOnly, let path { found = Discovery(profiles: [Classifier.profile(path: path, home: home, preferences: prefs)], notes: ["Selected folder only; exclusions apply."]) }
            else if watchedOnly {
                let paths = prefs.locations.filter { $0.value.watched && !prefs.excluded($0.key) }.map(\.key).sorted()
                found = Discovery(profiles: paths.map { Classifier.profile(path: $0, home: home, preferences: prefs) }, notes: ["Watchlist only; no broad discovery. Missing watched paths are recorded as missing."])
            } else if priorityOnly && !ScanPlanner.discoveryDue(prefs, now: now) {
                found = Discovery(profiles: known, notes: ["Priority pass over saved locations. Discovery is due every seven days while periodic checks are enabled."])
            } else { found = Inventory.discover(home: home, preferences: prefs, cancellation: token) { path in
                DispatchQueue.main.async { if !token.stopped { self.progress = "Discovering: " + path + " · macOS may request access" } }
            } }
            let profiles = priorityOnly ? ScanPlanner.priority(found.profiles, preferences: prefs, records: history, now: now) : found.profiles
            let rediscovered = !selectedOnly && !watchedOnly && (!priorityOnly || ScanPlanner.discoveryDue(prefs, now: now))
            DispatchQueue.main.async {
                if !selectedOnly && !watchedOnly { self.acceptDiscovery(found) }
                if rediscovered { self.recordDiscovery() }
                self.targetCount = profiles.count; self.progress = "Checking process handles…"
            }
            guard !profiles.isEmpty else {
                DispatchQueue.main.async { self.error = "No included locations match this scan. Add a location or change your filters."; self.running = false }
                return
            }
            let record = ScanEngine.scan(profiles: profiles, preferences: prefs, scope: scope, notes: found.notes, cancellation: token, limits: priorityOnly ? .priority : .manual, totalSeconds: priorityOnly ? 90 : 900) { item, index, total in
                DispatchQueue.main.async { self.partial.append(item); self.completed = index; self.progress = item.profile.name }
            }
            DispatchQueue.main.async {
                self.records.append(record); self.refreshVolume()
                do { try self.store?.append(record) }
                catch { self.error = "Scan is available in memory but could not be saved: \(error.localizedDescription)" }
                self.running = false; self.progress = record.complete ? "Scan complete" : "Scan preserved; open Needs Attention for incomplete locations"
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
    func exportReport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Context-Cleaner-\(Int(Date().timeIntervalSince1970)).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = "# Context Cleaner\n\nRead-only report. No files are deleted by this app. Allocated sizes are estimates, not guaranteed reclaimable space.\n\n"
        for row in rows.sorted(by: { $0.bytes > $1.bytes }) {
            let p = row.measurement.profile
            text += "## \(p.name)\n\nPath: `\(p.path)`\n\nSize: \(row.bytes >= 0 ? byteLabel(row.bytes) : "Not measured") · \(row.category) · \(row.status)\n\nAssociation: \(p.associatedApp)\n\n\(p.explanation)\n\nConsequences: \(p.consequence)\n\n"
            if let change = row.change.delta { text += "Measured change: \(change >= 0 ? "+" : "−")\(byteLabel(abs(change)))\n\n" }
            for e in p.evidence { text += "- \(e.level.rawValue): \(e.label) — \(e.value). Source: \(e.source)\n" }
            text += "\n"
        }
        do { try writeNew(Data(text.utf8), to: url) } catch { self.error = "Export preserved the existing destination and did not replace it. Choose a new filename. \(error.localizedDescription)" }
    }
}
