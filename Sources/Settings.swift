import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            ScanningSettings(model: model).tabItem { Label("Scanning", systemImage: "magnifyingglass") }
            CoverageSettings(model: model).tabItem { Label("Coverage", systemImage: "folder.badge.gearshape") }
        }.frame(width: 620, height: 560)
    }
}

struct GeneralSettings: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(get: { model.preferences.appearance ?? "System" }, set: { model.setAppearance($0) })) {
                    Text("Match System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
                }.pickerStyle(.segmented)
            }
            Section {
                Picker("Check watched and growing folders", selection: Binding(get: { model.preferences.effectiveSchedule }, set: { value in model.updatePreferences { $0.schedule = value; $0.dailyWhileOpen = value != "off" } })) {
                    Text("Off").tag("off"); Text("Daily").tag("daily"); Text("Weekly").tag("weekly")
                }
                if model.preferences.effectiveSchedule != "off" {
                    Stepper("Up to \(model.preferences.effectivePriorityCount) folders each time", value: Binding(get: { model.preferences.effectivePriorityCount }, set: { value in model.updatePreferences { $0.priorityCount = value } }), in: 4...48, step: 4)
                }
            } header: { Text("Scheduled checks") } footer: {
                Text("Only while Context Cleaner is open. Watched and growing folders go first." + (model.preferences.lastScheduledAttempt.map { " Last check \($0.formatted(.relative(presentation: .named)))." } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Label("Context Cleaner never deletes files. You decide, in Finder.", systemImage: "lock.shield")
            } footer: {
                Text("\(model.records.count) \(model.records.count == 1 ? "scan" : "scans") and \(model.capacity.count) disk \(model.capacity.count == 1 ? "reading" : "readings") are saved on this Mac. Nothing is ever pruned.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct ScanningSettings: View {
    @ObservedObject var model: CleanerModel
    @State private var showingAccessHelp = false
    @State private var advanced = false
    var body: some View {
        Form {
            Section {
                Label("A scan reads folder sizes and dates. It never opens, changes or deletes files.", systemImage: "magnifyingglass")
                HStack {
                    Button("Scan Watchlist") { model.scan(watchedOnly: true) }
                    Button("Look for New Folders") { model.discover() }
                    Spacer()
                    Button("About Access…") { showingAccessHelp = true }
                }.disabled(model.running || model.inspecting || model.discovering)
            } footer: {
                Text(model.preferences.lastDiscovery.map { "Last looked for new folders \($0.formatted(.relative(presentation: .named)))." } ?? "Scan Folders also looks for new folders.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    Picker("Time per folder", selection: Binding(get: { model.preferences.perLocationSeconds ?? 120 }, set: { value in model.updatePreferences { $0.perLocationSeconds = value } })) {
                        Text("30 seconds").tag(30); Text("1 minute").tag(60); Text("2 minutes (default)").tag(120); Text("5 minutes").tag(300); Text("15 minutes").tag(900)
                    }
                    Picker("Files per folder", selection: Binding(get: { model.preferences.perLocationEntries ?? 1_000_000 }, set: { value in model.updatePreferences { $0.perLocationEntries = value } })) {
                        Text("100 thousand").tag(100_000); Text("500 thousand").tag(500_000); Text("1 million (default)").tag(1_000_000); Text("5 million").tag(5_000_000)
                    }
                    Text("A folder that hits a limit keeps its earlier size and appears in Couldn't Scan.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
    }
}

enum CoverageFilter: String, CaseIterable, Identifiable {
    case all = "All", present = "On this Mac", off = "Turned off"
    var id: String { rawValue }
}

struct CoverageSettings: View {
    @ObservedObject var model: CleanerModel
    @State private var query = ""
    @State private var filter = CoverageFilter.all
    @State private var presence: [String: CoveragePresence] = [:]
    @State private var openGroups: Set<String> = []
    @State private var openRows: Set<String> = []
    private var busy: Bool { model.running || model.inspecting }
    private func matches(_ entry: CoverageEntry) -> Bool {
        let path = entry.path(home: model.home)
        guard query.isEmpty || (entry.writer + " " + entry.name + " " + entry.relativePath + " " + entry.writes).localizedCaseInsensitiveContains(query) else { return false }
        switch filter {
        case .all: return true
        case .present: return presence[entry.id] == .present
        case .off: return model.preferences.excluded(path)
        }
    }
    var body: some View {
        let measured = model.latest.filter { $0.state == .measured }
        let sizes = Dictionary(uniqueKeysWithValues: Coverage.entries.map { entry in
            (entry.id, uniqueAllocatedTotal(measured.filter { containsPath(entry.path(home: model.home), $0.profile.path) }))
        })
        VStack(spacing: 0) {
            HStack {
                TextField("Search apps or paths", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Picker("Show", selection: $filter) { ForEach(CoverageFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
            Text("Where Context Cleaner looks. Turn off anything you don't want scanned.").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            Form {
                ForEach(CoverageGroup.allCases) { group in
                    let entries = Coverage.entries.filter { $0.group == group && matches($0) }
                    if !entries.isEmpty {
                        let open = openGroups.contains(group.id) || !query.isEmpty
                        Section {
                            groupHeader(group, entries: Coverage.entries.filter { $0.group == group }, open: open)
                            if open { ForEach(entries) { entry in row(entry, size: sizes[entry.id] ?? 0) } }
                        }
                    }
                }
                if filter != .present && (query.isEmpty || "your folders".localizedCaseInsensitiveContains(query)) { yourFolders }
                if query.isEmpty && filter == .all {
                    Section {
                        DisclosureGroup("What's never scanned") {
                            ForEach(Coverage.notScanned, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                        }
                    } footer: { Text("Context Cleaner looks where apps pile up data. It isn't a whole-disk scanner, so its totals never equal your used space.").font(.caption).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped)
        }
        .task {
            let home = model.home
            presence = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: Coverage.entries.map { ($0.id, Coverage.presence($0, home: home)) })
            }.value
        }
    }
    /// An accessible expand button beside the group's switch.
    private func groupHeader(_ group: CoverageGroup, entries: [CoverageEntry], open: Bool) -> some View {
        let paths = entries.map { $0.path(home: model.home) }
        let on = paths.filter { !model.preferences.excluded($0) }.count
        let total = uniqueAllocatedTotal(model.latest.filter { item in item.state == .measured && paths.contains { containsPath($0, item.profile.path) } })
        let summary = "\(on) of \(entries.count) on" + (total > 0 ? " · \(byteLabel(total))" : "")
        return HStack(spacing: 10) {
            Button { if openGroups.contains(group.id) { openGroups.remove(group.id) } else { openGroups.insert(group.id) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary).frame(width: 12)
                    Image(systemName: group.symbol).foregroundStyle(Color.accentColor).frame(width: 20)
                    Text(group.rawValue).font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(group.rawValue), \(summary)").accessibilityHint(open ? "Hides its locations" : "Shows its locations")
            Toggle(group.rawValue, isOn: Binding(get: { on > 0 }, set: { value in
                model.updatePreferences { prefs in
                    for path in paths { var policy = prefs.policy(path); policy.excluded = !value; prefs.locations[normalized(path)] = policy }
                }
            })).toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(busy).help(on > 0 ? "Turn off everything in \(group.rawValue)" : "Turn on everything in \(group.rawValue)")
        }
    }
    private func row(_ entry: CoverageEntry, size: Int64) -> some View {
        let path = entry.path(home: model.home)
        let status = presence[entry.id]
        let open = openRows.contains(entry.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button { if open { openRows.remove(entry.id) } else { openRows.insert(entry.id) } } label: {
                    Image(systemName: "chevron.right").font(.caption).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary).frame(width: 12)
                }.buttonStyle(.plain).accessibilityLabel(open ? "Hide details" : "Show details")
                Image(systemName: entry.category.symbol).foregroundStyle(entry.category.tint).frame(width: 18).accessibilityHidden(true)
                Text(entry.writer == "You" ? entry.name : entry.writer == "Your projects" ? "GitHub · " + entry.name : entry.writer + " · " + entry.name).font(.callout).lineLimit(1)
                Spacer()
                Text(status == .missing ? "Not on this Mac" : status == .unavailable ? "Couldn't check" : size > 0 ? byteLabel(size) : status == .present ? "On this Mac" : "…")
                    .font(.caption).monospacedDigit().foregroundStyle(status == .unavailable ? Color.attention : .secondary)
                Toggle(entry.name, isOn: Binding(get: { !model.preferences.excluded(path) }, set: { on in model.policy(path) { $0.excluded = !on } }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(busy)
            }
            if open {
                Text(entry.writes + (entry.kind == .folder ? "" : " Each " + (entry.kind == .children ? "subfolder" : "project's build folder") + " is listed on its own.")).font(.caption).foregroundStyle(.secondary).padding(.leading, 40)
                Text("~/" + entry.relativePath).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary).padding(.leading, 40)
            }
        }.help("~/" + entry.relativePath + "\n" + entry.writes).accessibilityElement(children: .contain).accessibilityLabel(entry.writer + " " + entry.name)
    }
    private var yourFolders: some View {
        let catalog = Set(Coverage.entries.map { $0.path(home: model.home) })
        let others = model.preferences.locations.filter { $0.value.excluded && !catalog.contains($0.key) && !model.preferences.customRoots.contains($0.key) }.map(\.key).sorted()
        return Section {
            DisclosureGroup(isExpanded: Binding(get: { openGroups.contains("mine") || filter == .off }, set: { if $0 { openGroups.insert("mine") } else { openGroups.remove("mine") } })) {
                ForEach(model.preferences.customRoots.filter { filter != .off || model.preferences.excluded($0) }, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 18)
                        Text(model.displayName(path)).font(.callout).lineLimit(1).help(path)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.controlSize(.small)
                        Toggle(path, isOn: Binding(get: { !model.preferences.excluded(path) }, set: { on in model.policy(path) { $0.excluded = !on } })).toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(busy)
                    }
                }
                ForEach(others, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.badge.minus").foregroundStyle(.secondary).frame(width: 18)
                        Text(model.displayName(path)).font(.callout).lineLimit(1).help(path)
                        Text("turned off from Folders").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Turn On") { model.policy(path) { $0.excluded = false } }.controlSize(.small).disabled(busy)
                    }
                }
                Button("Add Folder…") { model.addRoot() }.disabled(model.running || model.inspecting || model.discovering)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle").foregroundStyle(Color.accentColor).frame(width: 20).accessibilityHidden(true)
                    Text("Your folders").font(.headline)
                    Text("\(model.preferences.customRoots.count) added" + (others.isEmpty ? "" : " · \(others.count) turned off")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ScanPlanView: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.dismiss) private var dismiss
    private var included: [CoverageEntry] { Coverage.entries.filter { !model.preferences.excluded($0.path(home: model.home)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Scan your folders", systemImage: "magnifyingglass").font(.title2.weight(.semibold))
            Text("Reads how big each folder is. Nothing is opened, changed or deleted.").font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CoverageGroup.allCases) { group in
                    let writers = Array(Set(included.filter { $0.group == group }.map { $0.writer == "You" ? "Downloads" : $0.writer == "Your projects" ? "GitHub projects" : $0.writer })).sorted()
                    if !writers.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: group.symbol).foregroundStyle(Color.accentColor).frame(width: 18).accessibilityHidden(true)
                            Text(group.rawValue).font(.headline).frame(width: 150, alignment: .leading)
                            Text(writers.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                let added = model.preferences.customRoots.filter { !model.preferences.excluded($0) }
                if !added.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "person.crop.circle").foregroundStyle(Color.accentColor).frame(width: 18).accessibilityHidden(true)
                        Text("Your folders").font(.headline).frame(width: 150, alignment: .leading)
                        Text(added.map { model.displayName($0) }.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                DisclosureGroup("Exact paths") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(included) { entry in Text("~/" + entry.relativePath).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            ForEach(model.preferences.customRoots.filter { !model.preferences.excluded($0) }, id: \.self) { path in Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 140)
                }.font(.callout)
            }.padding(16).background(.background.secondary)
            Text("Only these places, not your whole disk. Big folders can take a few minutes, and you can stop at any time.").font(.caption).foregroundStyle(.secondary)
            HStack {
                SettingsLink { Text("Change What's Scanned…") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start Scan", systemImage: "magnifyingglass") { model.showingScanPlan = false; model.scan() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.running || model.inspecting || model.discovering || model.store == nil)
            }
        }.padding(24).frame(width: 560)
    }
}
