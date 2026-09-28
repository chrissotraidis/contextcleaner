import Foundation

struct ActivitySnapshot {
    var observations: [ProcessEvidence]
    var available: Bool
    var note: String
    static func parse(_ output: String) -> [ProcessEvidence] {
        var pid = 0, command = "Unknown", access = "unknown"
        var entries: Set<ProcessEvidence> = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            switch prefix {
            case "p": pid = Int(value) ?? 0; command = "Unknown"; access = "unknown"
            case "c": command = value
            case "f": access = "unknown"
            case "a": access = value == "r" ? "read-capable handle" : value == "w" ? "write-capable handle" : value == "u" ? "read/write-capable handle" : "unknown mode"
            case "n": if value.hasPrefix("/") { entries.insert(ProcessEvidence(pid: pid, command: command, access: access, path: value)) }
            default: break
            }
        }
        return entries.sorted { a,b in a.pid == b.pid ? a.path < b.path : a.pid < b.pid }
    }
    static func capture(cancellation: Cancellation = Cancellation()) -> ActivitySnapshot {
        if cancellation.stopped { return ActivitySnapshot(observations: [], available: false, note: "Cancelled before checking process handles.") }
        let helperStart = ProcessInfo.processInfo.systemUptime
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-Fpcfan", "-u", NSUserName()]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ActivitySnapshot(observations: [], available: false, note: error.localizedDescription) }
        // Only terminate the read-only helper started here if it exceeds the limit.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { if process.isRunning && (cancellation.stopped || ProcessInfo.processInfo.systemUptime - helperStart >= 15) { process.terminate() } }
        timer.resume()
        var data = Data(), outputLimited = false
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if !outputLimited && data.count + chunk.count <= 16 * 1024 * 1024 { data.append(chunk) }
            else { outputLimited = true; if process.isRunning { process.terminate() } }
        }
        process.waitUntilExit(); timer.cancel()
        let complete = process.terminationStatus == 0 && !cancellation.stopped && !outputLimited
        return ActivitySnapshot(observations: complete ? parse(String(decoding: data, as: UTF8.self)) : [], available: complete,
            note: complete ? "Open handles observed at scan start. Handle access modes do not establish actual writes or inactivity." : outputLimited ? "Open-file output exceeded its 16 MiB allowance; activity is unknown." : "Open-file helper failed, was cancelled or timed out; activity is unknown.")
    }
}
struct ScanEngine {
    static func scan(profiles: [FolderProfile], preferences: Preferences, scope: String, notes: [String], cancellation: Cancellation,
                     limits: ScanLimits = .manual, totalSeconds: TimeInterval = 900, onItem: @escaping (FolderMeasurement, Int, Int) -> Void) -> ScanRecord {
        let start = Date(), started = ProcessInfo.processInfo.systemUptime, activity = ActivitySnapshot.capture(cancellation: cancellation)
        var measurements: [FolderMeasurement] = []
        for (index, profile) in profiles.enumerated() {
            if cancellation.stopped { break }
            let remaining = totalSeconds - (ProcessInfo.processInfo.systemUptime - started)
            if remaining <= 0 { break }
            var allowance = limits; allowance.seconds = min(allowance.seconds, remaining)
            let item = TreeMeasure.measure(profile, preferences: preferences, cancellation: cancellation,
                activity: activity.observations, activityAvailable: activity.available, limits: allowance)
            measurements.append(item); onItem(item, index + 1, profiles.count)
            if cancellation.stopped { break }
        }
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize]) as? NSNumber)?.int64Value
        return ScanRecord(id: UUID().uuidString, startedAt: start, finishedAt: Date(), scope: scope,
            complete: !cancellation.stopped && measurements.count == profiles.count && !measurements.contains(where: { [.limited, .cancelled, .inaccessible, .failed].contains($0.state) }), freeBytes: free, measurements: measurements,
            discoveryNotes: notes + [activity.note, "Allowance: up to \(Int(limits.seconds)) seconds and \(limits.entries.formatted()) entries per location; \(Int(totalSeconds)) seconds per pass. Limits are checked between filesystem calls.", "Visited \(measurements.count) of \(profiles.count) selected locations. Unvisited locations retain their previous observations."], legacySource: nil, requestedCount: profiles.count, stopReason: cancellation.stopped ? "Cancelled by you" : measurements.count < profiles.count ? "Pass time allowance reached" : measurements.contains(where: { [.limited, .inaccessible, .failed].contains($0.state) }) ? "Some locations need attention" : nil)
    }
}
