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
    let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
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
                Label("Never deletes. You do, in Finder.", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                header
                scanBanner
                if model.section == .overview { Dashboard(model: model) }
                else if model.section == .history { scanHistory }
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
            if !value.isEmpty && model.section == .overview { model.section = .locations; model.locationFilter = .all; model.categoryFilter = nil }
            model.retainVisibleSelection()
        }
        .onChange(of: model.section) { _, _ in model.retainVisibleSelection() }
        .onChange(of: model.locationFilter) { _, _ in model.retainVisibleSelection() }
        .onChange(of: model.categoryFilter) { _, _ in model.retainVisibleSelection() }
        .toolbar {
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
                Button { model.exportReport() } label: { Label("Export Report…", systemImage: "square.and.arrow.up") }
                    .help("Preview a Markdown report of the folders shown here, then save it (Shift-Command-E)")
            }
        }
        .searchable(text: $model.search, prompt: "Search folders, apps, projects, tags")
        .sheet(item: Binding(get: { model.editing.map { EditTarget(id: $0) } }, set: { model.editing = $0?.id })) { target in
            PolicyEditor(path: target.id, initial: model.preferences.policy(target.id)) { value in model.policy(target.id) { $0 = value }; model.editing = nil }
        }
        .sheet(isPresented: $model.showingScanPlan) { ScanPlanView(model: model) }
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
        .sheet(isPresented: Binding(get: { model.reportPreview != nil }, set: { if !$0 { model.reportPreview = nil } })) {
            ReportPreview(model: model, text: model.reportPreview ?? "")
        }
        .onReceive(timer) { _ in
            model.refreshVolume()
            model.checkScheduledPass()
        }
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
            } else { CapsuleLabel(text: "Never deletes files", symbol: "lock.shield") }
        }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 10)
    }
    /// Scope and progress while a scan runs, then a one-line result.
    @ViewBuilder var scanBanner: some View {
        if model.running || model.discovering {
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
        } else if let result = model.lastResult {
            let stopped = result.hasPrefix("Stopped")
            let unreadable = result.contains("couldn't be read")
            HStack(spacing: 10) {
                Image(systemName: stopped ? "stop.circle" : unreadable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(stopped ? Color.growing : unreadable ? Color.attention : Color.accentColor).accessibilityHidden(true)
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
            HStack(spacing: 12) {
                Picker("Show", selection: $model.locationFilter) { ForEach(LocationFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).fixedSize()
                Text(model.search.isEmpty ? model.locationFilter.explanation : "\(model.rows.count) \(model.rows.count == 1 ? "match" : "matches") for “\(model.search)” in folder names, apps, projects and tags").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }.padding(.horizontal, 16).padding(.bottom, 8)
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
    var folderTable: some View {
        Table(model.rows.sorted(using: sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Folder", value: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Label { Text(row.name).lineLimit(1) } icon: { Image(systemName: row.measurement.profile.category.symbol).foregroundStyle(selectedRow(row.id) ? Color.white : row.measurement.profile.category.tint) }.help(row.measurement.profile.path)
                    Text(row.app + " · " + row.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.width(min: 170, ideal: 230)
            TableColumn("Size", value: \.bytes) { row in Text(row.bytes >= 0 ? byteLabel(row.bytes) : "—").font(.callout).monospacedDigit() }.width(min: 80, ideal: 90)
            TableColumn("Trend", value: \.delta) { row in
                let values = model.sparkline(row.id)
                HStack(spacing: 8) {
                    if values.count > 1 { Sparkline(values: values, tint: selectedRow(row.id) ? .white : values.trendTint) }
                    else { Text(row.measurement.state == .measured ? "1 scan" : "—").font(.caption).foregroundStyle(selectedRow(row.id) ? Color.white : Color.secondary.opacity(0.6)) }
                    if let delta = row.change.delta, delta != 0 {
                        Text(signedBytes(delta)).font(.caption).monospacedDigit().foregroundStyle(selectedRow(row.id) ? Color.white : delta > 0 ? Color.growing : Color.stable)
                    }
                }.help(values.count > 1 ? "Size across the last \(values.count) comparable scans" : "Needs two scans to show a trend")
            }.width(min: 90, ideal: 120)
            TableColumn("Status", value: \.status) { row in Text(row.status).font(.caption).foregroundStyle(selectedRow(row.id) ? Color.white : row.statusTint) }.width(min: 60, ideal: 80)
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
        Table(model.rows.sorted(using: sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
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
                    Text("Every scanned folder was read completely. If macOS blocks a folder, or one is too large or goes missing, it shows up here with a fix.")
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
                    let byCategory = Dictionary(grouping: summary.items.filter { $0.state == .measured }, by: { $0.profile.category })
                    ForEach(byCategory.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                        HStack { Circle().fill(category.tint).frame(width: 8, height: 8).accessibilityHidden(true); Text(category.displayName).font(.callout); Spacer(); Text("\(byCategory[category]!.count) · \(byteLabel(uniqueAllocatedTotal(byCategory[category]!)))").font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(summary.items.sorted { ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1) }.prefix(12), id: \.profile.path) { item in
                        HStack { Text(item.profile.displayName).font(.callout).lineLimit(1); Spacer(); Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit() }
                    }
                    if summary.items.count > 12 { Text("and \(summary.items.count - 12) more").font(.caption).foregroundStyle(.secondary) }
                    HStack { Button("Show All in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting(model.selection.map { URL(fileURLWithPath: $0) }) }.buttonStyle(.borderedProminent); Menu("More") { SelectionActions(model: model, paths: Array(model.selection).sorted()) }.fixedSize() }
                    Text("Context Cleaner never deletes files. You decide, in Finder.").font(.caption).foregroundStyle(.secondary)
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
            Text("in \(measured.count) scanned \(measured.count == 1 ? "folder" : "folders")\(pending > 0 ? " · \(pending) not scanned yet" : "")").font(.callout).foregroundStyle(.secondary)
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
                Text((item.profile.project ?? item.profile.associatedApp) + " · " + item.profile.category.displayName).font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack(alignment: .firstTextBaseline) {
            Text(item.state == .pending ? "Not scanned" : item.allocatedBytes.map(byteLabel) ?? "Size unknown").font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
            Spacer()
            Button { model.policy(path) { $0.isWatched.toggle() } } label: { Label(policy.isWatched ? "Watching" : "Watch", systemImage: policy.isWatched ? "eye.fill" : "eye") }
                .help(policy.isWatched ? "Remove from your watchlist" : "Add to your watchlist; scheduled checks look at it first")
            Menu { LocationActions(model: model, path: path) } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More actions for this folder")
        }
        Text(item.profile.category.shortPurpose).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            CapsuleLabel(text: item.profile.category.reproducible ? "Usually rebuildable" : "May hold personal files", symbol: item.profile.category.reproducible ? "arrow.triangle.2.circlepath" : "hand.raised", color: item.profile.category.reproducible ? .accentColor : .secondary)
            if item.state == .measured { Text("Scanned \(item.observedAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
        }
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
        Text("Context Cleaner never deletes files. You decide, in Finder.").font(.caption).foregroundStyle(.secondary)
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
                                } else { Text("Size not yet measured").font(.caption2).foregroundStyle(.secondary) }
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
            } else { Text("Rescan this folder to record its child and file-type breakdown. Earlier snapshots do not contain this detail.").font(.callout) }
            Divider()
            if let events = childChanges(item.profile.path, records: model.records) {
                ChildEventsView(events: events).id(item.profile.path)
            }
            Divider()
            Text("Inspect further").font(.headline)
            if model.inspecting { ProgressView(); Text("Measuring and preserving individual observations…").font(.caption); Button("Stop inspecting") { model.inspectionCancellation.cancel() } }
            else {
                Button("Measure child folders and files") { model.inspectChildren(item) }.disabled(model.running || model.preferences.excluded(item.profile.path))
                if SimulatorLocations.deviceRoot(item.profile.path) != nil {
                    Button("Inspect simulator apps and data") { model.inspectChildren(item, simulatorApps: true) }.disabled(model.running || model.preferences.excluded(item.profile.path))
                    Text("Reads app, data and shared-group containers for this device. Stored metadata does not establish current boot state or whether saves are expendable.").font(.caption).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 8) {
                if let changes {
                    let delta = changes.grew.reduce(Int64(0)) { $0 + $1.delta } + changes.shrank.reduce(Int64(0)) { $0 + $1.delta }
                    Text(delta == 0 ? "Same total size as the scan before." : signedBytes(delta) + " compared with the scan before, in folders both scans read.").font(.callout)
                } else { Text("Nothing earlier to compare with yet.").font(.callout).foregroundStyle(.secondary) }
                ForEach(record.measurements.prefix(40)) { item in
                    HStack(alignment: .top) {
                        Text(item.profile.displayName).lineLimit(1).help(item.profile.path)
                        Spacer()
                        Text(item.state == .measured ? item.allocatedBytes.map(byteLabel) ?? "Size unknown" : item.state == .cancelled ? "Stopped" : item.state.problem).monospacedDigit().foregroundStyle(item.state == .measured || item.state == .cancelled ? Color.secondary : Color.attention)
                    }.font(.caption)
                }
                if record.measurements.count > 40 { Text("and \(record.measurements.count - 40) more").font(.caption).foregroundStyle(.secondary) }
                Text([record.freeBytes.map { byteLabel($0) + " free on disk at the time" }, "took " + elapsedLabel(record.finishedAt.timeIntervalSince(record.startedAt))].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        } label: {
            HStack(spacing: 12) {
                let problem = !record.wasStopped && record.measurements.contains { [.inaccessible, .limited, .missing, .failed].contains($0.state) }
                Image(systemName: record.wasStopped ? "stop.circle" : problem ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(record.wasStopped ? Color.growing : problem ? Color.attention : Color.accentColor).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.folderSummary).font(.headline).lineLimit(1)
                    Text(record.resultSummary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.finishedAt.formatted(date: .omitted, time: .shortened)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }.padding(.vertical, 4)
        }
    }
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let error = model.error { Text(error).font(.caption).foregroundStyle(Color.attention).textSelection(.enabled).lineLimit(3) }
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
            Text("Your context for this location").font(.title2)
            Text(path).font(.caption).textSelection(.enabled)
            Toggle("Watch this location", isOn: $value.isWatched)
            Toggle("This growth is expected", isOn: $value.expected)
            Toggle("Review later", isOn: Binding(get: { value.reviewAfter != nil }, set: { value.reviewAfter = $0 ? Date().addingTimeInterval(86400) : nil }))
            if value.reviewAfter != nil {
                DatePicker("Review after", selection: Binding(get: { value.reviewAfter ?? Date() }, set: { value.reviewAfter = $0 }), displayedComponents: [.date, .hourAndMinute])
                Text("Until this time, the location stays out of Growing, Rebuildable and priority checks. Manual scans remain available.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Tags, separated by commas", text: $tags)
            TextField("Review threshold (GiB of growth)", text: $threshold)
            if !validThreshold { Text("Enter a nonnegative number below 1,000,000 GiB, or leave blank.").font(.caption).foregroundStyle(Color.attention) }
            TextField("Notes", text: $value.note, axis: .vertical).lineLimit(3...6)
            Text("Labels guide review. They never authorize file changes or deletion.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save Context") {
                value.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                value.growthThresholdBytes = Double(threshold).flatMap { $0.isFinite && $0 >= 0 && $0 < 1_000_000 ? Int64($0 * 1_073_741_824) : nil }
                save(value)
            }.buttonStyle(.borderedProminent).disabled(!validThreshold) }
        }.padding(24).frame(width: 500)
    }
}
@main struct ContextCleanerApp: App {
    @StateObject private var model = CleanerModel()
    var body: some Scene {
        WindowGroup("Context Cleaner") { MainView(model: model) }.defaultSize(width: 1480, height: 920)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .importExport) {
                    Button("Add Folder to Scan…") { model.addRoot() }.keyboardShortcut("o", modifiers: [.command, .shift])
                    Button("Export Report…") { model.exportReport() }.keyboardShortcut("e", modifiers: [.command, .shift])
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
                    Button("Tags and Notes…") { if let path = model.selected { model.editing = path } }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.selection.count != 1)
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
            Text("Export report").font(.title2.weight(.semibold))
            Text("A Markdown file listing the \(model.rows.count) \(model.rows.count == 1 ? "folder" : "folders") shown in \(model.section == .overview || model.section == .history ? "Folders" : model.section.rawValue): sizes, changes, paths, what each holds and your notes. It stays on your Mac.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let excerpt = text.count > 6000 ? String(text.prefix(6000)) + "\n\n… preview shortened. The saved file contains every folder." : text
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
