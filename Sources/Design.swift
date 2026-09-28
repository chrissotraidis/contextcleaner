import SwiftUI

// Design system, see docs/DESIGN.md. Five destinations, one filter row inside Locations,
// three reserved status colors, one hue per category, system accent for selection.

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", locations = "Locations", watching = "Watching", needsAttention = "Needs Attention", history = "History"
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
        case .overview: return "See what takes space, what changes, and what it belongs to."
        case .locations: return "Every place this app measures. Select a row to see its story."
        case .watching: return "Locations you watch, plus ones that keep growing. Checked first on every scan."
        case .needsAttention: return "Could not be measured completely. Each row says why and what to do."
        case .history: return "Every scan, newest first, with what changed."
        }
    }
    /// Sidebar icons use a status hue only where the destination is itself a status.
    var tint: Color? { self == .needsAttention ? .attention : nil }
}

enum LocationFilter: String, CaseIterable, Identifiable {
    case all = "All", rebuildable = "Rebuildable", growing = "Growing", reviewLater = "Review later", excluded = "Excluded"
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .all: return "Every measured or discovered location that is not excluded."
        case .rebuildable: return "Caches and build output that a tool can recreate, with no process holding files open at scan time. Rebuildable is not the same as unused; review each before removing anything yourself."
        case .growing: return "Locations that grew between two comparable scans and are not marked as expected."
        case .reviewLater: return "Locations you asked to be reminded about later."
        case .excluded: return "Locations you told Context Cleaner not to scan. Nothing here is measured."
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
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
            content
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The one context menu for a location. Used by the table, the overview cards and the inspector.
struct LocationActions: View {
    @ObservedObject var model: CleanerModel
    let path: String
    var body: some View {
        let policy = model.preferences.policy(path)
        let busy = model.running || model.inspecting || model.discovering
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        Button("Rescan This Folder") { model.selected = path; model.scan(selectedOnly: true) }.disabled(busy || policy.excluded)
        Divider()
        Button(policy.watched ? "Stop Watching" : "Watch") { model.policy(path) { $0.watched.toggle() } }
        Button(policy.expected ? "Growth Is Not Expected" : "Growth Is Expected") { model.policy(path) { $0.expected.toggle() } }
        Button("Review Tomorrow") { model.policy(path) { $0.reviewAfter = Date().addingTimeInterval(86400) } }
        Button("Tags and Notes…") { model.editing = path }
        Divider()
        Button(policy.excluded ? "Include in Scans" : "Exclude from Scans") { model.policy(path) { $0.excluded.toggle() } }.disabled(model.running || model.inspecting)
    }
}
