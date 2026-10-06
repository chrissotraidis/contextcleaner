import Foundation
import CryptoKit
import Darwin

enum StoreError: Error, LocalizedError {
    case exists(String), io(String), invalid(String)
    var errorDescription: String? {
        switch self { case .exists(let p): return "Preserved existing file; refused to overwrite: \(p)"
        case .io(let p): return "Could not append a new file: \(p)"
        case .invalid(let p): return "Could not read stored record: \(p)" }
    }
}
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
// Sole data-writing primitive. New files only. Never replace, truncate, rename, trash or unlink.
func writeNew(_ data: Data, to url: URL) throws {
    let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { if errno == EEXIST { throw StoreError.exists(url.path) }; throw StoreError.io(url.path) }
    defer { Darwin.close(fd) }
    try data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        var offset = 0
        while offset < data.count {
            let n = Darwin.write(fd, base.advanced(by: offset), data.count - offset)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw StoreError.io(url.path) }; offset += n
        }
    }
    guard fsync(fd) == 0 else { throw StoreError.io(url.path) }
}
struct DiscoveryEvent: Codable { var date: Date; var id: String; var value: Discovery }
struct PreferencesEvent: Codable { var date: Date; var id: String; var value: Preferences }
struct MigrationReceipt: Codable { var digest: String; var importedAt: Date; var snapshotCount: Int }
/// One Trash command you copied, and what became of each item in it. Saved as a new file each time it changes.
struct Cleanup: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case waiting, moved, notMoved, leftOut }
    struct Item: Codable, Equatable { var path: String; var bytes: Int64; var status: Status; var note: String? = nil }
    var id: String
    var copiedAt: Date
    var updatedAt: Date
    var items: [Item]
    func bytes(_ status: Status) -> Int64 { items.filter { $0.status == status }.reduce(0) { $0 + $1.bytes } }
    func count(_ status: Status) -> Int { items.filter { $0.status == status }.count }
}
final class AppendStore {
    let root: URL
    let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
    private(set) var warnings: [String] = []
    init(root: URL) throws {
        self.root = root
        for folder in ["scans", "preferences", "imports", "discoveries", "capacity", "cleanups", "trash-lists"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }
    /// Decodes every file in parallel, one decoder per file. Unreadable files are reported and left untouched.
    private func decodeAll<T: Decodable>(_ directory: String, as type: T.Type, label: String, transform: @escaping (T) -> T = { $0 }) -> [T] {
        let urls = files(directory)
        var results = [T?](repeating: nil, count: urls.count)
        results.withUnsafeMutableBufferPointer { slots in
            let base = slots.baseAddress!
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                base[index] = (try? JSONDecoder().decode(T.self, from: Data(contentsOf: urls[index]))).map(transform)
            }
        }
        for (index, value) in results.enumerated() where value == nil { warnings.append("Unreadable \(label) preserved: \(urls[index].lastPathComponent)") }
        return results.compactMap { $0 }
    }
    private func files(_ directory: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
    }
    func records() -> [ScanRecord] {
        // Scans saved before 0.21.2 kept every open file. In memory, one line per app and item inside is all the answers use;
        // the files themselves are never rewritten.
        decodeAll("scans", as: ScanRecord.self, label: "scan", transform: { record in
            var record = record
            for m in record.measurements.indices where record.measurements[m].processes.count > 50 {
                record.measurements[m].processes = compactActivity(record.measurements[m].processes, under: record.measurements[m].profile.path)
            }
            return record
        }).sorted { $0.finishedAt < $1.finishedAt }
    }
    func append(_ record: ScanRecord) throws {
        guard record.id.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil else { throw StoreError.invalid("record ID") }
        try writeNew(encoder.encode(record), to: root.appendingPathComponent("scans/\(record.id).json"))
    }
    func saveDiscovery(_ discovery: Discovery) throws {
        let event = DiscoveryEvent(date: Date(), id: UUID().uuidString, value: discovery)
        try writeNew(encoder.encode(event), to: root.appendingPathComponent("discoveries/\(event.id).json"))
    }
    func learnedDiscovery() -> Discovery? {
        let events = decodeAll("discoveries", as: DiscoveryEvent.self, label: "discovery").sorted { $0.date < $1.date }
        guard let last = events.last else { return nil }
        var profiles: [String: FolderProfile] = [:]
        for event in events { for profile in event.value.profiles { profiles[profile.path] = profile } }
        return Discovery(profiles: profiles.values.sorted { $0.path < $1.path }, notes: last.value.notes)
    }
    func preferences() -> Preferences {
        decodeAll("preferences", as: PreferencesEvent.self, label: "preference event").max { a,b in a.date == b.date ? a.id < b.id : a.date < b.date }?.value ?? Preferences()
    }
    func save(_ preferences: Preferences) throws {
        let event = PreferencesEvent(date: Date(), id: UUID().uuidString, value: preferences)
        try writeNew(encoder.encode(event), to: root.appendingPathComponent("preferences/\(event.id).json"))
    }
    /// Appends a new file per reading. Earlier readings are never rewritten or removed.
    func appendCapacity(_ reading: CapacityReading) throws {
        let stamp = Int64(reading.date.timeIntervalSince1970 * 1000)
        try writeNew(encoder.encode(reading), to: root.appendingPathComponent("capacity/\(stamp)-\(UUID().uuidString).json"))
    }
    func capacityReadings() -> [CapacityReading] {
        decodeAll("capacity", as: CapacityReading.self, label: "capacity reading").sorted { $0.date < $1.date }
    }
    /// Appends the latest state of a cleanup. Earlier states stay on disk; the newest per cleanup wins when read.
    func append(_ cleanup: Cleanup) throws {
        let stamp = Int64(cleanup.updatedAt.timeIntervalSince1970 * 1000)
        try writeNew(encoder.encode(cleanup), to: root.appendingPathComponent("cleanups/\(cleanup.id)-\(stamp)-\(UUID().uuidString).json"))
    }
    func cleanups() -> [Cleanup] {
        let all = decodeAll("cleanups", as: Cleanup.self, label: "cleanup")
        return Dictionary(grouping: all, by: \.id).values.compactMap { $0.max { $0.updatedAt < $1.updatedAt } }.sorted { $0.copiedAt > $1.copiedAt }
    }
    /// Saves the paths of a long Trash command as a new file, for the command to read. Returns its path.
    func saveTrashList(_ id: String, _ paths: [String]) throws -> String {
        guard id.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil else { throw StoreError.invalid("list ID") }
        let url = root.appendingPathComponent("trash-lists/\(id).txt")
        try writeNew(trashListData(paths), to: url)
        return url.path
    }
    func importLegacy(_ source: URL, home: String) throws -> Int {
        let data = try Data(contentsOf: source), sourceDigest = digest(data)
        let receiptURL = root.appendingPathComponent("imports/receipt-\(sourceDigest).json")
        if FileManager.default.fileExists(atPath: receiptURL.path) { return 0 }
        let snapshots = try JSONDecoder().decode([LegacySnapshot].self, from: data)
        let rawURL = root.appendingPathComponent("imports/original-\(sourceDigest).json")
        if !FileManager.default.fileExists(atPath: rawURL.path) { try writeNew(data, to: rawURL) }
        let existing = Set(records().map(\.id))
        var count = 0
        for snapshot in snapshots {
            let id = "legacy-" + digest(try encoder.encode(snapshot))
            guard !existing.contains(id) else { continue }
            let measured = snapshot.items.map { item in
                FolderMeasurement(profile: Classifier.profile(path: item.path, home: home, readMetadata: false), observedAt: snapshot.date,
                    state: item.error == nil ? .measured : .failed, allocatedBytes: item.error == nil ? item.bytes : nil,
                    logicalBytes: nil, fileCount: 0, latestModifiedAt: nil, processes: [], activityCheckAvailable: false,
                    diagnostic: item.error ?? (item.active ? "Legacy scan detected open files but did not record process identities." : "Imported legacy scan; process identities and file counts were not recorded."), elapsedSeconds: 0)
            }
            try append(ScanRecord(id: id, startedAt: snapshot.date, finishedAt: snapshot.date, scope: "Imported SpaceCheck scan", complete: true,
                freeBytes: snapshot.freeBytes, measurements: measured, discoveryNotes: ["Original source preserved byte-for-byte in imports. Activity details were unavailable."], legacySource: sourceDigest))
            count += 1
        }
        try writeNew(encoder.encode(MigrationReceipt(digest: sourceDigest, importedAt: Date(), snapshotCount: count)), to: receiptURL)
        return count
    }
}
struct LegacyItem: Codable {
    var path: String; var name: String; var kind: String; var reason: String; var bytes: Int64
    var previousBytes: Int64?; var active: Bool; var error: String?
}
struct LegacySnapshot: Codable { var date: Date; var freeBytes: Int64; var items: [LegacyItem] }
