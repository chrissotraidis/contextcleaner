import Foundation
import Darwin

struct Discovery: Codable {
    var profiles: [FolderProfile]
    var notes: [String]
    var complete: Bool? = nil
}
struct Inventory {
    static func discover(home: String, preferences: Preferences, cancellation: Cancellation = Cancellation(), progress: (String) -> Void = { _ in }) -> Discovery {
        var paths: Set<String> = [], notes: [String] = []
        var complete = true
        func add(_ p: String) {
            let p = normalized(p)
            guard !preferences.excluded(p) else { return }
            guard !cancellation.stopped else { return }
            progress(p)
            var st = stat()
            let code = lstat(p, &st)
            if code == 0, (st.st_mode & S_IFMT) != S_IFLNK { paths.insert(p) }
            else if code != 0 && (errno == EACCES || errno == EPERM) { paths.insert(p) }
        }
        func children(_ parent: String) -> [String] {
            guard !preferences.excluded(parent), !cancellation.stopped else { return [] }
            progress(parent)
            var st = stat()
            guard lstat(parent, &st) == 0 else {
                if errno != ENOENT { complete = false; notes.append("Could not inspect " + parent + ": " + String(cString: strerror(errno))) }
                return []
            }
            let listing = DirectoryListing.read(parent, preferences: preferences, cancellation: cancellation)
            if !listing.complete { complete = false }
            if let note = listing.note { notes.append(parent + ": " + note) }
            return listing.names.filter { !$0.hasPrefix(".") }.map { parent + "/" + $0 }
        }
        for entry in Coverage.entries {
            let root = entry.path(home: home)
            switch entry.kind {
            case .folder: add(root)
            case .children: for p in children(root) { add(p) }
            case .projects:
                for project in children(root) {
                    var st = stat(); guard lstat(project, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
                    for suffix in Coverage.projectSuffixes { add(project + "/" + suffix) }
                }
            }
        }
        for p in preferences.customRoots where !preferences.excluded(p) { paths.insert(normalized(p)) }
        for (p, policy) in preferences.locations where policy.watched && !preferences.excluded(p) { paths.insert(normalized(p)) }
        let profiles = paths.map { path in
            if !cancellation.stopped { progress(path) }
            return Classifier.profile(path: path, home: home, readMetadata: !cancellation.stopped, preferences: preferences)
        }.sorted { a,b in
            let aw = preferences.policy(a.path).watched, bw = preferences.policy(b.path).watched
            if aw != bw { return aw }
            if a.category.reproducible != b.category.reproducible { return a.category.reproducible }
            return a.path < b.path
        }
        notes.append("Coverage: recognized development/cache locations plus selected roots. Not an entire-disk scan. Symbolic links are not followed; other filesystem volumes are not traversed from a parent scan.")
        if cancellation.stopped { complete = false; notes.append("Discovery cancelled. Previously known locations are retained.") }
        return Discovery(profiles: profiles, notes: notes, complete: complete)
    }
}

struct Cancellation: @unchecked Sendable {
    private final class State: @unchecked Sendable { let lock = NSLock(); var stopped = false }
    private let state = State()
    var stopped: Bool { state.lock.lock(); defer { state.lock.unlock() }; return state.stopped }
    func cancel() { state.lock.lock(); state.stopped = true; state.lock.unlock() }
}

struct ScanLimits {
    var seconds: TimeInterval
    var entries: Int
    var depth: Int = 128
    static let manual = ScanLimits(seconds: 120, entries: 1_000_000)
    static let priority = ScanLimits(seconds: 10, entries: 100_000)
}
// Directory handles are bounded by traversal depth and closed on every return path.
// Only directory metadata is read; no file payload is opened.
final class DirectoryCursor {
    let path: String
    private var pointer: UnsafeMutablePointer<DIR>?
    init(_ path: String) throws {
        self.path = path
        let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard let pointer = fdopendir(fd) else { let code = errno; Darwin.close(fd); throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        self.pointer = pointer
    }
    deinit { if let pointer { closedir(pointer) } }
    func next() throws -> String? {
        guard let pointer else { return nil }
        while true {
            errno = 0
            guard let entry = readdir(pointer) else {
                if errno != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                return nil
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { raw in
                raw.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { return name }
        }
    }
}
struct DirectoryListing {
    var names: [String]
    var complete: Bool
    var note: String?
    static func read(_ path: String, preferences: Preferences, cancellation: Cancellation = Cancellation(), limit: Int = 4096) -> DirectoryListing {
        guard !preferences.excluded(path) else { return DirectoryListing(names: [], complete: false, note: "Excluded by you.") }
        guard MetadataReader.hasNoSymlinkComponents(path) else { return DirectoryListing(names: [], complete: false, note: "Unavailable path or symbolic-link ancestor.") }
        do {
            let cursor = try DirectoryCursor(path)
            var names: [String] = [], seen = 0
            let started = ProcessInfo.processInfo.systemUptime
            while let name = try cursor.next() {
                if cancellation.stopped { return DirectoryListing(names: names.sorted(), complete: false, note: "Listing cancelled.") }
                if seen >= limit || ProcessInfo.processInfo.systemUptime - started >= 5 {
                    return DirectoryListing(names: names.sorted(), complete: false, note: "Listing limit reached; showing an incomplete set of entries. Add a narrower location to investigate.")
                }
                seen += 1
                if !preferences.excluded(path + "/" + name) { names.append(name) }
            }
            return DirectoryListing(names: names.sorted(), complete: true, note: nil)
        } catch { return DirectoryListing(names: [], complete: false, note: error.localizedDescription) }
    }
}
struct TreeMeasure {
    // Cooperative time/entry/depth limits: a slow filesystem call can outlast the deadline.
    // Streaming traversal bounds pending work by depth, rather than directory width.
    static func measure(_ profile: FolderProfile, preferences: Preferences, cancellation: Cancellation,
                        activity: [ProcessEvidence], activityAvailable: Bool, limits: ScanLimits = .manual) -> FolderMeasurement {
        let started = ProcessInfo.processInfo.systemUptime
        var contents: FolderContents?
        func result(_ state: MeasurementState, _ bytes: Int64? = nil, _ logical: Int64? = nil, _ files: Int = 0,
                    _ latest: Date? = nil, diagnostic: String? = nil) -> FolderMeasurement {
            var measurement = FolderMeasurement(profile: profile, observedAt: Date(), state: state, allocatedBytes: bytes, logicalBytes: logical,
                fileCount: files, latestModifiedAt: latest, processes: activity.filter { containsPath(profile.path, $0.path) },
                activityCheckAvailable: activityAvailable, diagnostic: diagnostic, elapsedSeconds: ProcessInfo.processInfo.systemUptime - started)
            measurement.scopeID = "metadata-v1:" + preferences.locations.filter { $0.value.excluded && containsPath(profile.path, $0.key) }.map { normalized($0.key) }.sorted().joined(separator: "|")
            measurement.contents = state == .measured ? contents : nil
            return measurement
        }
        if preferences.excluded(profile.path) { return result(.excluded, diagnostic: "Excluded by your preference.") }
        if cancellation.stopped { return result(.cancelled, diagnostic: "Cancelled before reading this location.") }
        var rootStat = stat()
        guard lstat(profile.path, &rootStat) == 0 else { return result(errno == ENOENT ? .missing : .inaccessible, diagnostic: String(cString: strerror(errno))) }
        guard MetadataReader.hasNoSymlinkComponents(profile.path) else { return result(.excluded, diagnostic: "Symbolic links, including parent path components, are not traversed.") }
        var stack: [DirectoryCursor] = [], nextPath: String? = profile.path
        var bytes: Int64 = 0, logical: Int64 = 0, files = 0, entries = 0, latest: Date?
        var childMap: [String: ChildSummary] = [:], typeMap: [String: FileTypeSummary] = [:]
        var retainedNames: Set<String> = [], listedChildren = 0
        var seen: Set<String> = [], failures: [String] = [], omitted = 0
        func incomplete(_ reason: String) -> FolderMeasurement {
            result(.limited, diagnostic: "\(reason) after \(entries.formatted()) entries. Partial sizes are withheld. Measure a smaller child folder or run a manual scan with its larger allowance.")
        }
        while nextPath != nil || !stack.isEmpty {
            if cancellation.stopped { return result(.cancelled, diagnostic: "Cancelled; no partial total presented as complete.") }
            if ProcessInfo.processInfo.systemUptime - started >= limits.seconds { return incomplete("Time allowance reached") }
            // Read the next entry only when needed; a directory with millions of names
            // never creates a million-element URL stack.
            if nextPath == nil, let cursor = stack.last {
                do {
                    if let name = try cursor.next() {
                        let child = cursor.path == "/" ? "/" + name : cursor.path + "/" + name
                        if preferences.excluded(child) { omitted += 1; entries += 1; if entries >= limits.entries { return incomplete("Entry allowance reached") }; continue }
                        if cursor.path == profile.path {
                            listedChildren += 1
                            if retainedNames.count < 512 { retainedNames.insert(name) }
                            else if let largest = retainedNames.max(), name < largest {
                                retainedNames.remove(largest); childMap.removeValue(forKey: largest); retainedNames.insert(name)
                            }
                        }
                        nextPath = child
                    } else { stack.removeLast(); continue }
                } catch { if failures.count < 3 { failures.append(cursor.path + ": " + error.localizedDescription) }; stack.removeLast(); continue }
            }
            guard let path = nextPath else { continue }; nextPath = nil
            if entries >= limits.entries { return incomplete("Entry allowance reached") }
            entries += 1
            if preferences.excluded(path) { omitted += 1; continue }
            var st = stat()
            guard lstat(path, &st) == 0 else { if failures.count < 3 { failures.append(path + ": " + String(cString: strerror(errno))) }; continue }
            if (st.st_mode & S_IFMT) == S_IFLNK || st.st_dev != rootStat.st_dev { omitted += 1; continue }
            if st.st_nlink > 1 && (st.st_mode & S_IFMT) == S_IFREG {
                let key = "\(st.st_dev):\(st.st_ino)"
                if !seen.insert(key).inserted { continue }
            }
            let allocated = Int64(st.st_blocks) * 512, isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
            let relative = path == profile.path ? "" : String(path.dropFirst(profile.path == "/" ? 1 : profile.path.count + 1))
            let firstComponent = String(relative.split(separator: "/").first ?? "")
            if retainedNames.contains(firstComponent) {
                if childMap[firstComponent] == nil { childMap[firstComponent] = ChildSummary(name: firstComponent, directory: isDirectory, identity: "\(st.st_dev):\(st.st_ino)") }
                childMap[firstComponent]!.bytes += allocated
                if !isDirectory { childMap[firstComponent]!.files += 1 }
                let modification = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
                if childMap[firstComponent]!.modifiedAt == nil || modification > childMap[firstComponent]!.modifiedAt! { childMap[firstComponent]!.modifiedAt = modification }
            }
            if !isDirectory {
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                var type = ext.isEmpty ? "No extension" : "." + String(ext.prefix(32))
                if typeMap[type] == nil && typeMap.count >= 63 { type = "Other extensions" }
                var summary = typeMap[type] ?? FileTypeSummary(kind: type)
                summary.files += 1; summary.bytes += allocated; typeMap[type] = summary
            }
            bytes += allocated; logical += Int64(st.st_size)
            let modified = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))
            if latest == nil || modified > latest! { latest = modified }
            if isDirectory {
                if stack.count >= limits.depth { return incomplete("Directory depth allowance reached") }
                do { stack.append(try DirectoryCursor(path)) }
                catch { if failures.count < 3 { failures.append(path + ": " + error.localizedDescription) } }
            } else { files += 1 }
            if entries % 4000 == 0 { Thread.sleep(forTimeInterval: 0.002) }
        }
        if !failures.isEmpty { return result(.inaccessible, diagnostic: "Incomplete measurement; partial sizes withheld. " + failures.joined(separator: "\n")) }
        contents = FolderContents(children: childMap.values.sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }, fileTypes: typeMap.values.sorted { $0.bytes > $1.bytes }, listedChildren: listedChildren, retainedLimit: 512, omittedEntries: omitted)
        return result(.measured, bytes, logical, files, latest, diagnostic: omitted > 0 ? "\(omitted) excluded paths, symbolic links or other-volume entries were skipped. Size describes only included contents." : nil)
    }
}
