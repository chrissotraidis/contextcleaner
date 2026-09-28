import Foundation

struct ScanPlanner {
    static func scheduledInterval(_ preferences: Preferences) -> TimeInterval? {
        switch preferences.effectiveSchedule { case "daily": return 86400; case "weekly": return 7 * 86400; default: return nil }
    }
    static func dailyDue(_ preferences: Preferences, now: Date) -> Bool {
        guard let interval = scheduledInterval(preferences) else { return false }
        guard let last = preferences.lastScheduledAttempt else { return true }
        return now.timeIntervalSince(last) >= interval
    }
    static func discoveryDue(_ preferences: Preferences, now: Date) -> Bool {
        guard let last = preferences.lastDiscovery else { return true }
        return now.timeIntervalSince(last) >= 7 * 86400
    }
    static func priority(_ profiles: [FolderProfile], preferences: Preferences, records: [ScanRecord], now: Date, limit: Int = 12) -> [FolderProfile] {
        var latest: [String: Date] = [:]
        for record in records { for item in record.measurements where item.state != .cancelled && item.state != .excluded {
            latest[item.profile.path] = max(latest[item.profile.path] ?? .distantPast, item.observedAt)
        }}
        func score(_ p: FolderProfile) -> Double {
            let policy = preferences.policy(p.path)
            guard let date = latest[p.path] else { return 1000 }
            let age = max(0, now.timeIntervalSince(date) / 86400)
            let growing = (growth(p.path, records: records).delta ?? 0) > 0
            let weight = policy.isWatched ? 4.0 : growing ? 3.0 : policy.expected ? 0.5 : 1.0
            return (age + 0.1) * weight
        }
        var unique: [String: FolderProfile] = [:]
        for p in profiles where !preferences.excluded(p.path) && (preferences.policy(p.path).reviewAfter ?? .distantPast) <= now { unique[p.path] = p }
        let ordered = unique.values.sorted { a,b in
            let x = score(a), y = score(b)
            return x == y ? a.path < b.path : x > y
        }
        var selected: [FolderProfile] = []
        for profile in ordered {
            if selected.count >= max(0, limit) { break }
            guard !selected.contains(where: { containsPath($0.path, profile.path) || containsPath(profile.path, $0.path) }) else { continue }
            selected.append(profile)
        }
        return selected
    }
}
