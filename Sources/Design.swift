import SwiftUI

// Design system, see docs/DESIGN.md. Five destinations, one filter row inside Locations,
// three reserved status colors, one hue per category, system accent for selection.

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", freeUp = "Free Up Space", locations = "Folders", watching = "Watchlist", kept = "Ignored", needsAttention = "Couldn't Scan", history = "History"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .freeUp: return "checklist"
        case .overview: return "square.grid.2x2"
        case .locations: return "folder"
        case .watching: return "eye"
        case .kept: return "eye.slash"
        case .needsAttention: return "exclamationmark.triangle"
        case .history: return "clock"
        }
    }
    var subtitle: String {
        switch self {
        case .freeUp: return "What nothing has touched for a while, biggest first. Tick it, copy one command, paste it in your terminal."
        case .overview: return "How full your disk is, and what's filling it."
        case .locations: return "Every folder Context Cleaner knows, biggest first."
        case .watching: return "Folders you check on, like caches that keep coming back. Scans measure these first."
        case .kept: return "Folders you keep out of suggestions, or don't scan at all. Context Cleaner leaves them alone."
        case .needsAttention: return "Folders a scan couldn't read, with a fix for each."
        case .history: return "What you moved to the Trash, and what each scan found."
        }
    }
    /// Sidebar icons use a status hue only where the destination is itself a status.
    var tint: Color? { self == .needsAttention ? .attention : nil }
}

enum LocationFilter: String, CaseIterable, Identifiable {
    case all = "All", safe = "Safe to remove", rebuild = "Rebuildable", check = "Review first", keep = "Not for the Trash", inside = "Old items inside folders", growing = "Growing", unscanned = "Not scanned yet", reviewLater = "Remind me later", excluded = "Scanning off"
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .all: return "Safe to remove: not needed again. Rebuildable: the next build recreates it. Review first: may hold something only here."
        case .safe: return "Not needed again: the project is finished or it's sat unused for weeks. Nothing is lost."
        case .rebuild: return "Still in use, but the next build or download recreates it. Nothing is lost; you wait for that build."
        case .check: return "May hold something that exists only here, such as uncommitted work, a backup or test results. Look first."
        case .keep: return "Not worth moving to the Trash: app libraries and chat history (manage them in their apps), and folders that take no space on this Mac."
        case .unscanned: return "Found, but not scanned yet. Nothing is wrong."
        case .growing: return "Grew between two scans and not marked as expected."
        case .reviewLater: return "Folders you asked to come back to."
        case .inside: return "Folders holding old builds or downloads that haven't changed in a week or more. Open one to see them."
        case .excluded: return "Folders you stopped scanning. Their sizes are from before you turned scanning off."
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
    /// Only "Operation not permitted" is macOS privacy protection, which Full Disk Access fixes. Anything else, such as a
    /// folder a task changed mid-scan, is a read error that scanning again usually clears.
    var privacyBlocked: Bool { state == .inaccessible && (diagnostic ?? "").contains("Operation not permitted") }
    var problem: String {
        if permissionDenied { return "No permission to read it" }
        if state == .inaccessible && !privacyBlocked { return "Part of it couldn't be read" }
        return state.problem
    }
}

extension Color {
    /// Old items inside folders: a softer green than Safe, since they cost at most a rebuild.
    static let insideTint = Color(red: 0.52, green: 0.80, blue: 0.56)
}
extension Verdict {
    /// Green: nothing lost. Teal: costs a rebuild. Orange: your call. Gray: leave it to its app.
    var tint: Color {
        switch self {
        case .safe: return .green
        case .rebuild: return .cyan
        case .check: return .orange
        case .keep: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .rebuild: return "arrow.triangle.2.circlepath.circle.fill"
        case .check: return "questionmark.circle.fill"
        case .keep: return "hand.raised.fill"
        }
    }
    /// The Folders list that shows this answer.
    var filter: LocationFilter {
        switch self {
        case .safe: return .safe
        case .rebuild: return .rebuild
        case .check: return .check
        case .keep: return .keep
        }
    }
    /// What the answer means, in a few words.
    /// The answer in one or two words, for tight spaces.
    /// The answer on a Folders tile, where the hint underneath says what it means.
    var shortTitle: String { title }
    /// The difference between the answers, in three words or so, for tiles and legends.
    var hint: String {
        switch self {
        case .safe: return "not needed again"
        case .rebuild: return "rebuilds itself"
        case .check: return "look inside first"
        case .keep: return "app data, or frees nothing"
        }
    }
    var meaning: String {
        switch self {
        case .safe: return "not needed again"
        case .rebuild: return "recreated by the next build"
        case .check: return "may be the only copy; look first"
        case .keep: return "app data, or frees nothing here"
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
                // The whole answer, even on a narrow tile: the icon goes first, then the text shrinks a little.
                ViewThatFits(in: .horizontal) {
                    Label(title, systemImage: symbol)
                    Text(title).lineLimit(1).minimumScaleFactor(0.8)
                }.font(.callout.weight(.semibold)).foregroundStyle(tint)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
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
    /// The folder, when moving it to the Trash yourself is a sensible option.
    var trashPath: String? = nil
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
            if !advice.staleItems.isEmpty { staleSection }
            Divider()
            Text("How to remove it yourself").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(advice.howTo).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let trashPath, advice.verdict != .keep {
                TrashCopyButton(paths: [trashPath])
            }
            if let command = advice.command {
                HStack(spacing: 8) {
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 8).padding(.vertical, 5).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    Button(copied ? "Copied" : "Copy") {
                        copyToClipboard(command); copied = true
                    }.controlSize(.small).help("Copies the command. Context Cleaner never runs it.")
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(advice.verdict.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: advice) { _, _ in copied = false }
    }
    /// The old items inside a busy folder: the part you can remove without disturbing current work.
    private var staleSection: some View {
        let items = advice.staleItems
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Old items inside · \(byteLabel(advice.staleBytes)) in \(items.count) \(items.count == 1 ? "item" : "items"), untouched \(advice.staleDays)+ days").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(items.prefix(10)) { item in
                HStack(spacing: 6) {
                    Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle).help(item.path)
                    Spacer(minLength: 6)
                    Text(item.modifiedAt.map { ageText($0) } ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Text(byteLabel(item.bytes)).font(.callout).monospacedDigit().lineLimit(1).fixedSize()
                }
            }
            if items.count > 10 { Text("and \(items.count - 10) more").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Button("Show in Finder") { revealInFinder(items.map(\.path)) }
                    .controlSize(.small).help("Selects these items in Finder. Press ⌘⌫ there to move them to the Trash yourself.")
                TrashCopyButton(paths: items.map(\.path), bytes: advice.staleBytes)
            }
        }
    }
}

/// What happened to the last Trash command you asked for, for every Copy button to show.
@MainActor final class TrashCopyState: ObservableObject {
    static let shared = TrashCopyState()
    @Published private(set) var paths: [String] = []
    @Published private(set) var checking = false
    @Published private(set) var copied = 0
    @Published private(set) var leftOut = 0
    func start(_ paths: [String]) { self.paths = paths; checking = true; copied = 0; leftOut = 0 }
    func finish(_ paths: [String], copied: Int, leftOut: Int) { self.paths = paths; checking = false; self.copied = copied; self.leftOut = leftOut }
}
/// The one Copy Move-to-Trash button. It rechecks the folders first, then says what it copied, or why it copied nothing.
/// A big selection, or one with Review first folders, asks once in place before copying. After a copy, a button beside it
/// opens your terminal, chosen in Settings, so you can paste.
struct TrashCopyButton: View {
    let paths: [String]
    var bytes: Int64? = nil
    /// Sizes for items outside the scanned folders, which the app doesn't otherwise know.
    var sizes: [String: Int64] = [:]
    /// For items outside the scanned folders: their newest change, and the checkouts git must still call backed up.
    var seen: [String: Date] = [:]
    var backedUp: [String] = []
    var prominent = false
    /// Shift-Command-C copies, for the one main Copy button on screen.
    var shortcut = false
    /// A different name for the button before it's clicked.
    var label: String? = nil
    /// Asked in place before copying, from trashConfirmation. Nil copies straight away.
    var confirm: String? = nil
    @ObservedObject private var state = TrashCopyState.shared
    @AppStorage(terminalDefaultsKey) private var terminalID = ""
    /// The paths a confirmation is showing for. Changing the selection drops it.
    @State private var asking: [String]?
    var body: some View {
        if let confirm, asking == paths, !paths.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { confirmText(confirm).fixedSize(); confirmButtons }
                VStack(alignment: .leading, spacing: 6) { confirmText(confirm).fixedSize(horizontal: false, vertical: true); HStack(spacing: 8) { confirmButtons } }
            }.padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.caution.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        } else {
            HStack(spacing: 8) {
                copyButton
                if !paths.isEmpty && state.paths == paths && !state.checking && state.copied > 0 {
                    let terminal = chosenTerminal(terminalID)
                    Button { openTerminal(terminal) } label: { Label("Open \(terminal.name)", systemImage: "terminal") }
                        .controlSize(prominent ? .regular : .small)
                        .help("Opens \(terminal.name). Paste with Command-V and press Return. Choose another terminal in Settings.")
                }
            }
        }
    }
    private func confirmText(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
    }
    @ViewBuilder private var confirmButtons: some View {
        Button("Cancel") { asking = nil }.controlSize(.small).keyboardShortcut(.cancelAction)
        Button("Copy Anyway") { asking = nil; requestTrashCopy(paths, bytes: bytes, sizes: sizes, seen: seen, backedUp: backedUp) }
            .buttonStyle(.borderedProminent).controlSize(.small)
    }
    private var copyButton: some View {
        let mine = !paths.isEmpty && state.paths == paths
        let title: String = {
            guard mine else { return (label ?? "Copy Move-to-Trash Command") + (paths.count > 1 ? " (\(paths.count))" : "") }
            if state.checking { return "Checking \(paths.count == 1 ? "the folder" : "\(paths.count) items")…" }
            if state.copied == 0 { return "Nothing copied" }
            return paths.count == 1 ? "Copied" : state.copied == paths.count ? "Copied all \(paths.count)" : "Copied \(state.copied) of \(paths.count)"
        }()
        let symbol = mine && !state.checking ? (state.copied > 0 ? "checkmark.circle.fill" : "exclamationmark.circle") : "doc.on.clipboard"
        let button = Button {
            if confirm != nil && asking != paths { asking = paths } else { asking = nil; requestTrashCopy(paths, bytes: bytes, sizes: sizes, seen: seen, backedUp: backedUp) }
        } label: { Label(title, systemImage: symbol).monospacedDigit().contentTransition(.numericText()) }
            .controlSize(.small).disabled(paths.isEmpty || state.checking)
            .help("Checks each item is still there, not open in an app and unchanged since the scan, then copies one Terminal command that moves them to the Trash and prints a line for each. Put Back works. Context Cleaner never runs it." + (shortcut ? " Shortcut: Shift-Command-C." : ""))
            .keyboardShortcut(shortcut ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
        return Group { if prominent { button.buttonStyle(.borderedProminent).controlSize(.regular) } else { button } }
    }
}

// One place for each small system action, so every button does it the same way.
/// Puts text on the clipboard, replacing what was there.
func copyToClipboard(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
/// Selects these items in a Finder window.
func revealInFinder(_ paths: [String]) { NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) }) }
/// Opens the Trash in Finder.
func openTrash() { NSWorkspace.shared.open(URL(fileURLWithPath: homeDirectory + "/.Trash")) }
/// Opens System Settings at Privacy & Security › Full Disk Access.
func openFullDiskAccessSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
}
/// Terminal apps a copied command can be pasted into. Settings lists the ones installed.
struct TerminalApp: Identifiable, Equatable { let id: String; let name: String }
let terminalApps: [TerminalApp] = [
    TerminalApp(id: "com.apple.Terminal", name: "Terminal"),
    TerminalApp(id: "com.mitchellh.ghostty", name: "Ghostty"),
    TerminalApp(id: "com.googlecode.iterm2", name: "iTerm"),
    TerminalApp(id: "dev.warp.Warp-Stable", name: "Warp"),
    TerminalApp(id: "net.kovidgoyal.kitty", name: "kitty"),
    TerminalApp(id: "org.alacritty", name: "Alacritty"),
    TerminalApp(id: "com.github.wez.wezterm", name: "WezTerm"),
]
let terminalDefaultsKey = "terminalApp"
func terminalInstalled(_ id: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
/// The terminal chosen in Settings while it's still installed; otherwise Terminal, which every Mac has.
func chosenTerminal(_ saved: String?, installed: (String) -> Bool = terminalInstalled) -> TerminalApp {
    if let saved, let app = terminalApps.first(where: { $0.id == saved }), installed(app.id) { return app }
    return terminalApps[0]
}
/// Opens the terminal only. You paste the command and press Return yourself.
func openTerminal(_ app: TerminalApp) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

/// Asks the app to copy a Move-to-Trash command and watch its folders until they're gone.
extension Notification.Name { static let copyTrash = Notification.Name("ContextCleaner.copyTrash") }
/// seen gives the newest change for items the scan doesn't know, and backedUp lists checkouts that must still be backed up
/// by git when you copy, such as projects from Everything else.
func requestTrashCopy(_ paths: [String], bytes: Int64? = nil, sizes: [String: Int64] = [:], seen: [String: Date] = [:], backedUp: [String] = []) {
    var info: [String: Any] = ["paths": paths, "sizes": sizes, "seen": seen, "backedUp": backedUp]
    if let bytes { info["bytes"] = bytes }
    NotificationCenter.default.post(name: .copyTrash, object: nil, userInfo: info)
}

extension Color {
    /// Reserved status colors. Never used as category hues.
    /// Red: a scan couldn't read something. Nothing else is red.
    static let attention = Color.red
    /// Blue: used space, and growth in it. The chart's used area is the same blue.
    static let growing = Color.blue
    /// Green: free space, and space freed.
    static let stable = Color.green
    /// Orange: needs you. Your call, and warnings like an old scan or a waiting permission dialog.
    static let caution = Color.orange
    /// Purple: folders you keep out of suggestions or don't scan.
    static let ignored = Color.purple
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
        case .virtualMachine: return Color(hue: 0.58, saturation: 0.35, brightness: 0.75)
        case .appData: return .gray
        case .temporary: return Color(hue: 0.08, saturation: 0.3, brightness: 0.65)
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
        Button("Show in Finder") { revealInFinder([path]) }
        Button("Scan Again") { model.selected = path; model.scan(selectedOnly: true) }.disabled(busy || policy.excluded)
        Divider()
        Button(policy.isKept ? "Stop Ignoring" : "Ignore This Folder") { model.policy(path) { $0.isKept.toggle() } }
            .help(policy.isKept ? "Suggest this folder again when it looks safe to remove" : "Still scanned, but never suggested. It moves to Ignored.")
        Button(policy.isWatched ? "Stop Watching" : "Watch for Growth") { model.policy(path) { $0.isWatched.toggle() } }
            .help("Watched folders are scanned first and listed in Watchlist")
        Button(policy.expected ? "Warn Me When It Grows" : "Its Growth Is Normal") { model.policy(path) { $0.expected.toggle() } }
            .help(policy.expected ? "Show it under Growing again" : "Stop listing it under Growing; its answer becomes Not for the Trash")
        Button("Remind Me Tomorrow") { model.policy(path) { $0.reviewAfter = Date().addingTimeInterval(86400) } }
        Button("Tags & Notes…") { model.editing = path }
        Divider()
        Button(policy.excluded ? "Scan This Folder Again" : "Stop Scanning This Folder") { model.policy(path) { $0.excluded.toggle() } }.disabled(model.running || model.inspecting)
    }
}

/// Shared actions for a multi-selection, in the context menu, inspector and menu bar.
struct SelectionActions: View {
    @ObservedObject var model: CleanerModel
    let paths: [String]
    var body: some View {
        Button("Reveal \(paths.count) in Finder") { revealInFinder(paths) }
        Button("Watch All") { for path in paths { model.policy(path) { $0.isWatched = true } } }
        Button("Stop Watching All") { for path in paths { model.policy(path) { $0.isWatched = false; $0.autoWatched = nil } } }
        Button("Ignore These Folders") { for path in paths { model.policy(path) { $0.isKept = true } }; model.selection = [] }
        Divider()
        Button("Stop Scanning All") { for path in paths { model.policy(path) { $0.excluded = true } } }.disabled(model.running || model.inspecting)
        Button("Clear Selection") { model.selection = [] }
    }
}
