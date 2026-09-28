import Foundation
@main struct InspectCLI {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else { throw NSError(domain: "Provide new report path and one or more read-only scan roots", code: 1) }
        let roots = Array(CommandLine.arguments.dropFirst(2))
        var items: [FolderMeasurement] = []
        for path in roots {
            let item = TreeMeasure.measure(Classifier.profile(path: path, home: NSHomeDirectory()), preferences: Preferences(), cancellation: Cancellation(), activity: [], activityAvailable: false)
            items.append(item)
            print("\(item.profile.name): \(item.state.rawValue), \(item.fileCount) files, \(item.allocatedBytes.map(byteLabel) ?? "unknown"), \(String(format:"%.3f",item.elapsedSeconds)) seconds, \(item.contents?.children.count ?? 0) retained children")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try writeNew(encoder.encode(items), to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
