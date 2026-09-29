import Foundation

struct FileTypeSummary: Codable, Identifiable {
    var id: String { kind }
    var kind: String
    var files: Int = 0
    var bytes: Int64 = 0
}
struct ChildSummary: Codable, Identifiable {
    var id: String { name }
    var name: String
    var directory: Bool
    var identity: String
    var bytes: Int64 = 0
    var files: Int = 0
    var modifiedAt: Date?
}
struct FolderContents: Codable {
    var children: [ChildSummary]
    var fileTypes: [FileTypeSummary]
    var listedChildren: Int
    var retainedLimit: Int
    var omittedEntries: Int
    var exhaustive: Bool { listedChildren <= retainedLimit && omittedEntries == 0 }
}
struct ChildChange: Identifiable {
    var id: String { name }
    var name: String
    var event: String
    var delta: Int64?
}
/// Keeps each folder's child listing only for its most recent scans, in memory. Sizes and dates stay for history;
/// the saved scan files are never changed.
func droppingOldContents(_ records: [ScanRecord], keep: Int = 2) -> [ScanRecord] {
    var seen: [String: Int] = [:]
    var result = records
    for r in result.indices.sorted(by: { result[$0].finishedAt > result[$1].finishedAt }) {
        for m in result[r].measurements.indices where result[r].measurements[m].contents != nil {
            let path = result[r].measurements[m].profile.path
            seen[path, default: 0] += 1
            if seen[path]! > keep { result[r].measurements[m].contents = nil }
        }
    }
    return result
}
func childChanges(_ path: String, records: [ScanRecord]) -> [ChildChange]? {
    let measures = records.flatMap(\.measurements).filter { $0.profile.path == path }.sorted { $0.observedAt < $1.observedAt }
    guard measures.count >= 2 else { return nil }
    let old = measures[measures.count - 2], new = measures[measures.count - 1]
    guard old.state == .measured, new.state == .measured, old.scopeID == new.scopeID,
          let a = old.contents, let b = new.contents else { return nil }
    let before = Dictionary(uniqueKeysWithValues: a.children.map { ($0.name,$0) })
    let after = Dictionary(uniqueKeysWithValues: b.children.map { ($0.name,$0) })
    return Set(before.keys).union(after.keys).sorted().compactMap { name in
        switch (before[name], after[name]) {
        case let (x?,y?):
            if x.identity != y.identity { return ChildChange(name: name, event: "Different filesystem identity at this name", delta: y.bytes - x.bytes) }
            if x.bytes != y.bytes { return ChildChange(name: name, event: "Size changed", delta: y.bytes - x.bytes) }
            if x.modifiedAt != y.modifiedAt || x.files != y.files { return ChildChange(name: name, event: "Metadata changed; same allocated size", delta: 0) }
            return nil
        case let (nil,y?):
            let match = a.children.first { $0.identity == y.identity && after[$0.name] == nil }
            if let match, a.exhaustive && b.exhaustive { return ChildChange(name: name, event: "Possible rename from \(match.name); identity matched", delta: y.bytes - match.bytes) }
            return ChildChange(name: name, event: a.exhaustive ? "Newly observed" : "Not in previous retained detail", delta: nil)
        case (_?,nil): return ChildChange(name: name, event: b.exhaustive ? "No longer observed; cause unknown" : "Not in current retained detail", delta: nil)
        default: return nil
        }
    }
}

struct SimulatorLocations {
    static func deviceRoot(_ path: String) -> String? {
        guard let range = path.range(of: "/CoreSimulator/Devices/") else { return nil }
        let tail = path[range.upperBound...]
        guard let device = tail.split(separator: "/").first else { return nil }
        return String(path[..<range.upperBound]) + device
    }
    static func containerRoot(_ path: String) -> (path: String, kind: String)? {
        guard let device = deviceRoot(path) else { return nil }
        for (suffix,kind) in [("Data/Application", "app data"), ("Bundle/Application", "installed app"), ("Shared/AppGroup", "shared app group")] {
            let parent = device + "/data/Containers/" + suffix
            if containsPath(parent,path), path != parent, let id = path.dropFirst(parent.count + 1).split(separator: "/").first {
                return (parent + "/" + id,kind)
            }
        }
        return nil
    }
    static func containers(_ device: String, preferences: Preferences) throws -> [String] {
        var paths: [String] = []
        for suffix in ["Data/Application", "Bundle/Application", "Shared/AppGroup"] {
            let parent = device + "/data/Containers/" + suffix
            if preferences.excluded(parent) || !MetadataReader.hasNoSymlinkComponents(parent) { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let listing = DirectoryListing.read(parent, preferences: preferences)
            guard listing.complete else { throw NSError(domain: listing.note ?? "Container listing incomplete", code: 1) }
            for name in listing.names where !name.hasPrefix(".") {
                let path = parent + "/" + name
                if !preferences.excluded(path) { paths.append(path) }
            }
        }
        return paths
    }
}
