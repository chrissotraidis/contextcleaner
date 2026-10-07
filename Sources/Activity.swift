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
/// Collects finished folders from scan workers until the interface takes them.
/// add returns true when the caller should schedule a delivery (the first item since the last drain).
final class ScanBatch {
    private let lock = NSLock()
    private var items: [FolderMeasurement] = [], done = 0, scheduled = false
    func add(_ item: FolderMeasurement, done count: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items.append(item); done = max(done, count)
        if scheduled { return false }
        scheduled = true; return true
    }
    func drain() -> ([FolderMeasurement], Int) {
        lock.lock(); defer { lock.unlock() }
        let result = (items, done); items = []; scheduled = false
        return result
    }
}
struct ScanEngine {
    static func scan(profiles: [FolderProfile], preferences: Preferences, scope: String, notes: [String], cancellation: Cancellation,
                     limits: ScanLimits = .manual, totalSeconds: TimeInterval = 900, concurrency: Int = 1, onItem: @escaping (FolderMeasurement, Int, Int) -> Void) -> ScanRecord {
        let start = Date(), started = ProcessInfo.processInfo.systemUptime, activity = ActivitySnapshot.capture(cancellation: cancellation)
        // Workers take the next folder in list order. One slow or blocked folder no longer holds up the rest.
        // Results keep list order; onItem reports how many have finished.
        let lock = NSLock()
        var results: [Int: FolderMeasurement] = [:], next = 0
        let workers = max(1, min(concurrency, profiles.count))
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            while true {
                lock.lock()
                let remaining = totalSeconds - (ProcessInfo.processInfo.systemUptime - started)
                guard next < profiles.count, !cancellation.stopped, remaining > 0 else { lock.unlock(); return }
                let index = next; next += 1
                lock.unlock()
                var allowance = limits; allowance.seconds = min(allowance.seconds, remaining)
                let item = TreeMeasure.measure(profiles[index], preferences: preferences, cancellation: cancellation,
                    activity: activity.observations, activityAvailable: activity.available, limits: allowance)
                lock.lock(); results[index] = item; let done = results.count; lock.unlock()
                onItem(item, done, profiles.count)
            }
        }
        let measurements = results.keys.sorted().map { results[$0]! }
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize]) as? NSNumber)?.int64Value
        let needsAttention = measurements.contains { [.limited, .inaccessible, .failed].contains($0.state) }
        let stopReason: String? = cancellation.stopped ? "Cancelled by you"
            : measurements.count < profiles.count ? "Pass time allowance reached"
            : needsAttention ? "Some locations need attention" : nil
        return ScanRecord(id: UUID().uuidString, startedAt: start, finishedAt: Date(), scope: scope,
            complete: !cancellation.stopped && measurements.count == profiles.count && !measurements.contains(where: { [.limited, .cancelled, .inaccessible, .failed].contains($0.state) }),
            freeBytes: free, measurements: measurements,
            discoveryNotes: notes + [activity.note,
                "Allowance: up to \(Int(limits.seconds)) seconds and \(limits.entries.formatted()) entries per location; \(Int(totalSeconds)) seconds per pass. Limits are checked between filesystem calls.",
                "Visited \(measurements.count) of \(profiles.count) selected locations. Unvisited locations retain their previous observations."],
            legacySource: nil, requestedCount: profiles.count, stopReason: stopReason)
    }
}
