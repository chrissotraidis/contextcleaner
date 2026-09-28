import SwiftUI
import AppKit
import Charts
import Combine

struct TracePoint: Identifiable {
    var id: String; var date: Date; var bytes: Int64; var segment: Int
}
struct MainView: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.colorScheme) var colorScheme
    @State var sortOrder = [KeyPathComparator(\FolderRow.bytes, order: .reverse)]
    var appearance: String { model.preferences.appearance ?? "System" }
    @State var simulatorSearch = ""
    @State var showingAccessHelp = false
    let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.section }, set: { model.categoryFilter = nil; model.section = $0 })) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Label { Text(section.rawValue) } icon: { Image(systemName: section.symbol).foregroundStyle(section.tint ?? Color.primary) }.tag(section)
                        .badge(section == .needsAttention ? model.attentionCount : 0)
                }
            }.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                Label("Never deletes. You do, in Finder.", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                header
                if model.section == .overview { Dashboard(model: model) }
                else if model.section == .history { scanHistory }
                else {
                    // A fixed proportional split never reports a width larger than the window,
                    // so the header, table and inspector stay inside the visible area at any size.
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            VStack(spacing: 0) { filterBar; categoryBanner; folderTable }
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
        .onChange(of: model.selected) { _, _ in model.inspector = "Overview" }
        .onChange(of: model.search) { _, value in
            if !value.isEmpty && model.section == .overview { model.section = .locations; model.locationFilter = .all; model.categoryFilter = nil }
            model.retainVisibleSelection()
        }
        .onChange(of: model.section) { _, _ in model.retainVisibleSelection() }
        .onChange(of: model.locationFilter) { _, _ in model.retainVisibleSelection() }
        .onChange(of: model.categoryFilter) { _, _ in model.retainVisibleSelection() }
        .toolbar {
            ToolbarItemGroup {
                Button { model.showingScanPlan = true } label: { Label("Scan Folders…", systemImage: "magnifyingglass").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderedProminent).help("Choose what Context Cleaner will scan (Command-R)").disabled(model.running || model.inspecting || model.discovering || model.store == nil)
                if model.running || model.discovering { Button("Stop Scan") { model.cancelWork() } }
            }
            if #available(macOS 26.0, *) { ToolbarSpacer(.fixed) }
            ToolbarItemGroup {
                Button { model.exportReport() } label: { Label("Report…", systemImage: "doc.text").labelStyle(.titleAndIcon) }.help("Preview a local folder report before saving (Shift-Command-E)")
                Button { model.toggleAppearance(current: colorScheme) } label: { Label(colorScheme == .dark ? "Switch to Light" : "Switch to Dark", systemImage: colorScheme == .dark ? "sun.max" : "moon") }.help("Toggle light and dark. Choose Match System in Settings.")
            }
        }
        .searchable(text: $model.search, prompt: "Search names, projects, apps, tags")
        .sheet(item: Binding(get: { model.editing.map { EditTarget(id: $0) } }, set: { model.editing = $0?.id })) { target in
            PolicyEditor(path: target.id, initial: model.preferences.policy(target.id)) { value in model.policy(target.id) { $0 = value }; model.editing = nil }
        }
        .sheet(isPresented: $model.showingScanPlan) { ScanPlanView(model: model) }
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
        .sheet(isPresented: Binding(get: { model.reportPreview != nil }, set: { if !$0 { model.reportPreview = nil } })) {
            ReportPreview(model: model, text: model.reportPreview ?? "")
        }
        .onReceive(timer) { _ in
            model.checkScheduledPass()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cancellation.cancel(); model.inspectionCancellation.cancel() }
    }
    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if model.section == .overview, let icon = NSImage(named: "NSApplicationIcon") {
                Image(nsImage: icon).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.section == .overview ? "Storage at a glance" : model.section.rawValue).font(.title.weight(.semibold))
                Text(model.section.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.section != .overview, let v = model.volume {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(byteLabel(v.free)) free / \(byteLabel(v.total))").font(.caption).monospacedDigit()
                    ProportionBar(value: Double(v.used) / Double(v.total), tint: .indigo).frame(width: 180)
                    Text("\((Double(v.used) / Double(v.total)).formatted(.percent.precision(.fractionLength(0)))) used · checked \(v.date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                }
            } else { CapsuleLabel(text: "Never deletes files", symbol: "lock.shield") }
        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 10)
    }
    @ViewBuilder var filterBar: some View {
        if model.section == .locations {
            HStack(spacing: 12) {
                Picker("Show", selection: $model.locationFilter) { ForEach(LocationFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).frame(width: 195)
                Spacer()
                Text(model.search.isEmpty ? model.locationFilter.explanation : "\(model.rows.count) matches in \(model.locationFilter.rawValue) · names, projects, apps and tags").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 380, alignment: .trailing)
            }.padding(.horizontal, 16).padding(.bottom, 8)
        } else if !model.search.isEmpty {
            Text("Matching “\(model.search)” in names, projects, apps and tags · \(model.rows.count) locations").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
        }
        if let summary = model.selectionSummary {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text("\(model.selection.count) selected · \(byteLabel(summary.bytes))").font(.callout.weight(.semibold)).monospacedDigit()
                Text(summary.unmeasured > 0 ? "nested folders counted once · \(summary.unmeasured) not measured" : "nested folders counted once").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.selection.map { URL(fileURLWithPath: $0) }) }.controlSize(.small)
                Button("Watch All") { for path in model.selection { model.policy(path) { $0.isWatched = true } } }.controlSize(.small)
                Button("Clear") { model.selection = [] }.controlSize(.small)
            }.padding(.horizontal, 14).padding(.vertical, 8).background(Color.accentColor.opacity(0.10)).accessibilityElement(children: .contain).accessibilityLabel("\(model.selection.count) selected, \(byteLabel(summary.bytes))")
        }
    }
    @ViewBuilder var categoryBanner: some View {
        if let category = model.categoryFilter {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: category.symbol).font(.title2).foregroundStyle(category.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) { Text(category.displayName).font(.headline); Text(category.shortPurpose).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("Clear filter", systemImage: "xmark.circle") { model.categoryFilter = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }.padding(14).background(category.tint.opacity(0.07))
        }
    }
    var folderTable: some View {
        Table(model.rows.sorted(using: sortOrder), selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Folder", value: \.name) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Label { Text(row.name).lineLimit(1) } icon: { Image(systemName: row.measurement.profile.category.symbol).foregroundStyle(model.selection.contains(row.id) ? Color.white : row.measurement.profile.category.tint) }.help(row.measurement.profile.path)
                    Text(row.app + " · " + row.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.width(min: 190, ideal: 260)
            TableColumn("Size", value: \.bytes) { row in Text(row.bytes >= 0 ? byteLabel(row.bytes) : "—").monospacedDigit() }.width(min: 100, ideal: 110)
            TableColumn("Change", value: \.delta) { row in
                Text(row.change.delta.map { "\($0 > 0 ? "+" : $0 < 0 ? "−" : "")\(byteLabel(abs($0)))" } ?? (row.measurement.state == .pending ? "—" : "First scan")).font(.caption).foregroundStyle((row.change.delta ?? 0) > 0 ? Color.growing : .secondary)
            }.width(min: 100, ideal: 110)
            TableColumn("Status", value: \.status) { row in Text(row.status).font(.caption).foregroundStyle(model.selection.contains(row.id) ? Color.white : row.statusTint) }.width(min: 85, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if paths.count > 1 { SelectionActions(model: model, paths: Array(paths).sorted()) }
            else if let path = paths.first { LocationActions(model: model, path: path) }
        }
        .overlay {
            if model.rows.isEmpty { ContentUnavailableView(model.section == .needsAttention ? "No scan issues" : "No matching folders", systemImage: model.section == .needsAttention ? "checkmark.circle" : "folder", description: Text(model.section == .needsAttention ? "Scans that need access or reach a limit will appear here." : "Try another filter or scan folders to update the list.")) }
        }
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = model.selectionSummary {
                    Text("\(model.selection.count) locations selected").font(.title3.weight(.semibold))
                    Text(byteLabel(summary.bytes)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text(summary.unmeasured > 0 ? "Measured sizes added, nested folders counted once. \(summary.unmeasured) selected \(summary.unmeasured == 1 ? "location has" : "locations have") no size yet." : "Measured sizes added, nested folders counted once.").font(.caption).foregroundStyle(.secondary)
                    let byCategory = Dictionary(grouping: summary.items.filter { $0.state == .measured }, by: { $0.profile.category })
                    ForEach(byCategory.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                        HStack { Circle().fill(category.tint).frame(width: 8, height: 8).accessibilityHidden(true); Text(category.displayName).font(.caption); Spacer(); Text("\(byCategory[category]!.count) · \(byteLabel(uniqueAllocatedTotal(byCategory[category]!)))").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    Divider()
                    ForEach(summary.items.sorted { ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1) }.prefix(12), id: \.profile.path) { item in
                        HStack { Text(item.profile.displayName).font(.caption).lineLimit(1); Spacer(); Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.caption).monospacedDigit() }
                    }
                    if summary.items.count > 12 { Text("and \(summary.items.count - 12) more").font(.caption).foregroundStyle(.secondary) }
                    HStack { Button("Reveal All in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting(model.selection.map { URL(fileURLWithPath: $0) }) }.buttonStyle(.borderedProminent); Menu("More") { SelectionActions(model: model, paths: Array(model.selection).sorted()) }.frame(maxWidth: 110) }
                    Text("Context Cleaner never deletes files. You decide, in Finder.").font(.caption).foregroundStyle(.secondary)
                } else if let item = model.chosen {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.profile.category.symbol).font(.title2).foregroundStyle(item.profile.category.tint).frame(width: 46, height: 46).background(item.profile.category.tint.opacity(0.12), in: Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.profile.displayName).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            Text(item.profile.project ?? item.profile.associatedApp).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.allocatedBytes.map(byteLabel) ?? "Size unknown").font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                        Spacer()
                        Button { model.policy(item.profile.path) { $0.isWatched.toggle() } } label: { Label(model.preferences.policy(item.profile.path).isWatched ? "Watching" : "Watch folder", systemImage: model.preferences.policy(item.profile.path).isWatched ? "eye.fill" : "eye") }.buttonStyle(.bordered)
                    }
                    if item.state != .pending {
                        Text("\(item.state == .measured ? "Scanned" : "Last attempt") \(item.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Folder details", selection: $model.inspector) {
                        ForEach(["Overview", "Contents", "History", "Evidence"], id: \.self) { Text($0 == "History" ? "Size history" : $0 == "Evidence" ? "Sources" : $0).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    if item.state != .measured {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(item.state == .pending ? "Not scanned yet" : item.state == .limited ? "This scan reached its limit" : item.state == .missing ? "Folder not found" : item.state == .inaccessible ? "Permission needed" : "Scan could not finish",
                                  systemImage: item.state == .pending ? "clock" : "exclamationmark.triangle")
                                .font(.headline).foregroundStyle(item.state == .pending ? Color.secondary : .attention)
                            Text(item.state == .pending ? "Scan this folder to check its size. Your files stay untouched." : item.state == .limited ? "There was too much to check in the allowed time. Try a smaller subfolder or change the limits in Settings." : item.state == .missing ? "It may have moved or been removed since it was found." : item.state == .inaccessible ? "macOS did not allow access to this folder." : "No complete size was saved. Earlier readings are still available.")
                                .font(.callout).foregroundStyle(.secondary)
                            if item.state == .inaccessible { Button("How to Allow Access…") { showingAccessHelp = true } }
                            if item.state == .limited { Button("Browse Subfolders") { model.inspector = "Contents" } }
                            if item.state != .pending, let reason = item.diagnostic { DisclosureGroup("Technical details") { Text(reason).font(.caption).textSelection(.enabled) }.font(.caption) }
                        }.padding(14).background(.background.secondary)
                    }
                    switch model.inspector {
                    case "Contents": contents(item)
                    case "History": history(item)
                    case "Evidence": evidence(item)
                    default: overview(item)
                    }
                    Divider()
                    DisclosureGroup("Folder path") { Text(item.profile.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).padding(.top, 5) }
                    HStack {
                        Button("Scan Folder", systemImage: "magnifyingglass") { model.scan(selectedOnly: true) }
                            .buttonStyle(.borderedProminent).disabled(!model.canRescanSelection).help("Check only this folder; no files are changed")
                        Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.profile.path)]) }
                        Menu { LocationActions(model: model, path: item.profile.path) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26).accessibilityLabel("Folder actions")
                    }
                    Text("Context Cleaner never deletes files. You decide, in Finder.").font(.caption).foregroundStyle(.secondary)
                } else if model.running, let path = model.selected {
                    ProgressView()
                    Text("Measuring selected location…").font(.title3)
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(model.progress).font(.callout)
                } else {
                    Image(systemName: "folder.badge.questionmark").font(.largeTitle).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    Text(model.section == .needsAttention && model.rows.isEmpty ? "No scan issues" : "Choose a folder").font(.title2)
                    Text(model.section == .needsAttention && model.rows.isEmpty ? "Folders that have not been scanned yet are in Folders › Not scanned." : "See its size, what it contains, and how it has changed.").foregroundStyle(.secondary)
                    Text("Right-click a folder to add notes, watch it or skip future scans.").font(.callout)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func overview(_ item: FolderMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if let workspace = item.profile.evidence.first(where: { $0.label == "Workspace" }) { Label(workspace.value, systemImage: "folder.badge.gearshape").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let device = item.profile.evidence.first(where: { $0.label == "Device name" }) { Label(device.value, systemImage: "iphone").font(.caption).foregroundStyle(.purple).lineLimit(1) }
            }
            if item.state != .pending { FolderTrend(path: item.profile.path, points: model.history(item.profile.path), change: model.growthSummary(item.profile.path), compact: true) }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.profile.category.reproducible ? "arrow.triangle.2.circlepath" : "hand.raised").foregroundStyle(item.profile.category.reproducible ? Color.accentColor : Color.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.profile.category.reproducible ? "Can usually be rebuilt" : "May contain personal files").font(.headline)
                    Text(item.profile.consequence).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup("What’s in this folder?") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.profile.category.shortPurpose)
                    Text(item.profile.explanation).foregroundStyle(.secondary)
                    if item.profile.category == .simulator {
                        Text("Simulators are virtual test devices, separate from physical iPhones and iPads. Their app data can include unique saves.").foregroundStyle(.secondary)
                        Button("Explore devices and app data", systemImage: "square.stack.3d.up") { model.inspector = "Contents" }
                    }
                    if item.fileCount > 0 { LabeledContent("Files", value: item.fileCount.formatted()) }
                    if let modified = item.latestModifiedAt { LabeledContent("Latest change", value: modified.formatted(date: .abbreviated, time: .shortened)) }
                    Text(item.activityCheckAvailable ? "\(Set(item.processes.map(\.pid)).count) processes had open handles at scan time. Not proof of writing or inactivity." : "Process activity was not captured. Rescan to check open handles.").foregroundStyle(.secondary)
                    if let diagnostic = item.diagnostic { Text(diagnostic).textSelection(.enabled).foregroundStyle(.secondary) }
                }.font(.caption).padding(.top, 6)
            }
            let policy = model.preferences.policy(item.profile.path)
            if !policy.tags.isEmpty { Text("Tags: " + policy.tags.joined(separator: ", ")).font(.callout) }
            if !policy.note.isEmpty { Text(policy.note).font(.callout).textSelection(.enabled) }
            if policy.expected { CapsuleLabel(text: "Growth marked as expected", symbol: "checkmark.circle", color: .stable) }
            if policy.autoWatched == true {
                HStack(spacing: 10) {
                    CapsuleLabel(text: "Added to Watching automatically" + (policy.autoWatchedBytes.map { " · grew \(byteLabel($0))" } ?? ""), symbol: "eye", color: .growing)
                    Button("Undo") { model.undoAutoWatch(item.profile.path) }.controlSize(.small)
                }
                Text("It grew between two comparable scans. Watchlist folders get priority in scheduled scans. Mark growth as expected to stop this.").font(.caption).foregroundStyle(.secondary)
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
    func trace(_ points: [HistoryPoint]) -> [TracePoint] {
        var result: [TracePoint] = [], segment = 0, scope: String?
        for point in points {
            guard let bytes = point.bytes else { segment += 1; scope = nil; continue }
            if let scope, scope != point.scopeID { segment += 1 }
            scope = point.scopeID
            result.append(TracePoint(id: point.id, date: point.date, bytes: bytes, segment: segment))
        }
        return result
    }
    func history(_ item: FolderMeasurement) -> some View {
        let points = model.history(item.profile.path)
        let summary = model.growthSummary(item.profile.path)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Measured history").font(.headline)
            if points.isEmpty { Text("No saved measurements for this location. Rescan it to establish a baseline.") }
            else {
                Chart(trace(points)) { point in
                    LineMark(x: .value("Observed", point.date), y: .value("GiB", Double(point.bytes) / 1_073_741_824), series: .value("Comparable series", point.segment)).foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Observed", point.date), y: .value("GiB", Double(point.bytes) / 1_073_741_824)).foregroundStyle(Color.accentColor)
                }.chartYAxisLabel("GiB").frame(height: 170).accessibilityLabel("Folder size over recorded observations; detailed values below")
                if points.count == 1 { Text("One observation. No earlier growth is known.").font(.caption).foregroundStyle(.secondary) }
                if let delta = summary.delta, let interval = summary.interval {
                    Text("\(delta > 0 ? "+" : delta < 0 ? "−" : "")\(byteLabel(abs(delta))) over \(elapsedLabel(interval))").font(.headline)
                    if let rate = summary.bytesPerDay { Text("Net rate for this interval: \(rate > 0 ? "+" : rate < 0 ? "−" : "")\(byteLabel(Int64(abs(rate))))/day. Not a forecast.").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(points.reversed()) { point in
                    HStack { Text(point.date.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(point.bytes.map(byteLabel) ?? point.state.rawValue) }.font(.caption)
                }
                Text("Lines connect comparable measured endpoints. Changes between scans are unknown. Scope changes and failed observations break the series.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    func evidence(_ item: FolderMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What we know, and how").font(.headline)
            Text("Association identifies a likely purpose or owner. It does not establish which process wrote the data.").font(.caption).foregroundStyle(.secondary)
            ForEach(item.profile.evidence) { e in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(e.label).font(.headline)
                        Spacer()
                        CapsuleLabel(text: e.level.rawValue, symbol: e.level == .observed ? "checkmark.circle" : e.level == .inferred ? "link" : "questionmark.circle", color: e.level == .observed ? .accentColor : e.level == .inferred ? .blue : .secondary)
                    }
                    Text(e.value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("How we know") { Text(e.source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 5) }
                }.padding(14).background(.background.secondary)
            }
            DisclosureGroup("Processes with open handles · \(Set(item.processes.map(\.pid)).count)") {
                VStack(alignment: .leading, spacing: 8) {
                    if !item.activityCheckAvailable { Text("Not captured for this observation. Rescan to check current handles.") }
                    else if item.processes.isEmpty { Text("None detected at scan start. This is not proof of inactivity.") }
                    ForEach(Array(item.processes.prefix(30).enumerated()), id: \.offset) { _, p in Text("\(p.command) · PID \(p.pid)\n\(p.access)\n\(p.path)").textSelection(.enabled) }
                    if item.processes.count > 30 { Text("Showing 30 of \(item.processes.count) handle observations.") }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }
    /// Saved scan outcomes, with the scanned objects named before technical details.
    var scanHistory: some View {
        let records = model.records.sorted { $0.finishedAt > $1.finishedAt }
        return List {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                let previous = records.dropFirst(index + 1).first { $0.scope == record.scope && $0.complete }
                let changes = scanDelta(record, previous: previous)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if let changes {
                            let delta = changes.grew.reduce(Int64(0)) { $0 + $1.delta } + changes.shrank.reduce(Int64(0)) { $0 + $1.delta }
                            Text(delta == 0 ? "No overall size change in folders checked in both scans." : byteLabel(abs(delta)) + (delta > 0 ? " larger" : " smaller") + " across folders checked in both scans.").font(.callout)
                        } else { Text("No earlier scan of the same folders to compare yet.").font(.callout).foregroundStyle(.secondary) }
                        ForEach(record.measurements) { item in
                            HStack(alignment: .top) {
                                Text(item.profile.displayName).lineLimit(1).help(item.profile.path)
                                Spacer()
                                Text(item.state == .measured ? item.allocatedBytes.map(byteLabel) ?? "Unknown size" : item.state == .cancelled ? "Stopped" : item.state.rawValue.capitalized).foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                        if let free = record.freeBytes { Text("Disk space at the time: " + byteLabel(free) + " free").font(.caption).foregroundStyle(.secondary) }
                        Text("Scan duration: " + elapsedLabel(record.finishedAt.timeIntervalSince(record.startedAt))).font(.caption).foregroundStyle(.secondary)
                        if !record.discoveryNotes.isEmpty { DisclosureGroup("Scan details") { ForEach(Array(record.discoveryNotes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption).textSelection(.enabled) } }.font(.caption) }
                    }.padding(.vertical, 8)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: record.complete ? "checkmark.circle" : "stop.circle").foregroundStyle(record.complete ? Color.accentColor : .growing).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.folderSummary).font(.headline).lineLimit(1)
                            Text(record.resultSummary).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.finishedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
        }.overlay { if records.isEmpty { ContentUnavailableView("No scans yet", systemImage: "clock", description: Text("Completed and stopped folder scans will appear here.")) } }
    }
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if model.discovering { HStack { ProgressView().controlSize(.small); Text(model.progress).font(.caption).textSelection(.enabled) } }
            if model.running {
                HStack {
                    if model.targetCount > 0 {
                        ProgressView(value: Double(model.completed), total: Double(model.targetCount)).frame(width: 120)
                        Text("\(model.completed) of \(model.targetCount) folders checked · \(model.progress)").lineLimit(1).truncationMode(.middle)
                    } else { ProgressView().controlSize(.small); Text(model.progress).lineLimit(1).truncationMode(.middle) }
                }.font(.caption)
            } else if !model.discovering && model.progress != "Ready" { Text(model.progress).font(.caption).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(Color.attention).textSelection(.enabled) }
            HStack {
                Text(model.preferences.effectiveSchedule == "off" ? "Scheduled checks are off." : model.preferences.effectiveSchedule == "daily" ? "Checking priority locations daily while open." : "Checking priority locations weekly while open.").font(.caption).foregroundStyle(.secondary)
                SettingsLink { Text("Change…").font(.caption) }.buttonStyle(.link)
                Spacer()
                Text("\(model.discovery.profiles.count) folders · \(model.records.count) saved scans").font(.caption).foregroundStyle(.secondary)
            }
            if model.section == .locations { Text("Saved folder sizes are estimates. Context Cleaner never deletes files.").font(.caption2).foregroundStyle(.secondary) }
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
                    Button("Add Location…") { model.addRoot() }.keyboardShortcut("o", modifiers: [.command, .shift])
                    Button("Export Report…") { model.exportReport() }.keyboardShortcut("e", modifiers: [.command, .shift])
                }
                CommandGroup(after: .sidebar) {
                    Button(model.effectiveDarkAppearance ? "Switch to Light Appearance" : "Switch to Dark Appearance") { model.toggleAppearance() }
                        .keyboardShortcut("l", modifiers: [.command, .shift])
                }
                CommandMenu("Scan") {
                    Button("Scan Folders…") { model.showingScanPlan = true }.keyboardShortcut("r").disabled(model.running || model.inspecting || model.discovering)
                    Button("Scan This Folder") { model.scan(selectedOnly: true) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!model.canRescanSelection)
                    Button("Scan Watched Locations") { model.scan(watchedOnly: true) }.disabled(model.running || model.inspecting || model.discovering)
                    Button("Rediscover Locations") { model.discover() }.disabled(model.running || model.inspecting || model.discovering)
                    Divider()
                    Button("Cancel") { model.cancelWork() }.keyboardShortcut(".").disabled(!(model.running || model.discovering))
                }
                CommandMenu("Location") {
                    if model.selection.count > 1 {
                        SelectionActions(model: model, paths: Array(model.selection).sorted())
                    } else if let path = model.selected {
                        LocationActions(model: model, path: path)
                    } else {
                        Text("Select a location first")
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
        VStack(alignment: .leading, spacing: 18) {
            Label("Understanding access problems", systemImage: "lock.open").font(.title2)
            Text("A folder can be unreadable because of macOS privacy controls, file permissions, a disconnected volume or an I/O error. The scan’s diagnostic is the best starting point.")
            Text("For protected folders on your Mac:").font(.headline)
            Text("1. Open System Settings → Privacy & Security → Full Disk Access.\n2. Add the Context Cleaner app you are actually running and enable it.\n3. Quit and reopen Context Cleaner, then rescan the selected folder.")
            Text("Access is your choice. You can instead exclude the folder from scanning. Context Cleaner does not change permissions or use administrator commands.").font(.callout).foregroundStyle(.secondary)
            Text("When testing a new development build, macOS may require approving that particular build again.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Scanning allowances").font(.headline)
            Text("Priority checks: 10 seconds or 100,000 entries per location, up to 90 seconds of measurement per pass. Manual defaults: 120 seconds or 1,000,000 entries per location, up to 15 minutes per pass. A slow filesystem call can delay stopping.").font(.caption).foregroundStyle(.secondary)
            Text("An incomplete scan never supplies a complete size. Choose a smaller child folder to investigate large locations. Daily checks run only while this app is open and record attempts so failures do not trigger rapid retries.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal this app in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 560)
    }
}

struct ReportPreview: View {
    @ObservedObject var model: CleanerModel
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export report").font(.title2.weight(.semibold))
            Text("Local Markdown report for \(model.rows.count) \(model.rows.count == 1 ? "folder" : "folders"). Includes sizes, changes, paths, explanations and your notes. Preview it below, then save a new file. Nothing is uploaded.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let excerpt = text.count > 6000 ? String(text.prefix(6000)) + "\n\n… preview shortened. The saved file contains every location." : text
            ScrollView { Text(excerpt).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                .background(.background.secondary)
            HStack {
                Text("\(text.utf8.count.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                Button("Cancel") { model.reportPreview = nil }.keyboardShortcut(.cancelAction)
                Button("Save…") { model.saveReport(text) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 720, height: 560)
    }
}
