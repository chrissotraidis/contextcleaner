import SwiftUI

// Design system, see docs/DESIGN.md. Five destinations, one filter row inside Locations,
// three reserved status colors, one hue per category, system accent for selection.

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", locations = "Folders", watching = "Watchlist", needsAttention = "Couldn't Scan", history = "Scan History"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .locations: return "folder"
        case .watching: return "eye"
        case .needsAttention: return "exclamationmark.triangle"
        case .history: return "clock"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "How full your disk is, and what's filling it."
        case .locations: return "Every folder Context Cleaner knows, largest first."
        case .watching: return "Folders you're keeping an eye on. Scheduled checks look at these first."
        case .needsAttention: return "Folders a scan couldn't read, with a fix for each."
        case .history: return "Each scan: what it checked, when, and what it found."
        }
    }
    /// Sidebar icons use a status hue only where the destination is itself a status.
    var tint: Color? { self == .needsAttention ? .attention : nil }
}

enum LocationFilter: String, CaseIterable, Identifiable {
    case all = "All", scanned = "Scanned", unscanned = "Not scanned", rebuildable = "Caches & builds", growing = "Growing", reviewLater = "Review later", excluded = "Excluded"
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .all: return "Sizes from your latest scans."
        case .scanned: return "Folders with a complete size."
        case .unscanned: return "Found, but not scanned yet. Nothing is wrong."
        case .rebuildable: return "Caches and build files a tool can recreate. Check each before removing anything yourself."
        case .growing: return "Grew between two scans and not marked as expected."
        case .reviewLater: return "Folders you asked to come back to."
        case .excluded: return "Folders you turned off. They aren't scanned."
        }
    }
}

extension MeasurementState {
    /// Why a scan couldn't read a folder, in plain words.
    var problem: String {
        switch self {
        case .inaccessible: return "macOS blocked access"
        case .limited: return "Too large for the time limit"
        case .missing: return "Folder no longer exists"
        default: return "Scan couldn't finish"
        }
    }
    var problemSymbol: String {
        switch self {
        case .inaccessible: return "lock"
        case .limited: return "hourglass"
        case .missing: return "questionmark.folder"
        default: return "exclamationmark.triangle"
        }
    }
}

extension Color {
    /// Reserved status colors. Never used as category hues.
    static let attention = Color.red
    static let growing = Color.orange
    static let stable = Color.green
}

extension FolderCategory {
    /// One hue per category. Red, orange and green are reserved for status.
    var tint: Color {
        switch self {
        case .packageCache: return .teal
        case .installCache: return .cyan
        case .buildOutput: return .blue
        case .debugSymbols: return .indigo
        case .simulator: return .purple
        case .workspace: return .brown
        case .backup: return Color(hue: 0.83, saturation: 0.5, brightness: 0.95)
        case .history: return .mint
        case .model: return .yellow
        case .download: return Color(hue: 0.13, saturation: 0.35, brightness: 0.72)
        case .appData: return .gray
        case .unknown: return .secondary
        }
    }
}

/// Standard grouped container using the system background hierarchy. GroupBox is avoided on purpose:
/// its AXGroup/AXHeading structure crashes the accessibility automation used to verify every build.
struct Panel<Content: View>: View {
    var title: String
    var symbol: String
    var tint: Color = .accentColor
    var minimumHeight: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(tint) }.font(.headline)
            content
        }.padding(16).frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
            .background(.background.secondary)
    }
}

/// The one context menu for a location. Used by the table, the overview cards and the inspector.
struct LocationActions: View {
    @ObservedObject var model: CleanerModel
    let path: String
    var body: some View {
        let policy = model.preferences.policy(path)
        let busy = model.running || model.inspecting || model.discovering
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        Button("Scan This Folder") { model.selected = path; model.scan(selectedOnly: true) }.disabled(busy || policy.excluded)
        Divider()
        Button(policy.isWatched ? "Remove from Watchlist" : "Add to Watchlist") { model.policy(path) { $0.isWatched.toggle() } }
        Button(policy.expected ? "Growth Is Not Expected" : "Growth Is Expected") { model.policy(path) { $0.expected.toggle() } }
        Button("Review Tomorrow") { model.policy(path) { $0.reviewAfter = Date().addingTimeInterval(86400) } }
        Button("Tags and Notes…") { model.editing = path }
        Divider()
        Button(policy.excluded ? "Include in Scans" : "Exclude from Scans") { model.policy(path) { $0.excluded.toggle() } }.disabled(model.running || model.inspecting)
    }
}

/// Shared actions for a multi-selection, in the context menu, inspector and menu bar.
struct SelectionActions: View {
    @ObservedObject var model: CleanerModel
    let paths: [String]
    var body: some View {
        Button("Reveal \(paths.count) in Finder") { NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) }) }
        Button("Watch All") { for path in paths { model.policy(path) { $0.isWatched = true } } }
        Button("Stop Watching All") { for path in paths { model.policy(path) { $0.isWatched = false; $0.autoWatched = nil } } }
        Divider()
        Button("Exclude All from Scans") { for path in paths { model.policy(path) { $0.excluded = true } } }.disabled(model.running || model.inspecting)
        Button("Clear Selection") { model.selection = [] }
    }
}
