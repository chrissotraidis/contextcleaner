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
    func idleScore(now: Date) -> Double {
        guard bytes > 0 else { return 0 }
        let idle = advice.lastUsed.map { min(max(0, now.timeIntervalSince($0) / 86400), 90) / 90 } ?? 0.35
        return Double(bytes) * idle * (advice.verdict == .keep ? 0.25 : 1)
    }
    /// Default order: big folders you haven't used in a while come first. Size is weighted by idle time
    /// (full weight after 90 days); recently used folders sink, unknown use counts a third, and folders
    /// an app manages (Keep) count a quarter.
    var idleScore: Double { idleScore(now: Date()) }
    var growing: Bool { (change.delta ?? 0) > 0 && (change.delta ?? 0) >= (policy.growthThresholdBytes ?? 0) && !policy.expected }
    /// One plain word, shown only when it tells you something. Empty for an ordinary scanned folder.
    var status: String {
        if policy.excluded { return "Scanning off" }
        if policy.isKept { return "Ignored" }
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
        if !measurement.processes.isEmpty { return "Open at last scan" }
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
    @Published var selected: String? { willSet { placeWillChange() } didSet { if let s = selected { if selection != [s] { selection = [s] } } else if !selection.isEmpty { selection = [] } } }
    /// Table selection. One item drives the inspector; several show a summed summary.
    @Published var selection: Set<String> = [] { didSet { if selection.count == 1, selected != selection.first { selected = selection.first } else if selection.isEmpty, selected != nil { selected = nil } } }
    /// A changed view or filter must never leave actions targeting hidden rows.
    func retainVisibleSelection() {
        let visible = Set(rows.map(\.id))
        // A folder opened from inside a listed folder ("What's inside", Up, Back) stays selected.
        if selection.count == 1, let only = selection.first, visible.contains(where: { containsPath($0, only) }) { return }
        let retained = selection.intersection(visible)
        if retained != selection { selection = retained }
    }
    /// Free Up Space first: it's what the app is for.
    @Published var section: AppSection = .overview { willSet { placeWillChange() } }
    @Published var locationFilter: LocationFilter = .all { willSet { placeWillChange() } }
    @Published var editing: String?
    @Published var search = ""
    @Published var categoryFilter: FolderCategory? { willSet { placeWillChange() } }
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
    /// measurement, its settings and discovery facts, so it survives scan progress and is kept per folder.
    private struct AdviceEntry { let observedAt: Date; let bytes: Int64?; let state: MeasurementState; let advice: Advice }
    private var adviceCache: (preferences: Int, discovery: Int, value: [String: AdviceEntry]) = (-1, -1, [:])
    func adviceFor(_ m: FolderMeasurement) -> Advice {
        if adviceCache.preferences != preferencesVersion || adviceCache.discovery != discoveryVersion { adviceCache = (preferencesVersion, discoveryVersion, [:]) }
        if let cached = adviceCache.value[m.profile.path], cached.observedAt == m.observedAt, cached.bytes == m.allocatedBytes, cached.state == m.state { return cached.advice }
        let path = m.profile.path
        let worktree: WorktreeGit? = isWorktreeFolder(path) ? (worktrees[path].map { .read($0) } ?? (projectsRead ? .noRepository : .unread)) : nil
        var value = advice(for: m, policy: preferences.policy(path), devices: simDevices, project: project(for: path), worktree: worktree)
        // Until git activity has been read, a project folder can't be called safe: it may be work in progress.
        if !projectsRead, value.verdict == .safe, [.workspace, .buildOutput].contains(m.profile.category), !m.profile.path.contains("/DerivedData") {
            var held = Advice(verdict: .check, reason: "Checking its project's git activity before answering. " + value.reason, howTo: value.howTo, command: value.command, lastUsed: value.lastUsed)
            held.evidence = value.evidence
            held.short = "Checking git…"
            value = held
        }
        adviceCache.value[m.profile.path] = AdviceEntry(observedAt: m.observedAt, bytes: m.allocatedBytes, state: m.state, advice: value)
        return value
    }
    /// Git activity for the projects that scanned folders belong to, keyed by project root. Read-only.
    @Published var projects: [String: ProjectActivity] = [:] { didSet { discoveryVersion += 1 } }
    /// What git has of each whole Codex worktree folder, keyed by the folder. Read-only.
    @Published var worktrees: [String: RepoBackup] = [:] { didSet { discoveryVersion += 1 } }
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
            // Whole worktree folders: is everything in them kept by git? A few at a time; git status reads every file.
            let folders = paths.filter(isWorktreeFolder)
            var backups = [RepoBackup?](repeating: nil, count: folders.count)
            backups.withUnsafeMutableBufferPointer { slots in
                let base = slots.baseAddress!
                DispatchQueue.concurrentPerform(iterations: folders.count) { index in
                    if let repository = worktreeRepository(folders[index]) { base[index] = readRepoBackup(repository) }
                }
            }
            var states: [String: RepoBackup] = [:]
            for (index, folder) in folders.enumerated() { if let backup = backups[index] { states[folder] = backup } }
            DispatchQueue.main.async { self.projectRoots = roots; self.projectsRead = true; self.worktrees = states; self.projects = activity }
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
        guard !readingTrash else { return }
        readingTrash = true
        let url = URL(fileURLWithPath: home + "/.Trash")
        DispatchQueue.global(qos: .utility).async {
            let bytes = trashSize(url)
            DispatchQueue.main.async { self.readingTrash = false; if bytes != self.trashBytes { self.trashBytes = bytes } }
        }
    }
    private var readingTrash = false
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
        return folderGrowth(history: derived.history, profile: { self.isExcluded($0) ? nil : profiles[$0] }, from: from, to: to, limit: limit)
    }
    func sparkline(_ path: String) -> [Double] { sparklineValues(history(path)) }
    /// A friendly name for any known folder, falling back to its last path component.
    func displayName(_ path: String) -> String {
        latest.first { $0.profile.path == path }?.profile.displayName
            ?? discovery.profiles.first { $0.path == path }?.displayName
            ?? URL(fileURLWithPath: path).lastPathComponent
    }
    /// Turned-off folders, normalized once per settings change.
    private var excludedRoots: (version: Int, roots: [String]) = (-1, [])
    /// Whether a folder is turned off, or inside one that is. Same answer as Preferences.excluded, without
    /// normalizing every saved setting on every call.
    func isExcluded(_ path: String) -> Bool {
        if excludedRoots.version != preferencesVersion {
            excludedRoots = (preferencesVersion, preferences.locations.filter { $0.value.excluded }.map { normalized($0.key) })
        }
        guard !excludedRoots.roots.isEmpty else { return false }
        let target = normalized(path), bytes = target.utf8
        for root in excludedRoots.roots {
            if root == target || root == "/" { return true }
            let prefix = root.utf8
            if bytes.count > prefix.count, bytes.starts(with: prefix), bytes[bytes.index(bytes.startIndex, offsetBy: prefix.count)] == 0x2F { return true }
        }
        return false
    }
    // MARK: Everything else

    /// Used space that isn't in any scanned folder or any folder you ignored: the disk map's "Everything else".
    var everythingElseBytes: Int64 {
        guard let used = volume?.used else { return 0 }
        let r = reclaim, kept = keptSummary
        return max(0, used - (r.safe.bytes + r.inside.bytes + r.rebuild.bytes + r.check.bytes + r.keep.bytes + kept.keptBytes + kept.offBytes))
    }

    @Published var showingElsewhere = false
    @Published private(set) var elsewhere: [ElsewhereItem] = []
    @Published private(set) var elsewhereDate: Date?
    @Published private(set) var lookingElsewhere = false
    /// What's inside each row you opened, and the rows still being sized.
    @Published private(set) var elsewhereChildren: [String: [ElsewhereItem]] = [:]
    @Published private(set) var elsewhereOpening: Set<String> = []
    private var elsewhereCancellation = Cancellation()
    /// Sizes the top level of your home folder, your Library and Applications, leaving out every folder
    /// Context Cleaner already scans or you turned off, so nothing is counted twice. Reads metadata only.
    func lookElsewhere() {
        guard !lookingElsewhere else { return }
        lookingElsewhere = true; elsewhere = []; elsewhereChildren = [:]; elsewhereOpening = []
        elsewhereCancellation = Cancellation()
        let home = home, job = elsewhereJob()
        DispatchQueue.global(qos: .userInitiated).async {
            var targets = ["/Applications"]
            for path in folderEntries(home) where path != home + "/Library" { targets.append(path) }
            targets += folderEntries(home + "/Library")
            let found = job(targets, true)
            DispatchQueue.main.async { self.elsewhere = found; self.elsewhereDate = Date(); self.lookingElsewhere = false }
        }
    }
    /// Sizes what's inside one row, the same way. Kept until Look Again.
    func openElsewhere(_ path: String) {
        guard elsewhereChildren[path] == nil, !elsewhereOpening.contains(path) else { return }
        elsewhereOpening.insert(path)
        let job = elsewhereJob()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = job(folderEntries(path), false)
            DispatchQueue.main.async { self.elsewhereChildren[path] = found; self.elsewhereOpening.remove(path) }
        }
    }
    /// Measures places outside the scanned folders: size, newest change, what it is, and for git checkouts
    /// whether they're backed up. Scanned folders inside are left out of the size and noted apart.
    private func elsewhereJob() -> ([String], Bool) -> [ElsewhereItem] {
        let home = home, token = elsewhereCancellation
        var prefs = preferences
        // Folders you've since removed would otherwise still count as "scanned separately".
        let gone = gone
        let measured = latest.filter { $0.state == .measured && !gone.contains($0.profile.path) }
        let known = measured.map(\.profile.path) + preferences.locations.filter { $0.value.excluded }.map(\.key)
        for path in known { var policy = prefs.policy(path); policy.excluded = true; prefs.locations[normalized(path)] = policy }
        // Outermost scanned folders only, so nested ones count once.
        var outer: [FolderMeasurement] = []
        for item in measured.sorted(by: { $0.profile.path.count < $1.profile.path.count })
        where !outer.contains(where: { containsPath($0.profile.path, item.profile.path) }) { outer.append(item) }
        let skipped: [String: String] = [home + "/Library/CloudStorage": "Cloud storage isn't read, so nothing is downloaded.", home + "/Library/Mobile Documents": "iCloud Drive isn't read, so nothing is downloaded."]
        return { targets, topLevel in
            var results = [ElsewhereItem?](repeating: nil, count: targets.count)
            results.withUnsafeMutableBufferPointer { slots in
                let base = slots.baseAddress!
                DispatchQueue.concurrentPerform(iterations: targets.count) { index in
                    let path = targets[index]
                    let name = topLevel ? abbreviatedPath(path) : URL(fileURLWithPath: path).lastPathComponent
                    if let note = skipped[path] { base[index] = ElsewhereItem(path: path, name: name, bytes: nil, note: note); return }
                    guard !prefs.excluded(path), !token.stopped else { return }
                    var st = stat()
                    guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return }
                    let inside = outer.filter { $0.profile.path.hasPrefix(path + "/") }
                    let profile = FolderProfile(path: path, name: name, category: .unknown, project: nil, associatedApp: "", explanation: "", consequence: "", evidence: [])
                    let m = TreeMeasure.measure(profile, preferences: prefs, cancellation: token, activity: [], activityAvailable: false, limits: ScanLimits(seconds: 180, entries: 5_000_000))
                    var item: ElsewhereItem
                    switch m.state {
                    case .measured:
                        guard (m.allocatedBytes ?? 0) > 0 else { return }
                        item = ElsewhereItem(path: path, name: topLevel && !inside.isEmpty ? name + " (the rest of it)" : name, bytes: m.allocatedBytes, note: nil)
                    case .inaccessible: item = ElsewhereItem(path: path, name: name, bytes: nil, note: "macOS didn't allow reading it. Full Disk Access lets Context Cleaner size it.")
                    case .limited: item = ElsewhereItem(path: path, name: name, bytes: nil, note: "Too big to size in the time allowed.")
                    default: return
                    }
                    item.isFolder = (st.st_mode & S_IFMT) == S_IFDIR
                    item.about = elsewhereAbout(path, home: home)
                    item.scannedInside = inside.reduce(0) { $0 + ($1.allocatedBytes ?? 0) }
                    item.modified = ([m.latestModifiedAt] + inside.map(\.latestModifiedAt)).compactMap { $0 }.max()
                    item.scannedModified = inside.compactMap(\.latestModifiedAt).max()
                    var git = stat()
                    if item.isFolder, !topLevel, lstat(path + "/.git", &git) == 0 { item.backup = readRepoBackup(path) }
                    base[index] = item
                }
            }
            return results.compactMap { $0 }.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }
        }
    }
    func stopLookingElsewhere() { elsewhereCancellation.cancel() }

    // MARK: Back and Forward

    /// Where you are: the view, its filter and the folder shown. Search is typing, so it isn't a place.
    struct Place: Equatable {
        var section: AppSection, filter: LocationFilter, category: FolderCategory?, selected: String?
    }
    var place: Place { Place(section: section, filter: locationFilter, category: categoryFilter, selected: selected) }
    @Published private(set) var backStack: [Place] = []
    @Published private(set) var forwardStack: [Place] = []
    private var placeOrigin: Place?
    private var restoringPlace = false
    /// Several properties change together when you open something; they're merged into one step.
    private func placeWillChange() {
        guard !restoringPlace, placeOrigin == nil else { return }
        placeOrigin = place
        DispatchQueue.main.async { [weak self] in self?.commitPlace() }
    }
    private func commitPlace() {
        guard let origin = placeOrigin else { return }
        placeOrigin = nil
        let now = place
        guard now != origin else { return }
        // Clicking from one listed row to another isn't a new place.
        if origin.section == now.section && origin.filter == now.filter && origin.category == now.category {
            let visible = Set(rows.map(\.id))
            if (now.selected.map(visible.contains) ?? true) && (origin.selected.map(visible.contains) ?? true) { return }
        }
        backStack.append(origin)
        if backStack.count > 60 { backStack.removeFirst() }
        forwardStack = []
    }
    func goBack() { guard let target = backStack.popLast() else { return }; forwardStack.append(place); apply(target) }
    func goForward() { guard let target = forwardStack.popLast() else { return }; backStack.append(place); apply(target) }
    private func apply(_ target: Place) {
        restoringPlace = true
        categoryFilter = target.category; search = ""; section = target.section; locationFilter = target.filter; selected = target.selected
        restoringPlace = false
    }
    /// What Back would return to, for its tooltip.
    var backTitle: String? { backStack.last.map(placeTitle) }
    var forwardTitle: String? { forwardStack.last.map(placeTitle) }
    private func placeTitle(_ p: Place) -> String {
        if let path = p.selected { return displayName(path) }
        if p.section == .locations { return p.category?.displayName ?? (p.filter == .all ? "Folders" : p.filter.rawValue) }
        return p.section.rawValue
    }
    /// The nearest folder above this one that Context Cleaner knows, for "Up to…".
    func knownParent(of path: String) -> String? {
        var current = (path as NSString).deletingLastPathComponent
        let known = Set(latest.map(\.profile.path) + discovery.profiles.map(\.path))
        while current.count > home.count {
            if known.contains(current) { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
    /// Shows the Folders list, optionally narrowed to one type or answer.
    func showFolders(_ category: FolderCategory? = nil, filter: LocationFilter = .all) {
        categoryFilter = category; search = ""; section = .locations
        locationFilter = filter; selected = nil; inspector = "Overview"
    }
    /// Free Up Space, set to list what's sat untouched for at least this long.
    func showFreeUp(quietHours hours: Int? = nil) {
        if let hours { quietHours = hours }
        search = ""; categoryFilter = nil; section = .freeUp
    }
    /// The Overview chart's range and selected span, shared with "Where the space went".
    @Published var chartRange: UsageRange = .week { didSet { chartSpan = nil } }
    @Published var chartSpan: ClosedRange<Date>?
    var chartWindow: ClosedRange<Date> { chartRange.window(endingAt: usage.last?.date ?? Date()) }
    var chartActiveWindow: ClosedRange<Date> { chartSpan ?? chartWindow }
    var chartWindowPhrase: String {
        guard let span = chartSpan else { return "last " + chartRange.rawValue }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour()
        return span.lowerBound.formatted(style) + " – " + span.upperBound.formatted(style)
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
    init(home: String = homeDirectory, dataRoot: URL? = demoDataRoot) {
        self.home = home
        do {
            let root = dataRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Context Cleaner")
            let storage = try AppendStore(root: root)
            let legacy = URL(fileURLWithPath: home + "/Library/Application Support/SpaceCheck/history.json")
            if FileManager.default.fileExists(atPath: legacy.path) { _ = try storage.importLegacy(legacy, home: home) }
            records = droppingOldContents(storage.records()); preferences = storage.preferences()
            capacity = storage.capacityReadings()
            cleanups = storage.cleanups()
            discovery = storage.learnedDiscovery() ?? Discovery(profiles: [], notes: [])
            store = storage
            error = storage.warnings.isEmpty ? nil : storage.warnings.joined(separator: "\n")
        } catch { store = nil; self.error = "Storage unavailable; scanning is disabled to avoid losing history. \(error.localizedDescription)" }
        var saved = Dictionary(uniqueKeysWithValues: discovery.profiles.map { ($0.path, $0) })
        for path in preferences.customRoots where saved[path] == nil { saved[path] = Classifier.profile(path: path, home: home, readMetadata: false) }
        for record in records { for item in record.measurements { saved[item.profile.path] = item.profile } }
        discovery = Discovery(profiles: saved.values.sorted { $0.path < $1.path }, notes: ["Showing saved locations. Discovery runs only when requested. Coverage is recognized development/cache locations and your selected roots, not the whole disk."])
        recordCapacityIfDue()
        NotificationCenter.default.addObserver(forName: .copyTrash, object: nil, queue: .main) { [weak self] note in
            guard let paths = note.userInfo?["paths"] as? [String] else { return }
            let bytes = note.userInfo?["bytes"] as? Int64
            let sizes = note.userInfo?["sizes"] as? [String: Int64] ?? [:]
            MainActor.assumeIsolated { self?.copyTrash(paths, bytes: bytes, sizes: sizes) }
        }
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
            // A place now measured folder by folder (~/Documents/Codex) may have an old whole size; it would hide the folders inside.
            let home = self.home
            let containers = Set(Coverage.entries.filter { $0.kind != .folder }.map { $0.path(home: home) })
            for record in records.sorted(by: { $0.finishedAt < $1.finishedAt }) {
                // A quick scheduled check has short limits; a big folder it couldn't finish keeps the size a full scan found.
                let quick = record.scope.hasPrefix("Priority")
                for item in record.measurements where item.state != .cancelled && !containers.contains(item.profile.path) {
                    if quick && item.state != .measured && saved[item.profile.path]?.state == .measured { continue }
                    saved[item.profile.path] = item
                }
            }
            // Older scans saved names from earlier naming rules. Show today's names: subfolders named for
            // themselves, projects named for their own folder. Saved files are never changed.
            for (path, item) in saved where ![.simulator].contains(item.profile.category) && SimulatorLocations.containerRoot(path) == nil {
                let fresh = Classifier.profile(path: path, home: home, readMetadata: false)
                guard fresh.category == item.profile.category else { continue }
                var m = item; m.profile.name = fresh.name; m.profile.project = fresh.project
                saved[path] = m
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
        func excluded(_ path: String) -> Bool { isExcluded(path) }
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
    /// The table's rows in the chosen order, sorted once per change of rows or order rather than on every redraw.
    private var sortedCache: (key: String, order: [KeyPathComparator<FolderRow>], rows: [FolderRow]) = ("", [], [])
    func sortedRows(_ order: [KeyPathComparator<FolderRow>]) -> [FolderRow] {
        let current = rows
        let key = rowsCache.key + "|\(rowsCache.validUntil.timeIntervalSinceReferenceDate)"
        if sortedCache.key == key && sortedCache.order == order { return sortedCache.rows }
        let value: [FolderRow]
        if order.count == 1, let first = order.first, first.keyPath == \FolderRow.idleScore {
            // The default order: score each row once instead of on every comparison.
            let now = Date()
            let scored = current.map { ($0, $0.idleScore(now: now)) }
            value = scored.sorted { first.order == .reverse ? $0.1 > $1.1 : $0.1 < $1.1 }.map(\.0)
        } else { value = current.sorted(using: order) }
        sortedCache = (key, order, value)
        return value
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
        for item in baseMeasures() where item.state == .measured && !isExcluded(item.profile.path) && !preferences.policy(item.profile.path).isKept && !gone.contains(item.profile.path) {
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
        // Each byte counts once, for the innermost folder: a worktree's rebuildable build folder isn't also Review first.
        let own = exclusiveBytes(Verdict.allCases.flatMap { verdictGroups[$0] ?? [] })
        let items = verdictGroups[verdict] ?? []
        let value = (items.count, items.reduce(Int64(0)) { $0 + (own[normalized($1.profile.path)] ?? 0) })
        totalsCache.value[verdict] = value
        return value
    }
    private func include(_ row: FolderRow, _ p: FolderProfile) -> Bool {
        // Folders that are gone leave every list. Kept and turned-off folders live in their own view.
        if row.gone { return false }
        let off = isExcluded(p.path), kept = row.policy.isKept
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
    /// Refreshes when a scan is saved or settings change; scan progress doesn't move it.
    var reclaim: Reclaim {
        let key = "\(recordsVersion)|\(preferencesVersion)|\(discoveryVersion)"
        if reclaimCache.key == key { return reclaimCache.value }
        var value = Reclaim()
        // Count each byte once, with the answer of the innermost scanned folder that holds it:
        // a worktree that holds uncommitted work doesn't hide its rebuildable build folder.
        let all = Verdict.allCases.flatMap { v in (verdictGroups[v] ?? []).map { ($0, v) } }
        let own = exclusiveBytes(all.map(\.0))
        for (m, verdict) in all {
            let bytes = own[normalized(m.profile.path)] ?? 0, inside = min(adviceFor(m).staleBytes, bytes)
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
    // MARK: Free up space

    /// How long a folder must sit untouched before it's suggested. Saved between launches.
    /// Ticks survive a change of time: anything still listed stays ticked, anything no longer listed doesn't count.
    @Published var quietHours: Int = UserDefaults.standard.object(forKey: "quietHours") as? Int ?? 24 {
        didSet { UserDefaults.standard.set(quietHours, forKey: "quietHours") }
    }
    /// Smallest item Free up space lists.
    static var suggestionMinimum: Int64 = 100 * 1_048_576
    /// Suggestions you ticked, by path.
    @Published var selectedSuggestions: Set<String> = []
    private var suggestionCache: (key: String, value: [Suggestion]) = ("", [])
    /// What to move to the Trash now, biggest first. Rebuilt when scans, settings or the quiet time change,
    /// and at least every ten minutes as folders age.
    var suggestionList: [Suggestion] {
        let bucket = Int(Date().timeIntervalSince1970 / 600)
        let key = "\(recordsVersion)|\(preferencesVersion)|\(discoveryVersion)|\(quietHours)|\(bucket)|\(trashedSinceScan.count)|\(vanished.count)"
        if suggestionCache.key == key { return suggestionCache.value }
        let items = baseMeasures().filter { !isExcluded($0.profile.path) }
        // Items you moved to the Trash leave the list at once, including old items inside folders, which no scan has seen go yet.
        // Whole folders follow the same rule as every Trash command; old items inside a folder are judged by the folder's rules.
        let byPath = Dictionary(items.map { ($0.profile.path, $0) }, uniquingKeysWith: { a, _ in a })
        let value = suggestions(items, advice: { self.adviceFor($0) }, gone: gone, quiet: TimeInterval(quietHours) * 3600, minimum: Self.suggestionMinimum)
            .filter { !trashedSinceScan.contains($0.path) && !vanished.contains($0.path) && ($0.owner != nil || byPath[$0.path].map(mayTrashWhole) ?? false) }
        suggestionCache = (key, value)
        return value
    }
    /// Paths a Trash command moved since the last scan. Cleared when a scan is saved.
    @Published private(set) var trashedSinceScan: Set<String> = []
    /// Suggestions that are no longer on disk, however they went: a Trash command, Finder, or a tool cleaning up.
    /// They leave the list at once, so a copy never offers what's already gone.
    @Published private(set) var vanished: Set<String> = []
    private var checkingVanished = false
    func checkVanished() {
        guard !checkingVanished else { return }
        let paths = Array(Set(suggestionList.map(\.path)).union(selectedSuggestions))
        guard !paths.isEmpty else { return }
        checkingVanished = true
        DispatchQueue.global(qos: .utility).async {
            let missing = missingPaths(paths)
            DispatchQueue.main.async {
                self.checkingVanished = false
                guard !missing.isEmpty else { return }
                if !missing.isSubset(of: self.vanished) { self.vanished.formUnion(missing) }
                if !self.selectedSuggestions.isDisjoint(with: missing) { self.selectedSuggestions.subtract(missing) }
            }
        }
    }
    /// Whether a whole folder may go in a Trash command. Never: virtual machines, simulators, chat history, app libraries
    /// and model libraries (remove those in their own apps), ignored, turned-off or Not for the Trash folders, and the places
    /// Context Cleaner looks in, such as Downloads, ~/GitHub or Codex scratch, unless that place is itself a cache.
    func mayTrashWhole(_ m: FolderMeasurement) -> Bool {
        let path = m.profile.path, category = m.profile.category
        let cache: Set<FolderCategory> = [.packageCache, .installCache, .buildOutput, .debugSymbols]
        // An Android emulator is a folder plus an .ini file, and the command moves both; other virtual machines are removed in their apps.
        let emulator = category == .virtualMachine && path.hasSuffix(".avd")
        guard emulator || ![.virtualMachine, .simulator, .history, .appData, .model].contains(category), !path.hasSuffix("/CoreSimulator/Devices"),
              !isExcluded(path), !preferences.policy(path).isKept, !gone.contains(path) else { return false }
        if Coverage.entries.contains(where: { $0.path(home: home) == path }) && !cache.contains(category) { return false }
        return adviceFor(m).verdict != .keep
    }
    /// The folders from a Folders selection a single Trash command may move, each once (a folder inside another goes with it).
    /// Only Safe and Rebuildable folders: nothing is lost. Review first folders are copied one at a time from their card,
    /// or ticked in Free up space once they've sat untouched.
    func trashable(_ paths: [String], includeReview: Bool = false) -> (paths: [String], skipped: Int) {
        let known = Dictionary(baseMeasures().map { ($0.profile.path, $0) }, uniquingKeysWith: { a, _ in a })
        let allowed: Set<Verdict> = includeReview ? [.safe, .rebuild, .check] : [.safe, .rebuild]
        var ready: [String] = []
        for path in paths.sorted(by: { $0.count < $1.count }) {
            guard let m = known[path], m.state == .measured, !trashedSinceScan.contains(path), mayTrashWhole(m),
                  allowed.contains(adviceFor(m).verdict) else { continue }
            if hasAncestor(in: Set(ready), path) { continue }
            ready.append(path)
        }
        return (ready, paths.count - ready.count)
    }

    // MARK: Trash commands you copied

    /// A Trash command you copied: the folders in it, watched until they leave their place, and any left out. Metadata only.
    struct TrashWatch: Equatable {
        var id = UUID().uuidString
        var paths: [String]
        var bytes: Int64
        var leftOut: [String: LeftOut] = [:]
        var moved: Set<String> = []
        var started = Date()
        var movedBytes: Int64 = 0
        var done: Bool { !paths.isEmpty && moved.count == paths.count }
        var expired: Bool { Date().timeIntervalSince(started) > 1800 }
    }
    @Published private(set) var trashWatch: TrashWatch?
    /// Every Trash command you copied, newest first, with what became of each item.
    @Published private(set) var cleanups: [Cleanup] = []
    private var trashTimer: Timer?
    private var trashSizes: [String: Int64] = [:]
    /// The newest change a scan saw in a folder, or in an item inside a scanned folder.
    func seenDate(_ path: String) -> Date? {
        if let m = latest.first(where: { $0.profile.path == path }) { return m.latestModifiedAt }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path, name = URL(fileURLWithPath: path).lastPathComponent
        return latest.first(where: { $0.profile.path == parent })?.contents?.children.first(where: { $0.name == name })?.modifiedAt
    }
    /// A folder's size from the last scan, or an item's size inside a scanned folder.
    func knownBytes(_ path: String) -> Int64 {
        if let m = latest.first(where: { $0.profile.path == path }) { return m.allocatedBytes ?? 0 }
        if let s = suggestionList.first(where: { $0.path == path }) { return s.bytes }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path, name = URL(fileURLWithPath: path).lastPathComponent
        return latest.first(where: { $0.profile.path == parent })?.contents?.children.first(where: { $0.name == name })?.bytes ?? 0
    }
    /// Rechecks the folders, then copies one Move-to-Trash command for those that pass, and watches them so you can see it worked.
    /// A folder is left out if it's gone, open in an app, or changed since the scan. Context Cleaner never runs the command.
    func copyTrash(_ paths: [String], bytes: Int64? = nil, sizes known: [String: Int64] = [:]) {
        let state = TrashCopyState.shared
        guard !paths.isEmpty, !state.checking else { return }
        var sizes: [String: Int64] = [:]
        for path in paths { sizes[path] = known[path] ?? knownBytes(path) }
        if paths.count == 1, let bytes, sizes[paths[0]] == 0 { sizes[paths[0]] = bytes }
        let items = paths.map { (path: $0, seen: seenDate($0)) }
        // Worktrees offered because git had everything in them get the same git check again, in full.
        let cleanTrees = paths.filter { isWorktreeFolder($0) && worktrees[$0]?.keepsEverything == true }
        state.start(paths)
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = ActivitySnapshot.capture()
            var result = recheck(items, open: snapshot.available ? snapshot.observations : nil)
            // A clean worktree goes only if git still has everything: a new uncommitted change or a new file git
            // doesn't keep, anywhere inside, leaves it out.
            let trees = cleanTrees.filter { result.ready.contains($0) }
            var fresh = [RepoBackup?](repeating: nil, count: trees.count)
            fresh.withUnsafeMutableBufferPointer { slots in
                let base = slots.baseAddress!
                DispatchQueue.concurrentPerform(iterations: trees.count) { index in
                    base[index] = worktreeRepository(trees[index]).map(readRepoBackup)
                }
            }
            for (index, path) in trees.enumerated() where fresh[index]?.keepsEverything != true {
                result.ready.removeAll { $0 == path }; result.leftOut[path] = .changed
            }
            DispatchQueue.main.async {
                // What git just said replaces what it said at the scan, so the row's answer is current too.
                if !trees.isEmpty {
                    var states = self.worktrees
                    for (index, path) in trees.enumerated() { states[path] = fresh[index] }
                    self.worktrees = states
                }
                self.finishCopy(paths, result, sizes: sizes)
            }
        }
    }
    private func finishCopy(_ paths: [String], _ result: (ready: [String], leftOut: [String: LeftOut]), sizes: [String: Int64]) {
        let id = UUID().uuidString
        if !result.ready.isEmpty {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(trashCommandText(trashTargets(result.ready), id: id), forType: .string)
        }
        TrashCopyState.shared.finish(paths, copied: result.ready.count, leftOut: result.leftOut.count)
        trashSizes = sizes
        trashWatch = TrashWatch(id: id, paths: result.ready, bytes: result.ready.reduce(0) { $0 + (sizes[$1] ?? 0) }, leftOut: result.leftOut)
        // Items left out stay ticked, so you can see which they were and the Copy button keeps saying what it copied.
        let gone = result.leftOut.filter { $0.value == .gone }.map(\.key)
        selectedSuggestions.subtract(gone)
        vanished.formUnion(gone)
        if result.leftOut.values.contains(.gone) { refreshGone() }
        saveCleanup()
        trashTimer?.invalidate()
        guard !result.ready.isEmpty else { return }
        trashTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkTrashWatch() } }
    }
    /// The command to copy: every path written out when it's short, or read from a saved list when it's long.
    func trashCommandText(_ targets: [String], id: String) -> String {
        let prune = Array(Set(targets.compactMap { isWorktreeFolder($0) ? worktrees[$0]?.mainRepository : nil })).sorted()
        let inline = trashCommand(targets, prune: prune)
        guard inline.utf8.count > trashInlineLimit, let store, let list = try? store.saveTrashList(id, targets) else { return inline }
        return trashCommand(targets, list: list, prune: prune)
    }
    private func checkTrashWatch() {
        guard let watch = trashWatch else { trashTimer?.invalidate(); return }
        // Stop watching after half an hour; whatever is still in place is recorded as not moved.
        if watch.expired { trashTimer?.invalidate(); saveCleanup(); return }
        let pending = watch.paths.filter { !watch.moved.contains($0) }
        DispatchQueue.global(qos: .utility).async {
            let gone = missingPaths(pending)
            DispatchQueue.main.async {
                guard !gone.isEmpty, var current = self.trashWatch, current.id == watch.id else { return }
                current.moved.formUnion(gone)
                self.trashedSinceScan.formUnion(gone)
                current.movedBytes = current.moved.reduce(0) { $0 + (self.trashSizes[$1] ?? 0) }
                self.trashWatch = current
                self.selectedSuggestions.subtract(gone)
                self.refreshGone(); self.refreshTrash()
                if current.done { self.trashTimer?.invalidate() }
                self.saveCleanup()
            }
        }
    }
    /// Saves the current Trash command's state as a new file, and shows it in History.
    private func saveCleanup() {
        guard let watch = trashWatch else { return }
        var items = watch.paths.map { path in
            Cleanup.Item(path: path, bytes: trashSizes[path] ?? 0, status: watch.moved.contains(path) ? .moved : watch.expired ? .notMoved : .waiting)
        }
        items += watch.leftOut.sorted { $0.key < $1.key }.map { Cleanup.Item(path: $0.key, bytes: trashSizes[$0.key] ?? 0, status: .leftOut, note: $0.value.rawValue) }
        let cleanup = Cleanup(id: watch.id, copiedAt: watch.started, updatedAt: Date(), items: items)
        cleanups.removeAll { $0.id == cleanup.id }; cleanups.insert(cleanup, at: 0)
        do { try store?.append(cleanup) } catch { self.error = "The cleanup couldn't be saved to History: \(error.localizedDescription)" }
    }

    /// Folders holding old items, biggest amount first.
    private var insideListCache: (key: String, value: [FolderMeasurement]) = ("", [])
    var insideFolders: [FolderMeasurement] {
        let key = "\(recordsVersion)|\(preferencesVersion)|\(discoveryVersion)"
        if insideListCache.key == key { return insideListCache.value }
        let value = ((verdictGroups[.rebuild] ?? []) + (verdictGroups[.check] ?? [])).map { ($0, adviceFor($0).staleBytes) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        insideListCache = (key, value)
        return value
    }
    /// Where used space went since from, by place; plus the disk's own change over the same span.
    struct SpaceWent {
        var from: Date; var to: Date; var diskChange: Int64?; var places: [SpaceChange]
        var explained: Int64 { places.reduce(0) { $0 + $1.bytes } }
        /// Days the span covers, at least an hour's worth, for rates.
        var days: Double { max(to.timeIntervalSince(from), 3600) / 86400 }
    }
    private var wentCache: (key: String, value: SpaceWent?) = ("", nil)
    func spaceWent(from start: Date, to end: Date) -> SpaceWent? {
        let key = "\(recordsVersion)|\(discoveryVersion)|\(preferencesVersion)|\(usage.count)|\(usage.last?.used ?? 0)|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))"
        if wentCache.key == key { return wentCache.value }
        refreshDerived()
        let readings = usage
        guard let first = readings.first(where: { $0.date >= start && $0.date <= end }), let last = readings.last(where: { $0.date <= end && $0.date >= start }), first.date < last.date else { wentCache = (key, nil); return nil }
        // Folders removed since their last scan count as freed in their own place, when the range reaches the present.
        let reachesNow = last.date >= (readings.last?.date ?? last.date)
        let current = derived.saved.values.filter { !isExcluded($0.profile.path) && (reachesNow || !gone.contains($0.profile.path)) }
        let places = spaceChanges(history: derived.history, latest: Array(current), created: created, from: first.date, to: last.date, removed: reachesNow ? gone : [], home: home)
        let value = SpaceWent(from: first.date, to: last.date, diskChange: last.used - first.used, places: places)
        wentCache = (key, value)
        return value
    }
    func groupSize(_ group: CoverageGroup) -> Int64 {
        Coverage.entries.filter { $0.group == group && !isExcluded($0.path(home: home)) }.reduce(0) { $0 + (coverageSizes[$1.id] ?? 0) }
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
            if isExcluded(item.profile.path) { summary.off.append(item) }
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
        guard !running, !inspecting, !discovering, ScanPlanner.dailyDue(preferences, now: now) else { return }
        runScheduledCheck(now: now)
    }
    /// The scheduled check, now: watched and growing folders first, then those checked longest ago.
    func runScheduledCheck(now: Date = Date()) {
        guard let store, !running, !inspecting, !discovering else { return }
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
                self.records = droppingOldContents(self.records + [record]); self.trashedSinceScan = []; self.vanished = []; self.refreshVolume(); self.refreshGone(); self.loadSimDevices(); self.refreshProjects()
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
                    self.records = droppingOldContents(self.records + [record]); self.refreshVolume()
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
        // What Free Up Space lists now: the quickest win, first.
        let quick = suggestionList
        text += "## Free up space now · \(byteLabel(quick.reduce(Int64(0)) { $0 + $1.bytes })) in \(quick.count) \(quick.count == 1 ? "item" : "items") untouched for \(quietHours >= 24 ? "\(quietHours / 24) \(quietHours == 24 ? "day" : "days")" : "\(quietHours) hours") or longer\n\n"
        for s in quick.prefix(60) { text += "- [ ] **\(s.name.replacingOccurrences(of: "*", with: ""))** · \(byteLabel(s.bytes)) · \(s.cost.title) · \(s.why)\n  `\(s.path)`\n" }
        if quick.count > 60 { text += "- and \(quick.count - 60) more in the app\n" }
        let easy = quick.filter { [.safe, .rebuild].contains($0.cost) }.map(\.path)
        let command = trashCommand(easy)
        if !easy.isEmpty && command.utf8.count <= trashInlineLimit { text += "\nOne command for the \(easy.count) Safe to remove and Rebuildable items above:\n\n```\n\(command)\n```\n" }
        text += "\n"
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
        text += "\n## 4. Review first · \(byteLabel(uniqueAllocatedTotal(check))) in \(check.count) \(check.count == 1 ? "folder" : "folders")\n\nMay hold the only copy of something. Look at each first. Biggest first.\n\n"
        for m in check.prefix(40) {
            let a = adviceFor(m)
            text += "- " + line(m, a) + "\n  \(a.reason)\n" + a.evidence.map { "  \($0)\n" }.joined() + "  `\(m.profile.path)`\n"
        }
        if check.count > 40 { text += "- and \(check.count - 40) more in the app\n" }
        let kept = keptSummary
        text += "\n## 5. Not for the Trash, or ignored by you · \(byteLabel(uniqueAllocatedTotal(keep) + kept.keptBytes))\n\nApp libraries and chat history (manage these inside their own apps), and folders you chose to ignore.\n\n"
        for m in (keep + kept.kept).filter({ ($0.allocatedBytes ?? 0) >= 1_048_576 }) { text += "- **\(m.profile.displayName)** · \(m.allocatedBytes.map(byteLabel) ?? "size unknown")\n" }
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

/// Every entry in a folder, sorted. Metadata only.
func folderEntries(_ folder: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted().map { folder + "/" + $0 }
}
