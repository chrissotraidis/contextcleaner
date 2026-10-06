import Foundation

/// Allocated size of the Trash, or nil when macOS won't let it be read. Reads metadata only.
func trashSize(_ url: URL) -> Int64? {
    guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return nil }
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
    guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return nil }
    var total: Int64 = 0
    for case let item as URL in items {
        if let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true { total += Int64(values.totalFileAllocatedSize ?? 0) }
    }
    return total
}
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
            // Folders only: a file such as Xcode's device_set.plist is not a location to measure.
            return listing.names.filter { !$0.hasPrefix(".") }.map { parent + "/" + $0 }.filter { path in
                var child = stat()
                return lstat(path, &child) != 0 || (child.st_mode & S_IFMT) == S_IFDIR
            }
        }
        /// The repositories in a project folder: the folder itself, or, for a folder that wraps them
        /// (Codex's nested worktrees: name/repo/.git), each child that holds a .git entry.
        func repositories(_ folder: String) -> [String] {
            var st = stat()
            if lstat(folder + "/.git", &st) == 0 { return [folder] }
            let inner = children(folder).filter { lstat($0 + "/.git", &st) == 0 }
            return inner.isEmpty ? [folder] : inner
        }
        for entry in Coverage.entries {
            let root = entry.path(home: home)
            switch entry.kind {
            case .folder: add(root)
            case .children: for p in children(root) { add(p) }
            case .projects, .workspaces:
                for project in children(root) {
                    var st = stat(); guard lstat(project, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
                    if entry.kind == .workspaces { add(project) }
                    for repository in repositories(project) {
                        for suffix in Coverage.projectSuffixes { add(repository + "/" + suffix) }
                    }
                }
            }
        }
        for p in preferences.customRoots where !preferences.excluded(p) { paths.insert(normalized(p)) }
        for (p, policy) in preferences.locations where policy.isWatched && !preferences.excluded(p) { paths.insert(normalized(p)) }
        let profiles = paths.map { path in
            if !cancellation.stopped { progress(path) }
            return Classifier.profile(path: path, home: home, readMetadata: !cancellation.stopped, preferences: preferences)
        }.sorted { a,b in
            let aw = preferences.policy(a.path).isWatched, bw = preferences.policy(b.path).isWatched
            if aw != bw { return aw }
            if a.category.reproducible != b.category.reproducible { return a.category.reproducible }
            return a.path < b.path
        }
        notes.append("Coverage: recognized development/cache locations plus selected roots. Not an entire-disk scan. Symbolic links are not followed; other filesystem volumes are not traversed from a parent scan.")
        if cancellation.stopped { complete = false; notes.append("Discovery cancelled. Previously known locations are retained.") }
        return Discovery(profiles: profiles, notes: notes, complete: complete)
    }
}

/// Reading sizes must never download anything. With iCloud's Desktop & Documents or another cloud folder, files and
/// folders can be "dataless": opening one asks the cloud for it, which takes disk space and can stall a scan for minutes.
/// This turns that off for the whole app: such items are skipped and take no space on this Mac anyway.
/// It also stops reads from mounting network folders (autofs).
func keepReadsLocal() {
    _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    _ = setiopolicy_np(IOPOL_TYPE_VFS_TRIGGER_RESOLVE, IOPOL_SCOPE_PROCESS, IOPOL_VFS_TRIGGER_RESOLVE_OFF)
}
/// Whether macOS gave Context Cleaner Full Disk Access. The TCC database can only be opened with it. Opens nothing else.
func hasFullDiskAccess(home: String = NSHomeDirectory()) -> Bool {
    let fd = open(home + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { return false }
    close(fd)
    return true
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
/// Repeats a system call interrupted by a signal (EINTR). Interrupted calls are routine and must not be read as "no access".
@inline(__always) func retryingInterrupted(_ call: () -> Int32) -> Int32 {
    var result: Int32
    repeat { result = call() } while result == -1 && errno == EINTR
    return result
}
final class DirectoryCursor {
    let path: String
    /// The folder's top-level child this directory sits under, so each entry is credited without re-reading its path.
    var top: String?
    private var pointer: UnsafeMutablePointer<DIR>?
    init(_ path: String) throws {
        self.path = path
        let fd = retryingInterrupted { Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
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
                if errno == EINTR { continue }
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
/// Reads a directory's entries in batches with getattrlistbulk: name, type, device, change date, file ID,
/// link count and sizes arrive together, so no per-entry lstat is needed. Metadata only; no file is opened.
/// A top-level child's totals while a folder is walked; turned into a ChildSummary at the end.
final class ChildBox {
    let name: String, directory: Bool, identity: String
    var bytes: Int64 = 0, files = 0, latest = Int.min
    init(name: String, directory: Bool, identity: String) { self.name = name; self.directory = directory; self.identity = identity }
    var summary: ChildSummary {
        ChildSummary(name: name, directory: directory, identity: identity, bytes: bytes, files: files, modifiedAt: latest == Int.min ? nil : Date(timeIntervalSince1970: Double(latest)))
    }
}
final class BulkCursor {
    struct Entry {
        let name: String
        let isDirectory: Bool, isRegular: Bool, isLink: Bool, isMountPoint: Bool
        let device: Int32
        let modifiedSeconds: Int
        let fileID: UInt64
        let linkCount: UInt32
        let allocated: Int64
        let logical: Int64
    }
    let path: String
    var top: String?
    /// Running totals for the top-level child this directory sits under, when that child is kept in the summary.
    var box: ChildBox?
    private let fd: Int32
    private let buffer: UnsafeMutableRawPointer
    private let capacity = 64 * 1024
    private var cursor: UnsafeMutableRawPointer
    private var remaining = 0
    private var finished = false
    private static let request: attrlist = {
        var a = attrlist()
        a.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        a.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
        a.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS) | attrgroup_t(ATTR_DIR_ALLOCSIZE) | attrgroup_t(ATTR_DIR_DATALENGTH)
        a.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE) | attrgroup_t(ATTR_FILE_DATALENGTH)
        return a
    }()
    init(_ path: String, top: String?, box: ChildBox? = nil) throws {
        self.path = path; self.top = top; self.box = box
        let fd = retryingInterrupted { Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        self.fd = fd
        buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        cursor = buffer
    }
    deinit { Darwin.close(fd); buffer.deallocate() }
    func next() throws -> Entry? {
        if remaining == 0 {
            guard !finished else { return nil }
            var request = Self.request
            let count = retryingInterrupted { getattrlistbulk(fd, &request, buffer, capacity, 0) }
            if count < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if count == 0 { finished = true; return nil }
            remaining = Int(count); cursor = buffer
        }
        remaining -= 1
        let start = cursor
        cursor += Int(start.loadUnaligned(as: UInt32.self))
        var p = start + 4
        let returned = p.loadUnaligned(as: attribute_set_t.self); p += MemoryLayout<attribute_set_t>.size
        let nameOffset = Int(p.loadUnaligned(as: Int32.self)), nameLength = Int(p.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        let nameBytes = UnsafeRawBufferPointer(start: p + nameOffset, count: max(0, nameLength - 1))
        let name = String(decoding: nameBytes, as: UTF8.self); p += 8
        let device = p.loadUnaligned(as: Int32.self); p += 4
        let type = p.loadUnaligned(as: UInt32.self); p += 4
        let modified = p.loadUnaligned(as: timespec.self); p += MemoryLayout<timespec>.size
        let fileID = p.loadUnaligned(as: UInt64.self); p += 8
        var linkCount: UInt32 = 1, allocated: Int64 = 0, logical: Int64 = 0, mountPoint = false
        let isDirectory = type == UInt32(VDIR.rawValue), isRegular = type == UInt32(VREG.rawValue)
        if isDirectory {
            if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 { mountPoint = p.loadUnaligned(as: UInt32.self) & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0; p += 4 }
            if returned.dirattr & attrgroup_t(ATTR_DIR_ALLOCSIZE) != 0 { allocated = p.loadUnaligned(as: Int64.self); p += 8 }
            if returned.dirattr & attrgroup_t(ATTR_DIR_DATALENGTH) != 0 { logical = p.loadUnaligned(as: Int64.self); p += 8 }
        } else {
            if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 { linkCount = p.loadUnaligned(as: UInt32.self); p += 4 }
            if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 { allocated = p.loadUnaligned(as: Int64.self); p += 8 }
            if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 { logical = p.loadUnaligned(as: Int64.self); p += 8 }
        }
        return Entry(name: name, isDirectory: isDirectory, isRegular: isRegular, isLink: type == UInt32(VLNK.rawValue), isMountPoint: mountPoint,
                     device: device, modifiedSeconds: Int(modified.tv_sec), fileID: fileID, linkCount: linkCount, allocated: allocated, logical: logical)
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
/// The open files inside a folder, one per app and top-level item: enough to say which app has it open, and which items
/// inside are held. Thousands of files a simulator holds open become a few lines, and every scan saved stays small.
func compactActivity(_ activity: [ProcessEvidence], under folder: String, limit: Int = 1000) -> [ProcessEvidence] {
    let root = normalized(folder)
    var seen: Set<ProcessEvidence> = [], out: [ProcessEvidence] = []
    for item in activity where containsPath(root, item.path) {
        var top = root
        if item.path.count > root.count + 1 {
            let rest = item.path.dropFirst(root == "/" ? 1 : root.count + 1)
            top = (root == "/" ? "" : root) + "/" + (rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "")
        }
        let compact = ProcessEvidence(pid: item.pid, command: item.command, access: item.access, path: top)
        if seen.insert(compact).inserted { out.append(compact); if out.count >= limit { break } }
    }
    return out
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
                fileCount: files, latestModifiedAt: latest, processes: compactActivity(activity, under: profile.path),
                activityCheckAvailable: activityAvailable, diagnostic: diagnostic, elapsedSeconds: ProcessInfo.processInfo.systemUptime - started)
            measurement.scopeID = "metadata-v1:" + preferences.locations.filter { $0.value.excluded && containsPath(profile.path, $0.key) }.map { normalized($0.key) }.sorted().joined(separator: "|")
            measurement.contents = state == .measured ? contents : nil
            return measurement
        }
        if preferences.excluded(profile.path) { return result(.excluded, diagnostic: "Excluded by your preference.") }
        if cancellation.stopped { return result(.cancelled, diagnostic: "Cancelled before reading this location.") }
        var rootStat = stat()
        guard retryingInterrupted({ lstat(profile.path, &rootStat) }) == 0 else { return result(errno == ENOENT ? .missing : .inaccessible, diagnostic: String(cString: strerror(errno))) }
        guard MetadataReader.hasNoSymlinkComponents(profile.path) else { return result(.excluded, diagnostic: "Symbolic links, including parent path components, are not traversed.") }
        // The folder itself counts like any entry; everything inside is read in batches.
        var bytes: Int64 = Int64(rootStat.st_blocks) * 512, logical: Int64 = Int64(rootStat.st_size), files = 0, entries = 1
        var latestSeconds: Int = rootStat.st_mtimespec.tv_sec
        // Turned-off folders inside this one, prepared once. Child paths are built from directory names,
        // so a plain prefix test matches containsPath without normalizing every entry.
        let root = normalized(profile.path)
        let excludedInside = preferences.locations.filter { $0.value.excluded }.map { normalized($0.key) }.filter { containsPath(root, $0) }
        let excludedPrefixes = excludedInside.map { $0 == "/" ? "/" : $0 + "/" }
        func isExcluded(_ path: String) -> Bool {
            guard !excludedInside.isEmpty else { return false }
            for (index, excluded) in excludedInside.enumerated() where path == excluded || path.hasPrefix(excludedPrefixes[index]) { return true }
            return false
        }
        var childMap: [String: ChildBox] = [:], typeMap: [String: FileTypeSummary] = [:]
        var listedChildren = 0
        /// Keeps the biggest top-level items. Folders are read one at a time, so every item but the one being read is
        /// complete when the list is trimmed; a folder with hundreds of thousands of items never holds them all.
        func trimChildren(keeping current: String) {
            let keep = Set(childMap.values.sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }.prefix(512).map(\.name))
            childMap = childMap.filter { keep.contains($0.key) || $0.key == current }
        }
        struct FileIdentity: Hashable { let device: Int32; let inode: UInt64 }
        var seen: Set<FileIdentity> = [], failures: [String] = [], omitted = 0
        func incomplete(_ reason: String) -> FolderMeasurement {
            result(.limited, diagnostic: "\(reason) after \(entries.formatted()) entries. Partial sizes are withheld. Measure a smaller child folder or run a manual scan with its larger allowance.")
        }
        // In your temporary folder, macOS keeps a few system services' items private; they aren't yours to remove.
        let skipsPrivate = profile.category == .temporary
        // One open directory per level of depth, so a folder with millions of names never builds a huge list.
        var stack: [BulkCursor] = []
        if (rootStat.st_mode & S_IFMT) == S_IFDIR {
            do { stack.append(try BulkCursor(profile.path, top: nil)) }
            catch { failures.append(profile.path + ": " + error.localizedDescription) }
        } else { files = 1 }
        while let cursor = stack.last {
            if cancellation.stopped { return result(.cancelled, diagnostic: "Cancelled; no partial total presented as complete.") }
            if ProcessInfo.processInfo.systemUptime - started >= limits.seconds { return incomplete("Time allowance reached") }
            let entry: BulkCursor.Entry
            do {
                guard let next = try cursor.next() else { stack.removeLast(); continue }
                entry = next
            } catch { if failures.count < 3 { failures.append(cursor.path + ": " + error.localizedDescription) }; stack.removeLast(); continue }
            let name = entry.name
            let atRoot = cursor.top == nil
            // Full paths are only needed to open a folder or to test exclusions.
            let child = entry.isDirectory || !excludedInside.isEmpty ? (cursor.path == "/" ? "/" + name : cursor.path + "/" + name) : ""
            if !excludedInside.isEmpty && isExcluded(child) { omitted += 1; entries += 1; if entries >= limits.entries { return incomplete("Entry allowance reached") }; continue }
            if atRoot {
                listedChildren += 1
                if childMap.count >= 4096 { trimChildren(keeping: name) }
            }
            if entries >= limits.entries { return incomplete("Entry allowance reached") }
            entries += 1
            if entry.isLink || entry.isMountPoint || entry.device != rootStat.st_dev { omitted += 1; continue }
            if entry.isRegular && entry.linkCount > 1 {
                if !seen.insert(FileIdentity(device: entry.device, inode: entry.fileID)).inserted { continue }
            }
            let top = cursor.top ?? name
            var box = cursor.box
            if atRoot {
                box = childMap[name] ?? ChildBox(name: name, directory: entry.isDirectory, identity: "\(entry.device):\(entry.fileID)")
                childMap[name] = box
            }
            if let box {
                box.bytes += entry.allocated
                if !entry.isDirectory { box.files += 1 }
                if entry.modifiedSeconds > box.latest { box.latest = entry.modifiedSeconds }
            }
            if !entry.isDirectory {
                let dot = name.lastIndex(of: ".")
                let ext = dot.map { name[name.index(after: $0)...] } ?? ""
                var type = ext.isEmpty || dot == name.startIndex ? "No extension" : "." + (ext.utf8.contains { $0 >= 65 && $0 <= 90 } ? String(ext.prefix(32)).lowercased() : String(ext.prefix(32)))
                if typeMap[type] == nil && typeMap.count >= 63 { type = "Other extensions" }
                var summary = typeMap[type] ?? FileTypeSummary(kind: type)
                summary.files += 1; summary.bytes += entry.allocated; typeMap[type] = summary
            }
            bytes += entry.allocated; logical += entry.logical
            if entry.modifiedSeconds > latestSeconds { latestSeconds = entry.modifiedSeconds }
            if entry.isDirectory {
                if stack.count >= limits.depth { return incomplete("Directory depth allowance reached") }
                do { stack.append(try BulkCursor(child, top: top, box: box)) }
                catch let error as POSIXError where error.code == .EDEADLK { omitted += 1 }
                catch let error as POSIXError where skipsPrivate && (error.code == .EPERM || error.code == .EACCES) { omitted += 1 }
                catch { if failures.count < 3 { failures.append(child + ": " + error.localizedDescription) } }
            } else { files += 1 }
            if entries % 4000 == 0 { Thread.sleep(forTimeInterval: 0.002) }
        }
        if !failures.isEmpty { return result(.inaccessible, diagnostic: "Incomplete measurement; partial sizes withheld. " + failures.joined(separator: "\n")) }
        contents = FolderContents(children: Array(childMap.values.map(\.summary).sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }.prefix(512)), fileTypes: typeMap.values.sorted { $0.bytes > $1.bytes }, listedChildren: listedChildren, retainedLimit: 512, omittedEntries: omitted)
        let latest = latestSeconds == Int.min ? nil : Date(timeIntervalSince1970: Double(latestSeconds))
        return result(.measured, bytes, logical, files, latest, diagnostic: omitted > 0 ? "\(omitted) excluded paths, symbolic links or other-volume entries were skipped. Size describes only included contents." : nil)
    }
}
