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
    @State private var fullDiskAccess = hasFullDiskAccess()
    @State private var showingAccessHelp = false
    var body: some View {
        let schedule = model.preferences.effectiveSchedule
        let busy = model.running || model.inspecting || model.discovering
        Form {
            Section {
                Picker(selection: Binding(get: { schedule }, set: { value in model.updatePreferences { $0.schedule = value; $0.dailyWhileOpen = value != "off" } })) {
                    Text("Off").tag("off"); Text("Daily").tag("daily"); Text("Weekly").tag("weekly")
                } label: { Label("Check folders", systemImage: "calendar.badge.clock") }
                if schedule != "off" {
                    Stepper("Up to \(model.preferences.effectivePriorityCount) folders each time", value: Binding(get: { model.preferences.effectivePriorityCount }, set: { value in model.updatePreferences { $0.priorityCount = value } }), in: 4...48, step: 4)
                }
                LabeledContent("Last check") {
                    HStack(spacing: 10) {
                        Text(model.preferences.lastScheduledAttempt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never").foregroundStyle(.secondary)
                        Button("Check Now") { model.runScheduledCheck() }.disabled(busy)
                    }
                }
                if schedule != "off", let next = ScanPlanner.nextCheck(model.preferences) {
                    LabeledContent("Next check") { Text(next <= Date() ? "Within 5 minutes" : next.formatted(.relative(presentation: .named))).foregroundStyle(.secondary) }
                }
            } header: { Text("Scheduled checks") } footer: {
                Text("A quick check of your watched and growing folders first, then the ones checked longest ago, so sizes stay current between full scans. It runs only while Context Cleaner is open, and reads sizes only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    HStack(spacing: 10) {
                        if !fullDiskAccess {
                            Button("Open Settings") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) } }
                        }
                        Button("Check Again") { fullDiskAccess = hasFullDiskAccess(); model.refreshTrash() }
                    }
                } label: {
                    Label { VStack(alignment: .leading, spacing: 2) {
                        Text(fullDiskAccess ? "Full Disk Access is on" : "Full Disk Access is off")
                        Text(fullDiskAccess ? "Scans read every place without asking, and the Trash's size shows." : "macOS asks before reading other apps' data and your Documents, and the Trash's size can't be read.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } } icon: { Image(systemName: fullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield").foregroundStyle(fullDiskAccess ? Color.stable : Color.caution) }
                }
                Button("How It Works…") { showingAccessHelp = true }.buttonStyle(.link)
            } header: { Text("Permission") } footer: {
                Text("Optional. Context Cleaner only reads sizes and dates either way. After turning it on in System Settings, quit and reopen Context Cleaner.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(selection: Binding(get: { model.preferences.appearance ?? "System" }, set: { model.setAppearance($0) })) {
                    Text("Match System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
                } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }.pickerStyle(.segmented)
            } footer: {
                Text("Context Cleaner never deletes files; you choose what goes to the Trash. \(model.records.count) \(model.records.count == 1 ? "scan" : "scans") and \(model.capacity.count) disk \(model.capacity.count == 1 ? "reading" : "readings") are saved on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fullDiskAccess = hasFullDiskAccess() }
    }
}

struct ScanningSettings: View {
    @ObservedObject var model: CleanerModel
    @State private var showingAccessHelp = false
    @State private var advanced = false
    private var busy: Bool { model.running || model.inspecting || model.discovering }
    private func action(_ title: String, _ detail: String, symbol: String, button: String, disabled: Bool = false, _ run: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(button, action: run).disabled(busy || disabled)
        }.padding(.vertical, 2)
    }
    var body: some View {
        let lastFull = model.records.last(where: { $0.measurements.count >= 20 })
        let watched = model.preferences.locations.filter { $0.value.isWatched && !model.preferences.excluded($0.key) }.count
        Form {
            Section {
                action("Full scan", "Measures every place in Coverage and looks for new folders. " + (lastFull.map { "Last one \($0.finishedAt.formatted(.relative(presentation: .named))), took \(elapsedLabel($0.finishedAt.timeIntervalSince($0.startedAt)))." } ?? "Not run yet."),
                       symbol: "magnifyingglass", button: "Scan Everything…") { model.showingScanPlan = true }
                action("Watchlist", "Only the \(watched) \(watched == 1 ? "folder" : "folders") you watch. Quick; doesn't look for new folders.",
                       symbol: "eye", button: "Scan Watchlist", disabled: watched == 0) { model.scan(watchedOnly: true) }
                action("New folders", "Finds new project, cache and device folders without measuring them. " + (model.preferences.lastDiscovery.map { "Last looked \($0.formatted(.relative(presentation: .named)))." } ?? ""),
                       symbol: "folder.badge.plus", button: "Look Now") { model.discover() }
            } header: { Text("Scan now") } footer: {
                Text("Scans only read folder sizes and dates. They never open, change or delete files.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Limits for very large folders", isExpanded: $advanced) {
                    Picker("Time per folder", selection: Binding(get: { model.preferences.perLocationSeconds ?? 300 }, set: { value in model.updatePreferences { $0.perLocationSeconds = value } })) {
                        Text("30 seconds").tag(30); Text("1 minute").tag(60); Text("2 minutes").tag(120); Text("5 minutes (default)").tag(300); Text("15 minutes").tag(900)
                    }
                    Picker("Files per folder", selection: Binding(get: { model.preferences.perLocationEntries ?? 5_000_000 }, set: { value in model.updatePreferences { $0.perLocationEntries = value } })) {
                        Text("100 thousand").tag(100_000); Text("500 thousand").tag(500_000); Text("1 million").tag(1_000_000); Text("5 million (default)").tag(5_000_000)
                    }
                    Text("A folder that hits a limit keeps its earlier size and appears in Couldn't Scan with a Scan Subfolders button.").font(.caption).foregroundStyle(.secondary)
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
        let sizes = model.coverageSizes
        // Biggest first, so the places worth a look are on top.
        let groups = CoverageGroup.allCases.sorted { model.groupSize($0) > model.groupSize($1) }
        VStack(spacing: 0) {
            HStack {
                TextField("Search apps or paths", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Picker("Show", selection: $filter) { ForEach(CoverageFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
            Text("Where Context Cleaner looks, biggest first. Turn off anything you don't want scanned.").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            Form {
                ForEach(groups) { group in
                    let entries = Coverage.entries.filter { $0.group == group && matches($0) }
                        .sorted { (sizes[$0.id] ?? 0, presence[$0.id] == .present ? 1 : 0) > (sizes[$1.id] ?? 0, presence[$1.id] == .present ? 1 : 0) }
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
                            ForEach(Coverage.notScanned, id: \.self) { Label($0, systemImage: "minus.circle").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
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
        let total = model.groupSize(group)
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
                Text(entry.writes + (entry.kind == .folder ? "" : " Each " + (entry.kind == .children ? "subfolder" : entry.kind == .workspaces ? "folder, and its build and work folders," : "project's build folder") + " is listed on its own.")).font(.caption).foregroundStyle(.secondary).padding(.leading, 40)
                Text(entry.shownPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary).padding(.leading, 40)
            }
        }.help(entry.shownPath + "\n" + entry.writes).accessibilityElement(children: .contain).accessibilityLabel(entry.writer + " " + entry.name)
    }
    private var yourFolders: some View {
        let catalog = Set(Coverage.entries.map { $0.path(home: model.home) })
        let others = model.preferences.locations.filter { $0.value.excluded && !catalog.contains($0.key) && !model.preferences.customRoots.contains($0.key) }.map(\.key).sorted()
        let open = openGroups.contains("mine") || filter == .off
        let summary = "\(model.preferences.customRoots.count) added" + (others.isEmpty ? "" : " · \(others.count) turned off from Folders")
        return Section {
            Button { if openGroups.contains("mine") { openGroups.remove("mine") } else { openGroups.insert("mine") } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary).frame(width: 12)
                    Image(systemName: "person.crop.circle").foregroundStyle(Color.accentColor).frame(width: 20)
                    Text("Your folders").font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Your folders, \(summary)").accessibilityHint(open ? "Hides your folders" : "Shows your folders")
            if open {
                ForEach(model.preferences.customRoots.filter { filter != .off || model.preferences.excluded($0) }, id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 18).padding(.leading, 22)
                        Text(model.displayName(path)).font(.callout).lineLimit(1).help(path)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.controlSize(.small)
                        Toggle(model.displayName(path), isOn: Binding(get: { !model.preferences.excluded(path) }, set: { on in model.policy(path) { $0.excluded = !on } })).toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(busy)
                    }
                }
                ForEach(others, id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.minus").foregroundStyle(.secondary).frame(width: 18).padding(.leading, 22)
                        Text(model.displayName(path)).font(.callout).lineLimit(1).help(path)
                        Text("turned off from Folders").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Turn On") { model.policy(path) { $0.excluded = false } }.controlSize(.small).disabled(busy)
                    }
                }
                Button("Add Folder…") { model.addRoot() }.disabled(model.running || model.inspecting || model.discovering)
            }
        }
    }
}

struct ScanPlanView: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.dismiss) private var dismiss
    private var included: [CoverageEntry] { Coverage.entries.filter { !model.preferences.excluded($0.path(home: model.home)) } }
    private var busy: Bool { model.running || model.inspecting || model.discovering || model.store == nil }
    var body: some View {
        let sizes = model.coverageSizes
        let groups = CoverageGroup.allCases.filter { g in included.contains { $0.group == g } }.sorted { model.groupSize($0) > model.groupSize($1) }
        let largest = Double(max(groups.map { model.groupSize($0) }.max() ?? 1, 1))
        let lastFull = model.records.last(where: { $0.measurements.count >= 20 })
        let watched = model.preferences.locations.filter { $0.value.isWatched && !model.preferences.excluded($0.key) }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Scan your folders", systemImage: "magnifyingglass").font(.title2.weight(.semibold))
                Spacer()
                Text(lastFull.map { "Last full scan \($0.finishedAt.formatted(.relative(presentation: .named))) · took \(elapsedLabel($0.finishedAt.timeIntervalSince($0.startedAt)))" } ?? "No full scan yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Measures how much space each place below takes and when it was last used, so the answers stay current. It only reads: nothing is opened, changed or deleted.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(groups) { group in
                    let entries = included.filter { $0.group == group }.sorted { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) }
                    let writers = entries.map { $0.writer == "You" ? "Downloads" : $0.writer == "Your projects" ? "GitHub projects" : $0.writer }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    let size = model.groupSize(group)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: group.symbol).foregroundStyle(Color.accentColor).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(group.rawValue).font(.headline)
                                Spacer()
                                Text(size > 0 ? byteLabel(size) : "not measured yet").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.55)).frame(width: max(2, geo.size.width * Double(size) / largest))
                            }.frame(height: 4)
                            Text(writers.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.accessibilityElement(children: .combine)
                }
                // Folders you added that are no longer on disk aren't listed; there's nothing left to scan.
                let added = model.preferences.customRoots.filter { !model.preferences.excluded($0) && !model.gone.contains($0) }
                if !added.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "person.crop.circle").foregroundStyle(Color.accentColor).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your folders").font(.headline)
                            Text(added.map { model.displayName($0) }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                DisclosureGroup("Exact paths") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(included) { entry in Text(entry.shownPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            ForEach(added, id: \.self) { path in Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 120)
                }.font(.callout)
            }.padding(16).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("What happens").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("1. Looks for new folders in these places.  2. Measures each one, four at a time.  3. Compares with the last scan and updates every answer.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Only these places, not your whole disk. macOS may ask for permission the first time; the scan waits for your answer. You can stop at any time.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                SettingsLink { Text("Change Places…") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Watchlist Only (\(watched))") { model.showingScanPlan = false; model.scan(watchedOnly: true) }
                    .disabled(busy || watched == 0).help("Scans only the folders you watch. Quick, but doesn't look for new folders.")
                Button("Start Full Scan", systemImage: "magnifyingglass") { model.showingScanPlan = false; model.scan() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(busy)
            }
        }.padding(24).frame(width: 600)
    }
}
