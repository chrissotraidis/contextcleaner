import SwiftUI

// Design system, see docs/DESIGN.md. Five destinations, one filter row inside Locations,
// three reserved status colors, one hue per category, system accent for selection.

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", locations = "Folders", watching = "Watchlist", kept = "Kept", needsAttention = "Couldn't Scan", history = "Scan History"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .locations: return "folder"
        case .watching: return "eye"
        case .kept: return "hand.raised"
        case .needsAttention: return "exclamationmark.triangle"
        case .history: return "clock"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "How full your disk is, and what's filling it."
        case .locations: return "Every folder Context Cleaner knows, largest first."
        case .watching: return "Folders you check on, like caches that keep coming back. Scans measure these first."
        case .kept: return "Folders you chose to keep or not scan. They're never suggested for removal."
        case .needsAttention: return "Folders a scan couldn't read, with a fix for each."
        case .history: return "Each scan: what it checked, when, and what it found."
        }
    }
    /// Sidebar icons use a status hue only where the destination is itself a status.
    var tint: Color? { self == .needsAttention ? .attention : nil }
}

enum LocationFilter: String, CaseIterable, Identifiable {
    case all = "All", safe = "Safe to remove", check = "Check first", keep = "Keep", growing = "Growing", unscanned = "Not scanned", reviewLater = "Review later", excluded = "Turned off"
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .all: return "Big folders you haven't used lately come first. Each row says whether it's safe to remove."
        case .safe: return "Tools recreate these. Remove them yourself in Finder or Xcode."
        case .check: return "Might be fine to remove, but look first. Each one says what to check."
        case .keep: return "App libraries and history. Manage these inside their own apps."
        case .unscanned: return "Found, but not scanned yet. Nothing is wrong."
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

extension FolderMeasurement {
    /// Ordinary file permissions ("Permission denied") need a different fix from macOS privacy protection ("Operation not permitted").
    var permissionDenied: Bool { state == .inaccessible && ((diagnostic ?? "").contains("Permission denied") || (diagnostic ?? "").contains("error 13")) }
    var problem: String { permissionDenied ? "No permission to read it" : state.problem }
}

extension Verdict {
    /// Green: safe. Orange: look first. Gray: leave it to its app.
    var tint: Color {
        switch self {
        case .safe: return .green
        case .check: return .orange
        case .keep: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .check: return "exclamationmark.circle.fill"
        case .keep: return "hand.raised.fill"
        }
    }
    /// The Folders list that shows this answer.
    var filter: LocationFilter {
        switch self {
        case .safe: return .safe
        case .check: return .check
        case .keep: return .keep
        }
    }
    /// What the answer means, in a few words.
    var meaning: String {
        switch self {
        case .safe: return "tools recreate these"
        case .check: return "look inside first"
        case .keep: return "manage in their apps"
        }
    }
}
/// A large, clickable total for one answer at the top of Folders.
struct VerdictTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol).font(.callout.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(selected ? 0.20 : hovering ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(selected ? 0.85 : 0), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(value), \(detail)").accessibilityAddTraits(selected ? .isSelected : [])
    }
}
/// The one-glance answer used in tables and lists.
struct VerdictBadge: View {
    let verdict: Verdict
    var selected = false
    var body: some View {
        Label(verdict.title, systemImage: verdict.symbol)
            .font(.caption.weight(.semibold)).lineLimit(1)
            .foregroundStyle(selected ? Color.white : verdict.tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((selected ? Color.white : verdict.tint).opacity(0.15), in: Capsule())
    }
}
/// "Can I remove it?" with the reason, the evidence and how to do it yourself.
struct VerdictCard: View {
    let advice: Advice
    let sizeSource: String?
    var neverUsed = false
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(advice.verdict.title, systemImage: advice.verdict.symbol).font(.headline).foregroundStyle(advice.verdict.tint)
            Text(advice.reason).font(.callout).fixedSize(horizontal: false, vertical: true)
            ForEach(advice.evidence, id: \.self) { line in
                Label(line, systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text([advice.lastUsed.map { "Last used " + ageText($0) } ?? (neverUsed ? "Never started" : "Last use not recorded yet"), sizeSource].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("How to remove it yourself").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(advice.howTo).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let command = advice.command {
                HStack(spacing: 8) {
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 8).padding(.vertical, 5).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string); copied = true
                    }.controlSize(.small).help("Copies the command. Context Cleaner never runs it.")
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(advice.verdict.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: advice) { _, _ in copied = false }
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
        Button(policy.isKept ? "Stop Keeping" : "Keep, Never Suggest") { model.policy(path) { $0.isKept.toggle() } }
            .help(policy.isKept ? "Suggest this folder again when it looks safe to remove" : "Keep this folder out of every suggestion. It moves to Kept.")
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
        Button("Keep All, Never Suggest") { for path in paths { model.policy(path) { $0.isKept = true } }; model.selection = [] }
        Divider()
        Button("Exclude All from Scans") { for path in paths { model.policy(path) { $0.excluded = true } } }.disabled(model.running || model.inspecting)
        Button("Clear Selection") { model.selection = [] }
    }
}
