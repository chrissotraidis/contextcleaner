import SwiftUI
import AppKit
import Charts
import Combine

struct TracePoint: Identifiable {
    var id: String; var date: Date; var bytes: Int64; var segment: Int
}
struct MainView: View {
    @ObservedObject var model: CleanerModel
    @State var sortOrder = [KeyPathComparator(\FolderRow.bytes, order: .reverse)]
    var appearance: String { model.preferences.appearance ?? "System" }
    @State var simulatorSearch = ""
    @State var showingAccessHelp = false
    @State var showInside = false
    @State var showDetails = false
    @State var historyTab = 0
    @State var showEmptyCleanups = false
    let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    /// Often enough that anything you moved yourself, in Terminal or Finder, leaves Free up space within seconds.
    let goneTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    var busy: Bool { model.running || model.inspecting || model.discovering }
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.section }, set: { model.categoryFilter = nil; model.section = $0 })) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    let quiet = section == .needsAttention && model.attentionCount == 0
                    Label { Text(section.rawValue) } icon: { Image(systemName: section.symbol).foregroundStyle(quiet ? Color.secondary : section.tint ?? Color.primary) }.tag(section)
                        .badge(section == .needsAttention ? model.attentionCount : 0)
                        .accessibilityLabel(section == .needsAttention && model.attentionCount > 0 ? "\(section.rawValue), \(model.attentionCount) \(model.attentionCount == 1 ? "folder" : "folders")" : section.rawValue)
                }
            }.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                Label("Never deletes. You decide.", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                header
                scanBanner
                if model.section == .freeUp { FreeUpView(model: model) }
                else if model.section == .overview { Dashboard(model: model) }
                else if model.section == .history { history }
                else {
                    // A fixed proportional split never reports a width larger than the window,
                    // so the header, table and inspector stay inside the visible area at any size.
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                filterBar; categoryBanner
                                if model.section == .needsAttention { issuesTable } else { folderTable }
                            }
                            Divider()
                            inspector.frame(width: min(max(geometry.size.width * 0.36, 340), 520))
                        }
                    }
                }
                footer
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(appearance == "Light" ? .light : appearance == "Dark" ? .dark : nil)
        .onChange(of: model.selected) { _, _ in model.inspector = "Overview"; showInside = false; showDetails = false }
        .onChange(of: model.inspector) { _, value in if value == "Contents" { showInside = true } }
        .onChange(of: model.search) { _, value in
            if !value.isEmpty && [.overview, .freeUp, .history].contains(model.section) { model.section = .locations; model.locationFilter = .all; model.categoryFilter = nil }
            model.retainVisibleSelection()
        }
        .onChange(of: model.section) { _, _ in model.retainVisibleSelection() }
        .onChange(of: model.locationFilter) { _, _ in model.retainVisibleSelection() }
        .onChange(of: model.categoryFilter) { _, _ in model.retainVisibleSelection() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(model.backStack.isEmpty).keyboardShortcut("[", modifiers: .command)
                    .help(model.backTitle.map { "Back to \($0) (Command-[)" } ?? "Back")
                Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(model.forwardStack.isEmpty).keyboardShortcut("]", modifiers: .command)
                    .help(model.forwardTitle.map { "Forward to \($0) (Command-])" } ?? "Forward")
            }
            ToolbarItemGroup {
                if model.running || model.discovering {
                    Button { model.cancelWork() } label: { Label("Stop Scan", systemImage: "stop.circle").labelStyle(.titleAndIcon) }
                        .help("Stop after the folder being read now (Command-.)")
                } else {
                    Button { model.showingScanPlan = true } label: { Label("Scan Folders…", systemImage: "magnifyingglass").labelStyle(.titleAndIcon) }
                        .buttonStyle(.borderedProminent).help("See what will be scanned, then start (Command-R)").disabled(model.inspecting || model.store == nil)
                }
            }
            if #available(macOS 26.0, *) { ToolbarSpacer(.fixed) }
            ToolbarItemGroup {
                Button { model.exportReport() } label: { Label("Export Cleanup List…", systemImage: "checklist") }
                    .help("Preview a Markdown report of the folders shown here, then save it (Shift-Command-E)")
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings: scheduled checks, permissions and where Context Cleaner looks (Command-,)")
            }
        }
        .searchable(text: $model.search, prompt: "Search folders, apps, projects, tags")
        .sheet(item: Binding(get: { model.editing.map { EditTarget(id: $0) } }, set: { model.editing = $0?.id })) { target in
            PolicyEditor(path: target.id, initial: model.preferences.policy(target.id)) { value in model.policy(target.id) { $0 = value }; model.editing = nil }
        }
        .sheet(isPresented: $model.showingScanPlan) { ScanPlanView(model: model) }
        .sheet(isPresented: $model.showingElsewhere) { ElsewhereView(model: model) }
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
        .sheet(isPresented: Binding(get: { model.reportPreview != nil }, set: { if !$0 { model.reportPreview = nil } })) {
            ReportPreview(model: model, text: model.reportPreview ?? "")
        }
        .onReceive(timer) { _ in
            model.refreshVolume()
            model.checkScheduledPass()
        }
        .onReceive(goneTimer) { _ in model.checkVanished() }
        // Coming back from Terminal or Finder is when things have moved: check what's gone, and the Trash.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.checkVanished(); model.refreshTrash() }
        .task { model.refreshTrash() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cancellation.cancel(); model.inspectionCancellation.cancel() }
    }
    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if model.section == .overview, let icon = NSImage(named: "NSApplicationIcon") {
                Image(nsImage: icon).resizable().frame(width: 34, height: 34).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.section.rawValue).font(.title2.weight(.semibold))
                Text(model.section.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.section != .overview, let v = model.volume {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(byteLabel(v.free)) free of \(byteLabel(v.total))").font(.caption).monospacedDigit()
                    ProportionBar(value: Double(v.used) / Double(max(v.total, 1)), tint: .accentColor).frame(width: 160)
                }.help("Checked \(v.date.formatted(date: .omitted, time: .shortened))")
            }
        }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 10)
    }
    /// Scope and progress while a scan runs, then a one-line result.
    @ViewBuilder var scanBanner: some View {
        if model.running || model.discovering {
            VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if model.running && model.targetCount > 0 {
                    ProgressView(value: Double(model.completed), total: Double(max(model.targetCount, 1))).frame(width: 140)
                    Text("Scanning \(model.completed) of \(model.targetCount) \(model.targetCount == 1 ? "folder" : "folders")").font(.callout.weight(.medium)).monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                    Text("Finding folders to scan…").font(.callout.weight(.medium))
                }
                Text(model.progress).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("Reading sizes only").font(.caption).foregroundStyle(.secondary)
                Button("Stop") { model.cancelWork() }.controlSize(.small)
            }.padding(.horizontal, 22).padding(.vertical, 8).background(Color.accentColor.opacity(0.08))
            // Reading another app's data or a protected folder makes macOS ask once, and the scan waits for the answer.
            if protectedPlace(model.progress) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Color.caution).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS may be asking for permission").font(.callout.weight(.semibold))
                        Text("If a dialog asks to access data from other apps or your Documents, Desktop or Downloads folder, the scan waits for your answer. Allow includes those folders; Don't Allow skips them. Either way it only reads sizes.")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    Button("Stop These Questions…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                    }.controlSize(.small)
                        .help("Opens Privacy & Security › Full Disk Access. Turning Context Cleaner on there lets it read sizes everywhere without asking each time. Your choice; it still never changes files.")
                }.padding(.horizontal, 22).padding(.vertical, 8).background(Color.caution.opacity(0.10))
            }
            }
        } else if let result = model.lastResult {
            let stopped = result.hasPrefix("Stopped")
            let unreadable = result.contains("couldn't be read")
            HStack(spacing: 10) {
                Image(systemName: stopped ? "stop.circle" : unreadable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(stopped ? Color.caution : unreadable ? Color.attention : Color.accentColor).accessibilityHidden(true)
                Text(result).font(.callout.weight(.medium))
                Spacer()
                if model.overview.growthCount > 0 { Button("Show Growing") { model.categoryFilter = nil; model.search = ""; model.section = .locations; model.locationFilter = .growing }.controlSize(.small) }
                if model.attentionCount > 0 { Button("Show Problems") { model.categoryFilter = nil; model.search = ""; model.section = .needsAttention }.controlSize(.small) }
                Button { model.lastResult = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("Dismiss scan result")
            }.padding(.horizontal, 22).padding(.vertical, 8).background(Color.secondary.opacity(0.08))
        }
    }
    @ViewBuilder var filterBar: some View {
        if model.section == .locations {
            // The answer first: how much is safe, how much needs a look, how much to keep. Each tile is a filter.
            let others: [LocationFilter] = [.inside, .growing, .unscanned, .reviewLater, .keep]
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    let scanned = Verdict.allCases.reduce(0) { $0 + model.verdictTotal($1).count }
                    VerdictTile(title: "All folders", value: "\(scanned) scanned", detail: "not counting ignored", symbol: "folder.fill", tint: .accentColor, selected: model.locationFilter == .all) { model.locationFilter = .all }
                    // Not for the Trash isn't a tile: nothing in it frees space. It's under More lists.
                    ForEach([Verdict.safe, .rebuild, .check]) { verdict in
                        let total = model.verdictTotal(verdict)
                        VerdictTile(title: verdict.shortTitle, value: byteLabel(total.bytes), detail: "\(total.count) · \(verdict.hint)", symbol: verdict.symbol, tint: verdict.tint, selected: model.locationFilter == verdict.filter) { model.locationFilter = verdict.filter }
                            .help(verdict.title + ": " + verdict.meaning)
                    }
                }
                HStack(spacing: 12) {
                    let hidden = model.gone.isEmpty || model.locationFilter == .excluded ? "" : " · \(model.gone.count) \(model.gone.count == 1 ? "folder" : "folders") no longer on disk \(model.gone.count == 1 ? "is" : "are") hidden"
                    Text((model.search.isEmpty ? model.locationFilter.explanation : "\(model.rows.count) \(model.rows.count == 1 ? "match" : "matches") for “\(model.search)” in folder names, apps, projects and tags") + hidden).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.locationFilter == .inside {
                        Button("List Them in Free Up Space") { model.showFreeUp(quietHours: 168) }.controlSize(.small)
                            .help("Free Up Space lists each old item on its own, so you can tick them and copy one command")
                    } else if !model.rows.isEmpty {
                        // Selecting is how Folders gets a Trash command: the summary on the right has the Copy button.
                        Button("Select All \(model.rows.count)") { model.selection = Set(model.rows.filter { !$0.gone }.map(\.id)) }.controlSize(.small)
                            .help("Selects every folder shown. The panel on the right then copies one Move-to-Trash command for them (Shift-Command-C).")
                    }
                    orderMenu
                    Menu {
                        ForEach(others) { filter in
                            Button { model.locationFilter = filter } label: { if model.locationFilter == filter { Label(filter.rawValue, systemImage: "checkmark") } else { Text(filter.rawValue) } }
                        }
                    } label: { Text(others.contains(model.locationFilter) ? "Showing: " + model.locationFilter.rawValue : "More lists") }
                        .menuStyle(.borderlessButton).fixedSize().font(.caption)
                        .help("Growing, not scanned yet and review later")
                }
            }.padding(.horizontal, 16).padding(.bottom, 8)
        } else if model.section == .kept {
            keptBanner
        } else if !model.search.isEmpty {
            Text("\(model.rows.count) \(model.rows.count == 1 ? "match" : "matches") for “\(model.search)” in folder names, apps, projects and tags").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
        }
        if let summary = model.selectionSummary {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text("\(model.selection.count) selected · \(byteLabel(summary.bytes))").font(.callout.weight(.semibold)).monospacedDigit()
                Text(summary.unmeasured > 0 ? "folders inside others counted once · \(summary.unmeasured) not scanned" : "folders inside others counted once").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.selection.map { URL(fileURLWithPath: $0) }) }.controlSize(.small)
                Button("Clear") { model.selection = [] }.controlSize(.small)
            }.padding(.horizontal, 14).padding(.vertical, 8).background(Color.accentColor.opacity(0.10)).accessibilityElement(children: .contain).accessibilityLabel("\(model.selection.count) selected, \(byteLabel(summary.bytes))")
        }
    }
    /// How Folders are ordered. The default is biggest first.
    private var orderName: String {
        switch sortOrder.first?.keyPath {
        case \FolderRow.idleScore: return "Biggest unused first"
        case \FolderRow.bytes: return "Biggest first"
        case \FolderRow.unusedKey: return "Unused longest first"
        case \FolderRow.name: return "Name"
        default: return "Custom"
        }
    }
    private func orderButton(_ title: String, _ order: [KeyPathComparator<FolderRow>]) -> some View {
        Button { sortOrder = order } label: { if orderName == title { Label(title, systemImage: "checkmark") } else { Text(title) } }
    }
    var orderMenu: some View {
        Menu {
            orderButton("Biggest first", [KeyPathComparator(\FolderRow.bytes, order: .reverse)])
            orderButton("Biggest unused first", [KeyPathComparator(\FolderRow.idleScore, order: .reverse)])
            Section("Other orders") {
                orderButton("Unused longest first", [KeyPathComparator(\FolderRow.unusedKey)])
                orderButton("Name", [KeyPathComparator(\FolderRow.name)])
            }
        } label: { Label("Sort: " + orderName, systemImage: "arrow.up.arrow.down") }
            .menuStyle(.borderlessButton).fixedSize().font(.caption)
            .help("Biggest first by default. Biggest unused first weighs size by how long a folder has gone unused.")
    }
    /// The Ignored view: folders you keep out of suggestions, and folders you don't scan, with their share of the disk.
    var keptBanner: some View {
        let summary = model.keptSummary
        let total = Double(max(model.volume?.total ?? 1, 1))
        func share(_ bytes: Int64) -> String { (Double(bytes) / total).formatted(.percent.precision(.fractionLength(0...1))) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if !summary.kept.isEmpty {
                    VerdictTile(title: "Ignored, still scanned", value: byteLabel(summary.keptBytes), detail: "\(summary.kept.count) \(summary.kept.count == 1 ? "folder" : "folders") · \(share(summary.keptBytes)) of your disk", symbol: "hand.raised.fill", tint: .ignored, selected: false) {}
                        .allowsHitTesting(false)
                }
                if !summary.off.isEmpty {
                    let newest = summary.off.map(\.observedAt).max()
                    VerdictTile(title: "Scanning off", value: byteLabel(summary.offBytes), detail: "\(summary.off.count) \(summary.off.count == 1 ? "folder" : "folders") · \(share(summary.offBytes)) of your disk · " + (newest.map { "sizes from " + ageText($0) } ?? "sizes from before you turned it off"), symbol: "eye.slash", tint: .ignored, selected: false) {}
                        .allowsHitTesting(false)
                }
            }
            Text(summary.off.isEmpty
                 ? "Ignored folders are still scanned but never suggested. Select one and choose Stop Ignoring to get suggestions for it again."
                 : "Ignored: still scanned, never suggested. Scanning off: not read at all, so the size is the last one seen before you turned scanning off, and Context Cleaner can't tell what inside could go. Select one and choose Turn Scanning Back On to get answers for it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }
    @ViewBuilder var categoryBanner: some View {
        if let category = model.categoryFilter {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: category.symbol).font(.title2).foregroundStyle(category.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) { Text(category.displayName).font(.headline); Text(category.shortPurpose).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer(); Button("Show All Folders") { model.categoryFilter = nil }.controlSize(.small)
            }.padding(12).background(category.tint.opacity(0.08))
        }
    }
    func selectedRow(_ id: String) -> Bool { model.selection.contains(id) }
    func lastUsedText(_ row: FolderRow) -> String {
        if let date = row.advice.lastUsed { return ageText(date) }
        if row.measurement.scopeID == xcodeLiveScope { return "Never" }
        return row.measurement.state == .pending ? "—" : "Not recorded"
    }
    var folderTable: some View {
        Table(model.sortedRows(sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Folder", value: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Label { Text(row.name).lineLimit(1) } icon: { Image(systemName: row.measurement.profile.category.symbol).foregroundStyle(selectedRow(row.id) ? Color.white : row.measurement.profile.category.tint) }
                    Text([locationHint(row.id) ?? row.app, row.category, row.status].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.help(row.measurement.profile.path)
            }.width(min: 170, ideal: 240)
            TableColumn("Can I remove it?", value: \.verdictRank) { row in
                Group {
                    if row.gone { Text("Gone").font(.caption).foregroundStyle(.secondary) }
                    else if row.policy.excluded { Label("Scanning off", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                    else if row.policy.isKept { Label("Ignored", systemImage: "eye.slash.fill").font(.caption.weight(.semibold)).foregroundStyle(selectedRow(row.id) ? Color.white : Color.ignored) }
                    else if row.measurement.state == .pending { Text("Scan first").font(.caption).foregroundStyle(.secondary) }
                    else {
                        VStack(alignment: .leading, spacing: 2) {
                            VerdictBadge(verdict: row.advice.verdict, selected: selectedRow(row.id))
                            if !row.advice.short.isEmpty {
                                Text(row.advice.short).font(.caption).lineLimit(1)
                                    .foregroundStyle(selectedRow(row.id) ? Color.white.opacity(0.85) : row.advice.staleItems.isEmpty ? Color.secondary : Color.insideTint)
                            }
                        }
                    }
                }.help(row.advice.reason)
            }.width(min: 120, ideal: 140)
            TableColumn("Size", value: \.bytes) { row in
                Text(row.bytes >= 0 ? byteLabel(row.bytes) : "—").font(.callout).monospacedDigit().foregroundStyle(row.gone ? Color.secondary : Color.primary).strikethrough(row.gone)
            }.width(min: 80, ideal: 90)
            TableColumn("Last used", value: \.lastUsedKey) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastUsedText(row)).font(.callout)
                        .foregroundStyle(row.advice.lastUsed == nil ? Color.secondary : Color.primary)
                    // Only say where the size came from when it isn't today's scan.
                    if let source = sizeSourceText(row.measurement), source != "size from today" { Text(source).font(.caption).foregroundStyle(.secondary) }
                }
            }.width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if paths.count > 1 { SelectionActions(model: model, paths: Array(paths).sorted()) }
            else if let path = paths.first { LocationActions(model: model, path: path) }
        }
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView(model.section == .watching ? "Nothing on your watchlist" : "No matching folders", systemImage: model.section == .watching ? "eye" : "folder",
                    description: Text(model.section == .watching ? "Right-click any folder and choose Add to Watchlist. Folders that grow a lot are added for you." : "Try another filter, or scan to update the list."))
            }
        }
    }
    /// Folders a scan couldn't read, each with its reason and one fix.
    var issuesTable: some View {
        Table(model.sortedRows(sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Folder", value: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Label { Text(row.name).lineLimit(1) } icon: { Image(systemName: row.measurement.profile.category.symbol).foregroundStyle(selectedRow(row.id) ? Color.white : row.measurement.profile.category.tint) }.help(row.measurement.profile.path)
                    Text(row.app).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.width(min: 160, ideal: 210)
            TableColumn("Problem", value: \.status) { row in
                Label(row.measurement.problem, systemImage: row.measurement.state.problemSymbol).font(.callout).foregroundStyle(selectedRow(row.id) ? Color.white : Color.attention)
            }.width(min: 150, ideal: 190)
            TableColumn("Fix") { row in fixButton(row) }.width(min: 110, ideal: 130)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if paths.count > 1 { SelectionActions(model: model, paths: Array(paths).sorted()) }
            else if let path = paths.first { LocationActions(model: model, path: path) }
        }
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to fix", systemImage: "checkmark.circle")
                } description: {
                    Text("Every scanned folder was read completely. If macOS blocks a folder or one is too large, it shows up here with a fix. Folders you delete simply leave the lists.")
                }
            }
        }
    }
    @ViewBuilder func fixButton(_ row: FolderRow) -> some View {
        let path = row.id
        switch row.measurement.state {
        case .inaccessible where row.measurement.permissionDenied:
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.controlSize(.small).help("Check the folder's permissions with Get Info")
        case .inaccessible: Button("Allow Access…") { showingAccessHelp = true }.controlSize(.small)
        case .limited: Button("Scan Subfolders") { model.selected = path; model.inspector = "Contents"; model.inspectChildren(row.measurement) }.controlSize(.small).disabled(busy)
        case .missing: Button("Stop Checking") { model.policy(path) { $0.excluded = true } }.controlSize(.small).disabled(model.running || model.inspecting).help("Turns this folder off. You can turn it back on in Settings › Coverage.")
        default: Button("Try Again") { model.selected = path; model.scan(selectedOnly: true) }.controlSize(.small).disabled(busy)
        }
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let summary = model.selectionSummary {
                    Text("\(model.selection.count) folders selected").font(.headline)
                    Text(byteLabel(summary.bytes)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text(summary.unmeasured > 0 ? "Added together, counting folders inside others once. \(summary.unmeasured) not scanned yet." : "Added together, counting folders inside others once.").font(.caption).foregroundStyle(.secondary)
                    // The Trash command first, so it's in reach however many folders are selected.
                    let trash = model.trashable(Array(model.selection))
                    let withReview = model.trashable(Array(model.selection), includeReview: true)
                    let review = withReview.paths.count - trash.paths.count
                    TrashCopyButton(paths: trash.paths, prominent: true, shortcut: true)
                    Text(trash.skipped == 0 ? "One command for every folder selected."
                         : "For the \(trash.paths.count) Safe to remove and Rebuildable \(trash.paths.count == 1 ? "folder" : "folders"): nothing is lost." + (review > 0 ? "" : " Leaves out \(trash.skipped): folders inside others, and places you remove in their own apps."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if review > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            TrashCopyButton(paths: withReview.paths, label: "Copy Command Including Review First")
                            Text("Includes \(review) Review first \(review == 1 ? "folder" : "folders") too. Each may hold something that exists only there, such as files made by hand or a backup, so only include them once you've looked.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Verdict.check.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Divider()
                    let byCategory = Dictionary(grouping: summary.items.filter { $0.state == .measured }, by: { $0.profile.category })
                    ForEach(byCategory.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                        HStack { Circle().fill(category.tint).frame(width: 8, height: 8).accessibilityHidden(true); Text(category.displayName).font(.callout); Spacer(); Text("\(byCategory[category]!.count) · \(byteLabel(uniqueAllocatedTotal(byCategory[category]!)))").font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(summary.items.sorted { ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1) }.prefix(12), id: \.profile.path) { item in
                        HStack { Text(item.profile.displayName).font(.callout).lineLimit(1); Spacer(); Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit() }
                    }
                    if summary.items.count > 12 { Text("and \(summary.items.count - 12) more").font(.caption).foregroundStyle(.secondary) }
                    HStack { Button("Show All in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting(model.selection.map { URL(fileURLWithPath: $0) }) }; Menu("More") { SelectionActions(model: model, paths: Array(model.selection).sorted()) }.fixedSize() }
                } else if let item = model.chosen {
                    folderInspector(item)
                } else if model.running, let path = model.selected {
                    ProgressView()
                    Text("Scanning this folder…").font(.headline)
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    listSummary
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    /// With nothing selected, the inspector sums up the visible list.
    @ViewBuilder var listSummary: some View {
        let rows = model.rows
        let measured = rows.filter { $0.measurement.state == .measured }.map(\.measurement)
        let biggest = measured.max { ($0.allocatedBytes ?? 0) < ($1.allocatedBytes ?? 0) }
        let growers = rows.filter { ($0.change.delta ?? 0) > 0 }.sorted { ($0.change.delta ?? 0) > ($1.change.delta ?? 0) }.prefix(3)
        let pending = rows.filter { $0.measurement.state == .pending }.count
        let title = model.section == .locations ? (model.categoryFilter?.displayName ?? (model.locationFilter == .all ? "All folders" : model.locationFilter.rawValue)) : model.section.rawValue
        Text(title).font(.headline)
        if model.section == .needsAttention && rows.isEmpty {
            Text("Folders that haven't been scanned yet aren't problems. They're listed in Folders.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Show Folders Not Scanned Yet") { model.section = .locations; model.locationFilter = .unscanned }.controlSize(.small)
        } else if model.section == .needsAttention {
            Text("\(rows.count) \(rows.count == 1 ? "folder" : "folders") couldn't be read").font(.title2.weight(.semibold))
            Text("Each row says why and offers one fix. Nothing is changed until you choose it.").font(.callout).foregroundStyle(.secondary)
        } else {
            Text(byteLabel(uniqueAllocatedTotal(measured))).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(model.section == .kept ? "in \(model.keptSummary.kept.count + model.keptSummary.off.count) \(model.keptSummary.kept.count + model.keptSummary.off.count == 1 ? "folder" : "folders") you set aside, last known sizes" : "in \(measured.count) scanned \(measured.count == 1 ? "folder" : "folders")\(pending > 0 ? " · \(pending) not scanned yet" : "")").font(.callout).foregroundStyle(.secondary)
            if let biggest, let bytes = biggest.allocatedBytes {
                Divider()
                Text("Biggest").font(.headline)
                summaryRow(biggest.profile, value: byteLabel(bytes), tint: .secondary)
            }
            if !growers.isEmpty {
                Text("Grew since the scan before").font(.headline)
                ForEach(Array(growers), id: \.id) { row in summaryRow(row.measurement.profile, value: signedBytes(row.change.delta ?? 0), tint: .growing) }
            }
        }
        if !rows.isEmpty && model.section != .needsAttention {
            Divider()
            Text("Select a folder to see what it is. ⌘-click or ⇧-click several to add their sizes.").font(.caption).foregroundStyle(.secondary)
        }
    }
    func summaryRow(_ profile: FolderProfile, value: String, tint: Color) -> some View {
        Button { model.selected = profile.path } label: {
            HStack(spacing: 8) {
                Image(systemName: profile.category.symbol).foregroundStyle(profile.category.tint).frame(width: 18).accessibilityHidden(true)
                Text(profile.displayName).lineLimit(1)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(tint)
            }.font(.callout).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// Size, owner and one sentence first. Contents and evidence stay folded until asked for.
    @ViewBuilder func folderInspector(_ item: FolderMeasurement) -> some View {
        let path = item.profile.path
        let policy = model.preferences.policy(path)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.profile.category.symbol).font(.title2).foregroundStyle(item.profile.category.tint).frame(width: 42, height: 42).background(item.profile.category.tint.opacity(0.12), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.profile.displayName).font(.headline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text((locationHint(item.profile.path) ?? item.profile.project ?? item.profile.associatedApp) + " · " + item.profile.category.displayName).font(.caption).foregroundStyle(.secondary).help(item.profile.path)
            }
        }
        // Exactly which folder this is, and the way back up.
        VStack(alignment: .leading, spacing: 4) {
            Text(abbreviatedPath(path)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.head).textSelection(.enabled).help(path)
            if let parent = model.knownParent(of: path) {
                Button { model.selected = parent } label: { Label("Up to " + model.displayName(parent), systemImage: "arrow.turn.left.up").lineLimit(1) }
                    .buttonStyle(.link).font(.caption).help(parent)
            }
        }
        HStack(alignment: .firstTextBaseline) {
            Text(item.state == .pending ? "Not scanned" : item.allocatedBytes.map(byteLabel) ?? "Size unknown").font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer()
            Button { model.policy(path) { $0.isWatched.toggle() } } label: { Label(policy.isWatched ? "Watching" : "Watch", systemImage: policy.isWatched ? "eye.fill" : "eye") }
                .help(policy.isWatched ? "Remove from your watchlist" : "Add to your watchlist; scheduled checks look at it first")
            Button { model.policy(path) { $0.isKept.toggle() } } label: { Label(policy.isKept ? "Ignored" : "Ignore", systemImage: policy.isKept ? "eye.slash.fill" : "eye.slash") }
                .help(policy.isKept ? "Stop ignoring: suggest it again when it looks safe to remove" : "Ignore this folder: it's still scanned but never suggested, and it moves to Ignored")
            Menu { LocationActions(model: model, path: path) } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More actions for this folder")
        }
        (Text("What it is: ").fontWeight(.semibold) + Text(item.profile.path.contains("/.codex/scratch/") ? "Scratch space a Codex task used for builds, test copies and downloads. Codex doesn't remove it when the task ends." : item.profile.category.shortPurpose)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        let simulatorRoot = path.hasSuffix("/CoreSimulator/Devices")
        if model.gone.contains(path) {
            Label("This folder is gone now. Scan again to update the list.", systemImage: "questionmark.folder").font(.callout).foregroundStyle(.secondary)
        } else if item.state == .measured || simulatorRoot || SimulatorLocations.deviceRoot(path) != nil {
            VerdictCard(advice: model.adviceFor(item), sizeSource: sizeSourceText(item), neverUsed: item.scopeID == xcodeLiveScope,
                        trashPath: model.mayTrashWhole(item) ? path : nil)
        }
        if simulatorRoot { simulatorDeviceList() }
        if policy.excluded {
            VStack(alignment: .leading, spacing: 8) {
                Label("Scanning off", systemImage: "eye.slash").font(.headline).foregroundStyle(Color.ignored)
                Text("You turned scanning off for this folder, so Context Cleaner doesn't read it. " + (item.state == .measured ? "Its size is from \(ageText(item.observedAt)), before that. " : "") + "It can't tell what inside could go until it's scanned again.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Turn Scanning Back On", systemImage: "eye") { model.policy(path) { $0.excluded = false }; model.scan(selectedOnly: true) }
                    .disabled(busy).help("Turns scanning back on for this folder and scans it now. It only reads sizes.")
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.ignored.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        InsideBreakdown(model: model, item: item)
        if item.state != .measured && item.state != .pending {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.state.problemSymbol).foregroundStyle(Color.attention).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.problem).font(.headline)
                    Text(item.state == .limited ? "It holds too much to read in the allowed time. Scan its subfolders instead." : item.state == .missing ? "It may have been moved or removed since it was found." : item.permissionDenied ? "Its file permissions don't let you read it. Get Info in Finder shows who can." : item.state == .inaccessible ? "macOS didn't allow Context Cleaner to read it." : "No complete size was saved. Earlier sizes are kept.").font(.callout).foregroundStyle(.secondary)
                    if item.state == .inaccessible && !item.permissionDenied { Button("Allow Access…") { showingAccessHelp = true }.controlSize(.small) }
                    if item.state == .limited { Button("Scan Subfolders") { model.inspector = "Contents"; model.inspectChildren(item) }.controlSize(.small).disabled(busy) }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.attention.opacity(0.08))
        }
        if item.state != .pending { FolderTrend(points: model.history(path), change: model.growthSummary(path)).id(path) }
        if policy.autoWatched == true {
            HStack(spacing: 10) {
                CapsuleLabel(text: "Watched for you" + (policy.autoWatchedBytes.map { " · grew \(byteLabel($0))" } ?? ""), symbol: "eye", color: .growing)
                Button("Undo") { model.undoAutoWatch(path) }.controlSize(.small)
            }
        }
        if policy.expected { CapsuleLabel(text: "Growth is expected", symbol: "checkmark.circle", color: .stable) }
        if !policy.tags.isEmpty || !policy.note.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !policy.tags.isEmpty { Text(policy.tags.map { "#" + $0 }.joined(separator: "  ")).font(.callout).foregroundStyle(Color.accentColor) }
                if !policy.note.isEmpty { Text(policy.note).font(.callout).textSelection(.enabled) }
            }
        }
        HStack {
            Button("Scan Folder", systemImage: "magnifyingglass") { model.scan(selectedOnly: true) }
                .buttonStyle(.borderedProminent).disabled(!model.canRescanSelection).help("Scan only this folder. Nothing is changed.")
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
        Divider()
        DisclosureGroup("What's inside", isExpanded: $showInside) { if showInside { contents(item).padding(.top, 8) } }.font(.headline)
        DisclosureGroup("Details", isExpanded: $showDetails) { if showDetails { details(item).padding(.top, 8) } }.font(.headline)
        Text("Context Cleaner never deletes files. You choose what goes to the Trash.").font(.caption).foregroundStyle(.secondary)
    }
    /// Every simulator Xcode knows, with current size, last use and a verdict. Read from Xcode, so it's never stale.
    @ViewBuilder func simulatorDeviceList() -> some View {
        let devices = model.simDevices.values.sorted { ($0.dataBytes ?? 0) > ($1.dataBytes ?? 0) }
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Test devices, from Xcode").font(.headline)
                ForEach(devices, id: \.udid) { device in
                    let verdict = model.deviceAdvice(device)
                    HStack(spacing: 8) {
                        Image(systemName: verdict.verdict.symbol).foregroundStyle(verdict.verdict.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name).font(.callout).lineLimit(1)
                            Text("\(device.runtime) · \(device.lastUsed.map { "used " + ageText($0) } ?? "never used")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(device.dataBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                    .help(verdict.verdict.title + ". " + verdict.reason)
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        Button("Copy Remove Command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("xcrun simctl delete \(device.udid)", forType: .string) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.home + "/Library/Developer/CoreSimulator/Devices/" + device.udid)]) }
                    }
                }
                Text("Current sizes and last use, straight from Xcode. Remove devices in Xcode › Window › Devices and Simulators.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// Evidence, path, handles and every saved size. Folded by default.
    func details(_ item: FolderMeasurement) -> some View {
        let points = model.history(item.profile.path).filter { $0.state != .cancelled }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("About this folder").font(.headline)
                Text(item.profile.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Before you remove anything: " + item.profile.consequence).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Where it is").font(.headline)
                Text(item.profile.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if item.fileCount > 0 { Text("\(item.fileCount.formatted()) files" + (item.latestModifiedAt.map { " · last changed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")).font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("How we know").font(.headline)
                Text("A known location suggests who uses a folder. It doesn't prove which app wrote to it.").font(.caption).foregroundStyle(.secondary)
                ForEach(item.profile.evidence) { e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.label).font(.callout.weight(.medium))
                        Spacer()
                        Text(e.level.rawValue).font(.caption).foregroundStyle(e.level == .observed ? Color.accentColor : .secondary)
                    }
                    Text(e.value).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3).help(e.source)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps using it at scan time").font(.headline)
                if !item.activityCheckAvailable { Text("Not checked in this scan.").font(.callout).foregroundStyle(.secondary) }
                else if item.processes.isEmpty { Text("None seen when the scan started. That doesn't prove it's unused.").font(.callout).foregroundStyle(.secondary) }
                ForEach(Array(Set(item.processes.map(\.command))).sorted().prefix(8), id: \.self) { Text($0).font(.callout) }
            }
            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Every saved size").font(.headline)
                    ForEach(points.reversed().prefix(12)) { point in
                        HStack { Text(point.date.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(point.bytes.map(byteLabel) ?? point.state.problem).monospacedDigit() }.font(.caption)
                    }
                    if points.count > 12 { Text("and \(points.count - 12) earlier").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let diagnostic = item.diagnostic, item.state != .pending {
                DisclosureGroup("Technical note") { Text(diagnostic).font(.caption).textSelection(.enabled) }.font(.callout)
            }
        }
    }
    func contents(_ item: FolderMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.profile.path.hasSuffix("/CoreSimulator/Devices") {
                Panel(title: "Your virtual test devices", symbol: "iphone", tint: .purple) {
                    Text("Each device has its own apps and data. Read the device names first, then choose one to measure.").font(.callout)
                    Button(model.identifyingDevices ? "Reading device names…" : "Identify simulator devices", systemImage: "list.bullet") { model.identifySimulatorDevices(item) }.disabled(model.identifyingDevices || model.preferences.excluded(item.profile.path))
                    if model.simulatorDeviceParent == item.profile.path {
                        Text("\(model.simulatorDevices.count) included devices · names from local metadata").font(.caption).foregroundStyle(.secondary)
                        TextField("Find a device or runtime", text: $simulatorSearch).textFieldStyle(.roundedBorder)
                        ForEach(model.simulatorDevices.filter { simulatorSearch.isEmpty || ($0.name + $0.evidence.map(\.value).joined()).localizedCaseInsensitiveContains(simulatorSearch) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { device in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(device.name).fontWeight(.medium)
                                    Spacer()
                                    Button("Measure") { model.selected = device.path; model.scan(selectedOnly: true) }.disabled(model.running || model.inspecting)
                                }
                                if let runtime = device.evidence.first(where: { $0.label == "Runtime" }) { Text(runtime.value.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")).font(.caption).foregroundStyle(.secondary) }
                                if let saved = model.latest.first(where: { $0.profile.path == device.path && $0.state == .measured }), let bytes = saved.allocatedBytes {
                                    Text("\(byteLabel(bytes)) · measured \(saved.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                } else { Text("Not scanned yet").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 5)
                        }
                        if !model.identifyingDevices && model.simulatorDevices.isEmpty { Text("No included device metadata was found.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let detail = item.contents {
                SnapshotContentsView(detail: detail, tint: item.profile.category.tint, busy: model.running || model.inspecting || model.discovering) { child in
                    model.selected = (item.profile.path == "/" ? "" : item.profile.path) + "/" + child.name
                    model.scan(selectedOnly: true)
                }.id(item.profile.path)
            } else { Text("Scan this folder to see what's inside it.").font(.callout).foregroundStyle(.secondary) }
            Divider()
            if let events = childChanges(item.profile.path, records: model.records) {
                ChildEventsView(events: events).id(item.profile.path)
            }
            Divider()
            Text("Go deeper").font(.headline)
            if model.inspecting { ProgressView(); Text("Scanning each item inside…").font(.caption); Button("Stop") { model.inspectionCancellation.cancel() } }
            else {
                Button("Scan Each Item Inside") { model.inspectChildren(item) }.disabled(model.running || model.preferences.excluded(item.profile.path))
                if SimulatorLocations.deviceRoot(item.profile.path) != nil {
                    Button("Scan This Device's Apps") { model.inspectChildren(item, simulatorApps: true) }.disabled(model.running || model.preferences.excluded(item.profile.path))
                    Text("Sizes each app and its data on this test device. It can't tell which saves still matter.").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach((model.childrenParent == item.profile.path ? model.children : []).sorted { ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1) }) { child in
                HStack {
                    Button { model.selected = child.profile.path; model.inspector = "Overview" } label: { Text(child.profile.category == .simulator ? child.profile.name : URL(fileURLWithPath: child.profile.path).lastPathComponent).lineLimit(3) }.buttonStyle(.link)
                    Spacer(); Text(child.allocatedBytes.map(byteLabel) ?? child.state.rawValue).font(.caption).monospacedDigit()
                }
            }
        }
    }
    /// What you cleaned up, and what each scan found.
    var history: some View {
        VStack(spacing: 0) {
            HistorySummary(model: model).padding(.horizontal, 22).padding(.bottom, 4)
            Picker("History", selection: $historyTab) { Text("Cleanups").tag(0); Text("Scans").tag(1) }
                .pickerStyle(.segmented).labelsHidden().fixedSize().padding(.vertical, 8)
            if historyTab == 0 { cleanupHistory } else { scanHistory }
        }
    }
    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        return calendar.isDateInToday(day) ? "Today" : calendar.isDateInYesterday(day) ? "Yesterday" : day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    /// Every Move-to-Trash command you copied, newest first: what was moved, what wasn't, and what was left out and why.
    var cleanupHistory: some View {
        // Copies that left everything out (it was all gone or changed) moved nothing; they're folded into one line.
        let empty = model.cleanups.filter { $0.items.count == $0.count(.leftOut) }
        let list = showEmptyCleanups ? model.cleanups : model.cleanups.filter { $0.items.count > $0.count(.leftOut) }
        let calendar = Calendar.current
        let days = Dictionary(grouping: list, by: { calendar.startOfDay(for: $0.copiedAt) }).sorted { $0.key > $1.key }
        return List {
            ForEach(days, id: \.key) { day, items in
                Section(dayTitle(day)) { ForEach(items) { cleanupRow($0) } }
            }
            if !empty.isEmpty {
                Button(showEmptyCleanups ? "Hide the \(empty.count) copies that moved nothing" : "\(empty.count) more \(empty.count == 1 ? "copy" : "copies") moved nothing: everything in them was already gone or had changed. Show them") { showEmptyCleanups.toggle() }
                    .buttonStyle(.link).font(.callout)
            }
        }.overlay { if list.isEmpty { ContentUnavailableView("No cleanups yet", systemImage: "trash", description: Text("When you copy a Move-to-Trash command, it shows up here: what was moved, what wasn't, and anything left out.")) } }
    }
    func cleanupRow(_ cleanup: Cleanup) -> some View {
        let inCommand = cleanup.items.count - cleanup.count(.leftOut)
        let moved = cleanup.count(.moved)
        let open = Date().timeIntervalSince(cleanup.copiedAt) < 1800
        let headline = inCommand == 0 ? "Nothing copied" : moved == inCommand ? "Moved \(moved == 1 ? "1 item" : "all \(moved)") to the Trash" : "Moved \(moved) of \(inCommand) to the Trash"
        var notes: [String] = []
        if moved < inCommand { notes.append(open ? "\(inCommand - moved) waiting for the command" : "\(inCommand - moved) still in place") }
        if cleanup.count(.leftOut) > 0 { notes.append("\(cleanup.count(.leftOut)) left out when rechecked") }
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(cleanup.items, id: \.path) { item in
                    let status = cleanupStatus(item, open: open)
                    HStack(spacing: 8) {
                        Image(systemName: status.symbol).foregroundStyle(status.tint).frame(width: 16).accessibilityHidden(true)
                        Text(model.displayName(item.path)).lineLimit(1).truncationMode(.middle)
                        if let hint = locationHint(item.path) { Text(hint).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        Spacer(minLength: 8)
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                        Text(byteLabel(item.bytes)).monospacedDigit().frame(minWidth: 80, alignment: .trailing)
                    }.font(.callout).frame(maxWidth: 820, alignment: .leading).help(item.path)
                }
            }.padding(.vertical, 6).padding(.leading, 26)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: inCommand > 0 && moved == inCommand ? "checkmark.circle" : moved > 0 ? "circle.lefthalf.filled" : "circle.dashed")
                    .foregroundStyle(inCommand > 0 && moved == inCommand ? Color.stable : Color.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline)
                    if !notes.isEmpty { Text(notes.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                if moved > 0 { Text(byteLabel(cleanup.bytes(.moved))).font(.callout).monospacedDigit().foregroundStyle(Color.stable) }
                Text(cleanup.copiedAt.formatted(date: .omitted, time: .shortened)).font(.callout).foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
            }.padding(.vertical, 4)
        }
    }
    private func cleanupStatus(_ item: Cleanup.Item, open: Bool) -> (text: String, symbol: String, tint: Color) {
        switch item.status {
        case .moved: return ("Moved to the Trash", "checkmark.circle.fill", .stable)
        case .notMoved: return ("Still in place", "circle", .caution)
        case .leftOut: return ("Left out: " + (item.note ?? "rechecked").lowercased(), "minus.circle", .secondary)
        case .waiting: return open ? ("Waiting for the command", "clock", .secondary) : ("Not confirmed", "questionmark.circle", .secondary)
        }
    }
    /// Saved scans grouped by day, newest first. Each row names what was scanned and the result.
    var scanHistory: some View {
        let records = model.records.sorted { $0.finishedAt > $1.finishedAt }
        let calendar = Calendar.current
        let days = Dictionary(grouping: records.indices, by: { calendar.startOfDay(for: records[$0].finishedAt) }).sorted { $0.key > $1.key }
        return List {
            ForEach(days, id: \.key) { day, indices in
                Section(calendar.isDateInToday(day) ? "Today" : calendar.isDateInYesterday(day) ? "Yesterday" : day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                    ForEach(indices, id: \.self) { index in historyRow(records, index) }
                }
            }
        }.overlay { if records.isEmpty { ContentUnavailableView("No scans yet", systemImage: "clock", description: Text("Choose Scan Folders… to take your first look. Each scan shows up here.")) } }
    }
    func historyRow(_ records: [ScanRecord], _ index: Int) -> some View {
        let record = records[index]
        let previous = records.dropFirst(index + 1).first { $0.scope == record.scope && $0.complete }
        let changes = scanDelta(record, previous: previous)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                let unreadable = record.measurements.filter { [.inaccessible, .limited, .failed].contains($0.state) }
                if let changes {
                    let grew = changes.grew.reduce(Int64(0)) { $0 + $1.delta }, shrank = changes.shrank.reduce(Int64(0)) { $0 + $1.delta }
                    Text(grew + shrank == 0 ? "No change from the scan before." : "\(signedBytes(grew + shrank)) since the scan before: \(changes.grew.count) grew, \(changes.shrank.count) shrank, the rest unchanged.")
                        .font(.callout)
                    if !changes.grew.isEmpty { historyChanges("Grew most", changes.grew.prefix(6).map { ($0.path, $0.delta) }, tint: .growing) }
                    if !changes.shrank.isEmpty { historyChanges("Shrank most", changes.shrank.prefix(4).map { ($0.path, $0.delta) }, tint: .stable) }
                } else {
                    Text("The first scan of these places. Biggest folders it found:").font(.callout)
                    let biggest = record.measurements.filter { $0.state == .measured }.sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }.prefix(5)
                    historyChanges(nil, biggest.map { ($0.profile.path, $0.allocatedBytes ?? 0) }, tint: .secondary, signed: false)
                }
                if !unreadable.isEmpty {
                    Label("\(unreadable.count) couldn't be read: " + unreadable.prefix(3).map(\.profile.displayName).joined(separator: ", ") + (unreadable.count > 3 ? "…" : ""), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Color.attention)
                }
                Text([record.freeBytes.map { byteLabel($0) + " free on disk at the time" }, "took " + elapsedLabel(record.finishedAt.timeIntervalSince(record.startedAt))].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6).padding(.leading, 26)
        } label: {
            HStack(spacing: 12) {
                let problem = !record.wasStopped && record.measurements.contains { [.inaccessible, .limited, .failed].contains($0.state) }
                Image(systemName: record.wasStopped ? "stop.circle" : problem ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(record.wasStopped ? Color.caution : problem ? Color.attention : Color.accentColor).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.folderSummary).font(.headline).lineLimit(1)
                    Text(record.resultSummary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let changes {
                    let net = changes.grew.reduce(Int64(0)) { $0 + $1.delta } + changes.shrank.reduce(Int64(0)) { $0 + $1.delta }
                    if net != 0 { Text(signedBytes(net)).font(.callout).monospacedDigit().foregroundStyle(net > 0 ? Color.growing : .stable) }
                }
                Text(record.finishedAt.formatted(date: .omitted, time: .shortened)).font(.callout).foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
            }.padding(.vertical, 4)
        }
    }
    /// A few folders with their change (or size), each one click from its card.
    func historyChanges(_ title: String?, _ items: [(String, Int64)], tint: Color, signed: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            ForEach(items, id: \.0) { path, bytes in
                Button { model.open(path) } label: {
                    HStack(spacing: 8) {
                        Text(model.displayName(path)).lineLimit(1)
                        if let hint = locationHint(path) { Text(hint).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        Spacer(minLength: 8)
                        Text(signed ? signedBytes(bytes) : byteLabel(bytes)).monospacedDigit().foregroundStyle(tint)
                    }.font(.callout).frame(maxWidth: 560, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(path)
            }
        }
    }
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let error = model.error { Text(error).font(.caption).foregroundStyle(Color.attention).textSelection(.enabled).lineLimit(3) }
            if let watch = model.trashWatch, !model.trashWatchHidden, model.section != .freeUp { TrashWatchLine(model: model, watch: watch) }
            HStack(spacing: 6) {
                Text(model.preferences.effectiveSchedule == "off" ? "Scheduled checks are off." : model.preferences.effectiveSchedule == "daily" ? "Checking watched and growing folders daily while open." : "Checking watched and growing folders weekly while open.").font(.caption).foregroundStyle(.secondary)
                SettingsLink { Text("Change…").font(.caption) }.buttonStyle(.link)
                Spacer()
                Text("\(model.discovery.profiles.count) folders known · \(model.records.count) scans saved").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16).padding(.bottom, 10)
    }
}
struct EditTarget: Identifiable { var id: String }
/// The About panel: what Context Cleaner is, what it never does, and where to find more.
func showAboutPanel() {
    let body = NSMutableAttributedString()
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.paragraphSpacing = 6
    func add(_ text: String, size: CGFloat = 11, color: NSColor = .labelColor, link: String? = nil) {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph]
        if let link, let url = URL(string: link) { attributes[.link] = url }
        body.append(NSAttributedString(string: text, attributes: attributes))
    }
    add("Finds the build output, caches, Codex worktrees and scratch folders filling your Mac, says what each one is and whether you'll miss it, and copies one Terminal command that moves what you pick to the Trash.\n")
    add("It never deletes anything itself. No network, no accounts, no analytics.\n", color: .secondaryLabelColor)
    add("GitHub", link: "https://github.com/chrissotraidis/contextcleaner"); add("  ·  ")
    add("What's new", link: "https://github.com/chrissotraidis/contextcleaner/blob/main/docs/CHANGELOG.md"); add("  ·  ")
    add("Report a problem", link: "https://github.com/chrissotraidis/contextcleaner/issues/new/choose")
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: body])
}
/// History at a glance: what you've moved to the Trash, day by day, how many cleanups and scans, and the Trash itself.
struct HistorySummary: View {
    @ObservedObject var model: CleanerModel
    private struct Day: Identifiable { let day: Date; let bytes: Int64; var id: Date { day } }
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let cleanups = model.cleanups
        let moved = Dictionary(grouping: cleanups.filter { $0.copiedAt >= start }, by: { calendar.startOfDay(for: $0.copiedAt) }).mapValues { $0.reduce(Int64(0)) { $0 + $1.bytes(.moved) } }
        let days = (0..<30).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { Day(day: $0, bytes: moved[$0] ?? 0) }
        let week = cleanups.filter { Date().timeIntervalSince($0.copiedAt) < 7 * 86400 }
        let allBytes = cleanups.reduce(Int64(0)) { $0 + $1.bytes(.moved) }
        let monthBytes = days.reduce(Int64(0)) { $0 + $1.bytes }
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                stat("Moved to the Trash, last 7 days", byteLabel(week.reduce(Int64(0)) { $0 + $1.bytes(.moved) }), "\(week.reduce(0) { $0 + $1.count(.moved) }) items")
                stat("All time", byteLabel(allBytes), "\(cleanups.filter { $0.count(.moved) > 0 }.count) cleanups · \(model.records.count) scans")
                HStack(spacing: 6) {
                    Image(systemName: "trash").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(model.trashBytes.map { "The Trash holds \(byteLabel($0))" } ?? "Space comes back when you empty the Trash").monospacedDigit()
                    Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: homeDirectory + "/.Trash")) }.buttonStyle(.link)
                }.font(.caption).foregroundStyle(.secondary)
            }.frame(width: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Moved to the Trash each day · \(byteLabel(monthBytes)) in 30 days").font(.caption).foregroundStyle(.secondary)
                Chart(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Moved", Double(day.bytes) / 1_073_741_824))
                        .foregroundStyle(Color.stable.gradient)
                        .accessibilityLabel(day.day.formatted(.dateTime.month().day()))
                        .accessibilityValue(byteLabel(day.bytes))
                }
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let gib = value.as(Double.self) { Text(byteLabel(Int64(gib * 1_073_741_824))) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 110)
            }.frame(maxWidth: .infinity)
        }.padding(14).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
    private func stat(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
/// What's inside a folder only its app understands, such as a virtual machine or Ollama's models, with a command for each
/// part that has a safe one. Read when the folder is shown; metadata and small manifests only.
struct InsideBreakdown: View {
    @ObservedObject var model: CleanerModel
    let item: FolderMeasurement
    @State private var parts: [InsidePart] = []
    @State private var copied: String?
    var body: some View {
        let path = item.profile.path
        // Always a view, even before the parts are read: an empty Group never starts its task.
        VStack(alignment: .leading, spacing: 0) {
            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inside it").font(.headline)
                    ForEach(parts) { part in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text(part.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text(byteLabel(part.bytes)).font(.callout).monospacedDigit()
                            if let command = part.command {
                                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string); copied = part.id } label: {
                                    Image(systemName: copied == part.id ? "checkmark" : "doc.on.clipboard")
                                }.buttonStyle(.borderless).help("Copy: " + command + ". Paste it in Terminal to remove just this model.").accessibilityLabel("Copy remove command for " + part.name)
                            }
                        }
                    }
                    if parts.contains(where: { $0.command != nil }) {
                        Text("Each copy button copies the command that removes just that model, for example \(parts.first(where: { $0.command != nil })?.command ?? ""). Download it again any time.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            } else { Color.clear.frame(height: 0) }
        }
        .task(id: path) {
            copied = nil
            parts = await Task.detached(priority: .utility) { insideParts(path) }.value
        }
    }
}
struct PolicyEditor: View {
    let path: String
    @State var value: LocationPolicy
    @State var tags: String
    @State var threshold: String
    let save: (LocationPolicy) -> Void
    @Environment(\.dismiss) var dismiss
    init(path: String, initial: LocationPolicy, save: @escaping (LocationPolicy) -> Void) {
        self.path = path; _value = State(initialValue: initial); _tags = State(initialValue: initial.tags.joined(separator: ", "))
        _threshold = State(initialValue: initial.growthThresholdBytes.map { String(Double($0) / 1_073_741_824) } ?? ""); self.save = save
    }
    var validThreshold: Bool {
        if threshold.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        guard let amount = Double(threshold) else { return false }
        return amount.isFinite && amount >= 0 && amount < 1_000_000
    }
    var body: some View {
        Form {
            Text("Tags and notes").font(.title2.weight(.semibold))
            Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Toggle("On my watchlist", isOn: $value.isWatched)
            Toggle("This growth is expected", isOn: $value.expected)
            Toggle("Remind me later", isOn: Binding(get: { value.reviewAfter != nil }, set: { value.reviewAfter = $0 ? Date().addingTimeInterval(86400) : nil }))
            if value.reviewAfter != nil {
                DatePicker("Remind me after", selection: Binding(get: { value.reviewAfter ?? Date() }, set: { value.reviewAfter = $0 }), displayedComponents: [.date, .hourAndMinute])
                Text("Until then it's left out of Growing and scheduled checks. You can still scan it.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Tags, separated by commas", text: $tags)
            TextField("Only flag growth above (GiB)", text: $threshold)
            if !validThreshold { Text("Enter a number of GiB, or leave it blank.").font(.caption).foregroundStyle(Color.attention) }
            TextField("Notes", text: $value.note, axis: .vertical).lineLimit(3...6)
            Text("Tags and notes are for you. Context Cleaner never deletes files.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") {
                value.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                value.growthThresholdBytes = Double(threshold).flatMap { $0.isFinite && $0 >= 0 && $0 < 1_000_000 ? Int64($0 * 1_073_741_824) : nil }
                save(value)
            }.buttonStyle(.borderedProminent).disabled(!validThreshold) }
        }.padding(24).frame(width: 500)
    }
}
@main struct ContextCleanerApp: App {
    @StateObject private var model = CleanerModel()
    init() { keepReadsLocal() }
    var body: some Scene {
        WindowGroup("Context Cleaner") { MainView(model: model) }.defaultSize(width: 1480, height: 920)
            .commands {
                CommandGroup(replacing: .appInfo) { Button("About Context Cleaner") { showAboutPanel() } }
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .importExport) {
                    Button("Add Folder to Scan…") { model.addRoot() }.keyboardShortcut("o", modifiers: [.command, .shift])
                    Button("Export Cleanup List…") { model.exportReport() }.keyboardShortcut("e", modifiers: [.command, .shift])
                }
                CommandGroup(after: .sidebar) {
                    Picker("Appearance", selection: Binding(get: { model.preferences.appearance ?? "System" }, set: { model.setAppearance($0) })) {
                        Text("Match System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
                    }
                    Button(model.effectiveDarkAppearance ? "Use Light Appearance" : "Use Dark Appearance") { model.toggleAppearance() }
                        .keyboardShortcut("l", modifiers: [.command, .shift])
                }
                CommandMenu("Scan") {
                    Button("Scan Folders…") { model.showingScanPlan = true }.keyboardShortcut("r").disabled(model.running || model.inspecting || model.discovering)
                    Button("Scan This Folder") { model.scan(selectedOnly: true) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!model.canRescanSelection)
                    Button("Scan Watchlist") { model.scan(watchedOnly: true) }.disabled(model.running || model.inspecting || model.discovering)
                    Button("Look for New Folders") { model.discover() }.disabled(model.running || model.inspecting || model.discovering)
                    Divider()
                    Button("Stop Scan") { model.cancelWork() }.keyboardShortcut(".").disabled(!(model.running || model.discovering))
                }
                CommandMenu("Folder") {
                    if model.selection.count > 1 {
                        SelectionActions(model: model, paths: Array(model.selection).sorted())
                    } else if let path = model.selected {
                        LocationActions(model: model, path: path)
                    } else {
                        Text("Select a folder first")
                    }
                    Divider()
                    Button("Tags & Notes…") { if let path = model.selected { model.editing = path } }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.selection.count != 1)
                }
            }
        Settings { SettingsView(model: model) }
    }
}

struct AccessHelp: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Let Context Cleaner read a blocked folder", systemImage: "lock.open").font(.title2.weight(.semibold))
            Text("macOS protects some folders. To let Context Cleaner read their sizes:").font(.callout)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open Privacy & Security › Full Disk Access.")
                Text("2. Turn on Context Cleaner. If it isn't listed, add it with the + button.")
                Text("3. Quit and reopen Context Cleaner, then scan the folder again.")
            }.font(.callout)
            Text("This is your choice. You can also turn the folder off instead. Context Cleaner never changes permissions itself.").font(.caption).foregroundStyle(.secondary)
            Text("Each new test build may need to be allowed again.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show This App in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Spacer()
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540)
    }
}

struct ReportPreview: View {
    @ObservedObject var model: CleanerModel
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export cleanup list").font(.title2.weight(.semibold))
            Text("A checklist of what you can remove, biggest first: safe folders, old items inside folders, rebuildable folders, and folders to review first, each with its path and how to remove it yourself. It's a Markdown file you can keep, print or share. It stays on your Mac unless you share it.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let excerpt = text.count > 6000 ? String(text.prefix(6000)) + "\n\n… preview shortened. The saved file has the whole list." : text
            ScrollView { Text(excerpt).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                .background(.background.secondary)
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                Button("Cancel") { model.reportPreview = nil }.keyboardShortcut(.cancelAction)
                Button("Save…") { model.saveReport(text) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 720, height: 560)
    }
}

/// After you copy a Move-to-Trash command: what's still waiting, and what has left its place.
struct TrashWatchLine: View {
    @ObservedObject var model: CleanerModel
    let watch: CleanerModel.TrashWatch
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(message).font(.callout).lineLimit(2)
            Spacer()
            if watch.done { Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: homeDirectory + "/.Trash")) }.controlSize(.small) }
            else if !watch.paths.isEmpty && watch.moved.isEmpty && !watch.expired {
                // Opens Terminal only. You paste and run the command yourself.
                Button("Open Terminal") {
                    if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") { NSWorkspace.shared.open(terminal) }
                }.controlSize(.small).help("Opens Terminal. Paste with ⌘V and press Return.")
            }
            Button { model.dismissTrashWatch() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Dismiss").accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .help(itemList)
    }
    private var symbol: String { watch.done ? "checkmark.circle.fill" : watch.paths.isEmpty ? "exclamationmark.circle" : "doc.on.clipboard" }
    private var tint: Color { watch.done ? Color.stable : watch.paths.isEmpty ? Color.caution : Color.accentColor }
    private var message: String {
        let total = watch.paths.count
        let left = watch.leftOut.isEmpty ? "" : " " + leftOutText
        if total == 0 && !watch.leftOut.isEmpty && watch.leftOut.values.allSatisfy({ $0 == .gone }) {
            return "Nothing to copy: \(watch.leftOut.count == 1 ? "it was" : "all \(watch.leftOut.count) were") already gone, so they've left the list."
        }
        if total == 0 { return "Nothing copied. " + leftOutText + " Scan again, then try once more." }
        let moved = "\(watch.moved.count) of \(total) moved to the Trash (\(byteLabel(watch.movedBytes)))."
        if watch.done { return "Moved to the Trash: \(total == 1 ? "the item" : "all \(total)"), \(byteLabel(watch.movedBytes)). Empty the Trash to get the space back." + left }
        if watch.moved.isEmpty { return "Copied a command for \(total == 1 ? "1 item" : "\(total) items") (\(byteLabel(watch.bytes))). Paste it in Terminal and press Return; it prints a line for each." + left }
        return moved + (watch.expired ? " The rest are still in place; History lists them." : " Waiting for the rest.")
    }
    private var itemList: String {
        let copied = watch.paths.map { (watch.moved.contains($0) ? "✓ " : "· ") + abbreviatedPath($0) }
        let left = watch.leftOut.map { "✕ " + abbreviatedPath($0.key) + " (" + $0.value.rawValue.lowercased() + ")" }
        return (copied + left).joined(separator: "\n")
    }
    /// "Left out 2: 1 changed since the scan, 1 open in an app."
    private var leftOutText: String {
        let groups = Dictionary(grouping: watch.leftOut.values, by: { $0 })
        let parts = [LeftOut.changed, .open, .gone].compactMap { reason in groups[reason].map { "\($0.count) \(reason.rawValue.lowercased())" } }
        return "Left out \(watch.leftOut.count): " + parts.joined(separator: ", ") + "."
    }
}
