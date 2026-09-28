import SwiftUI
import AppKit
import Charts
import Combine

struct TracePoint: Identifiable {
    var id: String; var date: Date; var bytes: Int64; var segment: Int
}
struct MainView: View {
    @StateObject var model = CleanerModel()
    @State var sortOrder = [KeyPathComparator(\FolderRow.bytes, order: .reverse)]
    var appearance: String { model.preferences.appearance ?? "System" }
    @State var simulatorSearch = ""
    @State var showingAccessHelp = false
    let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.section }, set: { model.categoryFilter = nil; model.section = $0 })) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Label { Text(section.rawValue) } icon: { Image(systemName: section.symbol).foregroundStyle(section.tint ?? Color.accentColor) }.tag(section)
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
        .onChange(of: model.search) { _, value in if !value.isEmpty && model.section == .overview { model.section = .locations; model.locationFilter = .all; model.categoryFilter = nil } }
        .toolbar {
            ToolbarItemGroup {
                Button { model.addRoot() } label: { Label("Add Location", systemImage: "folder.badge.plus") }.disabled(model.running || model.inspecting || model.discovering)
                Menu {
                    Button("Scan known and selected locations") { model.scan() }
                    Button("Scan priority locations (up to 12)") { model.scan(priorityOnly: true) }
                    Button("Scan watched locations") { model.scan(watchedOnly: true) }
                    Button("Rescan selected folder") { model.scan(selectedOnly: true) }.disabled(model.selected == nil)
                    Button("Rediscover locations") { model.discover() }
                    Divider()
                    Button("Access and scan limits…") { showingAccessHelp = true }
                } label: { Label("Scan Scope", systemImage: "slider.horizontal.3") }.accessibilityLabel("Scan scope").help("Choose which locations to scan").disabled(model.running || model.inspecting || model.discovering)
                Button { model.scan() } label: { Label("Scan Again", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }.disabled(model.running || model.inspecting || model.discovering || model.store == nil).keyboardShortcut("r")
                if model.running || model.discovering { Button(model.discovering ? "Cancel Discovery" : "Cancel Scan") { model.cancelWork() }.keyboardShortcut(.cancelAction) }
                Button { model.exportReport() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Menu {
                    Picker("Appearance", selection: Binding(get: { appearance }, set: { model.setAppearance($0) })) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) } }
                } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }.accessibilityLabel("Appearance")
            }
        }
        .searchable(text: $model.search, prompt: "Folder, project, app or tag")
        .sheet(item: Binding(get: { model.editing.map { EditTarget(id: $0) } }, set: { model.editing = $0?.id })) { target in
            PolicyEditor(path: target.id, initial: model.preferences.policy(target.id)) { value in model.policy(target.id) { $0 = value }; model.editing = nil }
        }
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
        .onReceive(timer) { _ in
            model.checkScheduledPass()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cancellation.cancel(); model.inspectionCancellation.cancel() }
    }
    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if model.section == .overview, let icon = NSImage(named: "NSApplicationIcon") {
                Image(nsImage: icon).resizable().frame(width: 54, height: 54)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.section == .overview ? "Understand your space." : model.section.rawValue).font(.largeTitle.weight(.semibold))
                Text(model.section.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.section != .overview, let v = model.volume {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(byteLabel(v.free)) free / \(byteLabel(v.total))").font(.caption).monospacedDigit()
                    ProportionBar(value: Double(v.used) / Double(v.total), tint: .indigo).frame(width: 180)
                    Text("Capacity checked \(v.date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                }
            } else { CapsuleLabel(text: "Read-only by design", symbol: "lock.shield") }
        }.padding(.horizontal, 22).padding(.vertical, 18)
    }
    @ViewBuilder var filterBar: some View {
        if model.section == .locations {
            HStack(spacing: 12) {
                Picker("Show", selection: $model.locationFilter) { ForEach(LocationFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
                Spacer()
                Text(model.locationFilter.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 360, alignment: .trailing)
            }.padding(.horizontal, 16).padding(.bottom, 10)
        }
    }
    @ViewBuilder var categoryBanner: some View {
        if let category = model.categoryFilter {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: category.symbol).font(.title2).foregroundStyle(category.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) { Text(category.rawValue).font(.headline); Text(category.shortPurpose).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("Clear filter", systemImage: "xmark.circle") { model.categoryFilter = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }.padding(14).background(category.tint.opacity(0.07))
        }
    }
    var folderTable: some View {
        Table(model.rows.sorted(using: sortOrder), selection: $model.selected, sortOrder: $sortOrder) {
            TableColumn("Folder", value: \.name) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Label { Text(row.name).lineLimit(1) } icon: { Image(systemName: row.measurement.profile.category.symbol).foregroundStyle(model.selected == row.id ? Color.white : row.measurement.profile.category.tint) }.help(row.measurement.profile.path)
                    Text(row.app + " · " + row.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.width(min: 190, ideal: 260)
            TableColumn("Size", value: \.bytes) { row in Text(row.bytes >= 0 ? byteLabel(row.bytes) : "—").monospacedDigit() }.width(min: 100, ideal: 110)
            TableColumn("Change", value: \.delta) { row in
                Text(row.change.delta.map { "\($0 > 0 ? "+" : $0 < 0 ? "−" : "")\(byteLabel(abs($0)))" } ?? "No baseline").font(.caption).foregroundStyle((row.change.delta ?? 0) > 0 ? Color.growing : .secondary)
            }.width(min: 100, ideal: 110)
            TableColumn("Status", value: \.status) { row in Text(row.status).font(.caption).foregroundStyle(model.selected == row.id ? Color.white : ![.measured, .excluded].contains(row.measurement.state) ? Color.attention : row.policy.watched ? Color.accentColor : .secondary) }.width(min: 85, ideal: 95)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first { LocationActions(model: model, path: path) }
        }
        .overlay {
            if model.rows.isEmpty { ContentUnavailableView("No matching locations", systemImage: "folder", description: Text("Change the filter, add a location, or run a scan. Excluded folders have their own section.")) }
        }
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item = model.chosen {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.profile.category.symbol).font(.title2).foregroundStyle(item.profile.category.tint).frame(width: 46, height: 46).background(item.profile.category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.profile.name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            Text(item.profile.project ?? item.profile.associatedApp).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.allocatedBytes.map(byteLabel) ?? "Not measured").font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        Spacer()
                        Button { model.policy(item.profile.path) { $0.watched.toggle() } } label: { Label(model.preferences.policy(item.profile.path).watched ? "Watching" : "Watch", systemImage: model.preferences.policy(item.profile.path).watched ? "eye.fill" : "eye") }.buttonStyle(.bordered)
                    }
                    Text(item.state == .pending ? "Not scanned yet" : "\(item.state == .measured ? "Measured" : "Attempted") \(item.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Picker("Folder details", selection: $model.inspector) {
                        ForEach(["Overview", "Contents", "History", "Evidence"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    if item.state != .measured {
                        Panel(title: item.state == .pending ? "Ready to measure" : item.state == .limited ? "Scan allowance reached" : item.state == .missing ? "Location not found" : "This measurement is incomplete", symbol: "exclamationmark.circle", tint: .attention) {
                            Text(item.diagnostic ?? item.state.rawValue.capitalized).font(.callout).textSelection(.enabled)
                            if item.state != .pending { Text("Earlier observations stay in History. This attempt is not treated as a zero-size folder or as measured growth.").font(.caption).foregroundStyle(.secondary) }
                            Button(item.state == .pending ? "Measure this location" : "Retry selected location", systemImage: "arrow.clockwise") { model.scan(selectedOnly: true) }.disabled(model.running || model.inspecting || model.preferences.excluded(item.profile.path))
                            if item.state == .inaccessible { Button("Access help…", systemImage: "lock.open") { showingAccessHelp = true } }
                            if item.state == .limited { Button("Explore smaller child folders") { model.inspector = "Contents" } }
                        }
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
                        Button("Reveal in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.profile.path)]) }.buttonStyle(.borderedProminent)
                        Button("Rescan") { model.scan(selectedOnly: true) }.keyboardShortcut("r", modifiers: [.command, .shift]).help("Rescan only this folder (Shift-Command-R)").disabled(model.running || model.preferences.excluded(item.profile.path))
                    }
                    HStack {
                        Button("Tags & notes…") { model.editing = item.profile.path }.keyboardShortcut("t", modifiers: [.command, .shift])
                        Menu("More") { LocationActions(model: model, path: item.profile.path) }.frame(maxWidth: 110)
                    }
                    Text("Context Cleaner never deletes files. You control any action in Finder.").font(.caption).foregroundStyle(.secondary)
                } else if model.running, let path = model.selected {
                    ProgressView()
                    Text("Measuring selected location…").font(.title3)
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(model.progress).font(.callout)
                } else {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 36)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    Text("Choose a location").font(.title2)
                    Text("Inspect its purpose, history, associated tools and the evidence behind each conclusion.").foregroundStyle(.secondary)
                    Text("A cache stores reusable output so work does not need to be repeated. Rebuildable does not mean unused or free of consequences.")
                    Text("Right-click a row to watch, tag, mark expected growth or exclude it from scanning.").font(.callout)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func overview(_ item: FolderMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let workspace = item.profile.evidence.first(where: { $0.label == "Workspace" }) {
                Label(workspace.value, systemImage: "folder.badge.gearshape").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let device = item.profile.evidence.first(where: { $0.label == "Device name" }) {
                Label(device.value, systemImage: "iphone").font(.caption).foregroundStyle(.purple)
            }
            FolderTrend(path: item.profile.path, records: model.records, compact: true)
            Panel(title: "What lives here", symbol: item.profile.category.symbol, tint: item.profile.category.tint) {
                Text(item.profile.category.shortPurpose).font(.callout)
                if item.profile.category == .simulator {
                    Button("Explore devices and app data", systemImage: "square.stack.3d.up") { model.inspector = "Contents" }
                    Text("Simulators are virtual test devices, separate from physical iPhones and iPads. Their app data can include unique saves.").font(.caption).foregroundStyle(.secondary)
                } else { Text(item.profile.explanation).font(.caption).foregroundStyle(.secondary) }
            }
            Panel(title: "Before any manual change", symbol: "info.circle", tint: item.profile.category.reproducible ? .accentColor : .attention) {
                CapsuleLabel(text: item.profile.category.reproducible ? "Usually reproducible · review first" : "May contain unique data", symbol: item.profile.category.reproducible ? "arrow.triangle.2.circlepath" : "hand.raised", color: item.profile.category.reproducible ? .accentColor : .attention)
                Text(item.profile.consequence).font(.callout)
            }
            HStack(spacing: 10) {
                Button("Explore contents", systemImage: "folder") { model.inspector = "Contents" }
                Button("View evidence", systemImage: "doc.text.magnifyingglass") { model.inspector = "Evidence" }
            }
            DisclosureGroup("Measurement details") {
                VStack(alignment: .leading, spacing: 8) {
                    if item.fileCount > 0 { LabeledContent("Files", value: item.fileCount.formatted()) }
                    if let modified = item.latestModifiedAt { LabeledContent("Latest modification", value: modified.formatted(date: .abbreviated, time: .shortened)) }
                    Text(item.activityCheckAvailable ? "\(Set(item.processes.map(\.pid)).count) processes had open handles at scan time. This does not prove writing or inactivity." : "Process activity was not captured in this observation. Rescan to check currently open handles.")
                    if let diagnostic = item.diagnostic { Text(diagnostic).textSelection(.enabled) }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
            let policy = model.preferences.policy(item.profile.path)
            if !policy.tags.isEmpty { Text("Tags: " + policy.tags.joined(separator: ", ")).font(.callout) }
            if !policy.note.isEmpty { Text(policy.note).font(.callout).textSelection(.enabled) }
            if policy.expected { CapsuleLabel(text: "Growth marked as expected", symbol: "checkmark.circle") }
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
        let points = historyPoints(item.profile.path, records: model.records)
        let summary = growth(item.profile.path, records: model.records)
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
                }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
    var scanHistory: some View {
        List(model.records.reversed()) { record in
            VStack(alignment: .leading, spacing: 6) {
                Text(record.finishedAt.formatted()).font(.headline)
                Text("\(record.scope) · \(record.measurements.count) / \(record.requestedCount ?? record.measurements.count) locations · \(record.complete ? "Completed" : "Incomplete")")
                if let reason = record.stopReason { Text(reason).font(.caption).foregroundStyle(Color.attention) }
                DisclosureGroup("Scan coverage and limits") { ForEach(Array(record.discoveryNotes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                Text(record.legacySource == nil ? "Append-only record · \(record.id)" : "Imported copy; original SpaceCheck history preserved").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }
    }
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if model.discovering { HStack { ProgressView().controlSize(.small); Text(model.progress).font(.caption).textSelection(.enabled) } }
            if model.running { ProgressView(value: Double(model.completed), total: Double(max(model.targetCount, 1))); Text("\(model.completed)/\(model.targetCount) · \(model.progress)").font(.caption) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(Color.attention).textSelection(.enabled) }
            HStack {
                Toggle("Check priority locations daily while open", isOn: Binding(get: { model.preferences.dailyWhileOpen }, set: { model.setDaily($0) })).toggleStyle(.checkbox)
                Spacer()
                Text("\(model.discovery.profiles.count) known/selected locations · \(model.records.count) preserved scans").font(.caption).foregroundStyle(.secondary)
            }
            if model.section == .locations { Text("Coverage: known tool locations plus folders you add. Sizes are estimates, never a promise of reclaimable space.").font(.caption2).foregroundStyle(.secondary) }
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
            Toggle("Watch this location", isOn: $value.watched)
            Toggle("Recurring area to review", isOn: $value.recurring)
            Toggle("This growth is expected", isOn: $value.expected)
            Toggle("Review later", isOn: Binding(get: { value.reviewAfter != nil }, set: { value.reviewAfter = $0 ? Date().addingTimeInterval(86400) : nil }))
            if value.reviewAfter != nil {
                DatePicker("Review after", selection: Binding(get: { value.reviewAfter ?? Date() }, set: { value.reviewAfter = $0 }), displayedComponents: [.date, .hourAndMinute])
                Text("Until this time, the location stays out of Growing, Candidates and priority checks. Manual scans remain available.").font(.caption).foregroundStyle(.secondary)
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
    var body: some Scene { WindowGroup("Context Cleaner") { MainView() }.defaultSize(width: 1480, height: 920) }
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
            Text("Priority checks: 10 seconds or 100,000 entries per location, up to 90 seconds of measurement per pass. Manual scans: 120 seconds or 1,000,000 entries per location, up to 15 minutes per pass. A slow filesystem call can delay stopping.").font(.caption).foregroundStyle(.secondary)
            Text("An incomplete scan never supplies a complete size. Choose a smaller child folder to investigate large locations. Daily checks run only while this app is open and record attempts so failures do not trigger rapid retries.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal this app in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 560)
    }
}
