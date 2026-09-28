import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            ScanningSettings(model: model).tabItem { Label("Scanning", systemImage: "arrow.clockwise") }
            CoverageSettings(model: model).tabItem { Label("Coverage", systemImage: "folder.badge.gearshape") }
        }.frame(width: 600, height: 620).padding(.bottom, 8)
    }
}

struct GeneralSettings: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        Form {
            Picker("Appearance", selection: Binding(get: { model.preferences.appearance ?? "System" }, set: { model.setAppearance($0) })) {
                Text("Match System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
            }.pickerStyle(.segmented)
            LabeledContent("Units") { Text("Binary (GiB), matching Finder's size calculations for APFS volumes.") .foregroundStyle(.secondary) }
            LabeledContent("History") { Text("\(model.records.count) saved scans · \(model.discovery.profiles.count) known locations").foregroundStyle(.secondary) }
            Section {
                Text("Context Cleaner never deletes files. You decide, in Finder.").font(.callout)
                Text("Scans read folder metadata only. Every scan and preference is appended to its own file; nothing is pruned.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(.top, 4)
    }
}

struct ScanningSettings: View {
    @ObservedObject var model: CleanerModel
    @State private var showingAccessHelp = false
    var body: some View {
        Form {
            Section("Scheduled checks") {
                Picker("Check priority locations", selection: Binding(get: { model.preferences.effectiveSchedule }, set: { value in model.updatePreferences { $0.schedule = value; $0.dailyWhileOpen = value != "off" } })) {
                    Text("Off").tag("off"); Text("Daily while open").tag("daily"); Text("Weekly while open").tag("weekly")
                }
                Stepper("Locations per check: \(model.preferences.effectivePriorityCount)", value: Binding(get: { model.preferences.effectivePriorityCount }, set: { value in model.updatePreferences { $0.priorityCount = value } }), in: 4...48, step: 4)
                Text("Checks run only while the app is open. Watched and growing locations go first, then the oldest measurements. Each attempt is recorded before it starts, so a failed check does not retry every few minutes.").font(.caption).foregroundStyle(.secondary)
                if let last = model.preferences.lastScheduledAttempt { Text("Last attempt \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Allowances for Scan Now") {
                Picker("Time per location", selection: Binding(get: { model.preferences.perLocationSeconds ?? 120 }, set: { value in model.updatePreferences { $0.perLocationSeconds = value } })) {
                    Text("30 seconds").tag(30); Text("1 minute").tag(60); Text("2 minutes").tag(120); Text("5 minutes").tag(300); Text("15 minutes").tag(900)
                }
                Picker("Entries per location", selection: Binding(get: { model.preferences.perLocationEntries ?? 1_000_000 }, set: { value in model.updatePreferences { $0.perLocationEntries = value } })) {
                    Text("100 thousand").tag(100_000); Text("500 thousand").tag(500_000); Text("1 million").tag(1_000_000); Text("5 million").tag(5_000_000)
                }
                Text("When a location exceeds its allowance the scan stops for that location, withholds the partial size and lists it under Needs Attention. Measure a smaller child folder instead.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Now") {
                HStack {
                    Button("Scan Watched Locations") { model.scan(watchedOnly: true) }
                    Button("Rediscover Locations") { model.discover() }
                    Spacer()
                    Button("About access…") { showingAccessHelp = true }
                }.disabled(model.running || model.inspecting || model.discovering)
                if let last = model.preferences.lastDiscovery { Text("Locations were last rediscovered \(last.formatted(date: .abbreviated, time: .shortened)). Rediscovery also runs with Scan Now once a week.").font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).padding(.top, 4)
        .sheet(isPresented: $showingAccessHelp) { AccessHelp() }
    }
}

struct CoverageSettings: View {
    @ObservedObject var model: CleanerModel
    @State private var query = ""
    var body: some View {
        Form {
            Section {
                TextField("Filter by tool or path", text: $query)
                Text("Every place Context Cleaner knows a tool writes to. Present means the folder exists on this Mac right now. Turn a location off to exclude it and everything inside it from scanning.").font(.caption).foregroundStyle(.secondary)
            }
            let groups = Dictionary(grouping: Coverage.entries.filter { query.isEmpty || ($0.writer + " " + $0.relativePath + " " + $0.writes).localizedCaseInsensitiveContains(query) }, by: \.writer)
            ForEach(groups.keys.sorted { a, b in a == "You" ? false : b == "You" ? true : a.localizedStandardCompare(b) == .orderedAscending }, id: \.self) { writer in
                Section(writer) {
                    ForEach(groups[writer]!) { entry in
                        let path = entry.path(home: model.home)
                        let present = Coverage.presence(entry, home: model.home)
                        Toggle(isOn: Binding(get: { !model.preferences.excluded(path) }, set: { on in model.policy(path) { $0.excluded = !on } })) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: entry.category.symbol).foregroundStyle(entry.category.tint).accessibilityHidden(true)
                                    Text("~/" + entry.relativePath).font(.callout).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(present ? "Present" : "Not on this Mac").font(.caption).foregroundStyle(present ? Color.stable : .secondary)
                                }
                                Text(entry.writes + (entry.kind == .folder ? "" : " Measured as: " + entry.kind.rawValue.lowercased() + ".")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.switch).disabled(model.running || model.inspecting)
                    }
                }
            }
            Section("Folders you added") {
                if model.preferences.customRoots.isEmpty { Text("None yet. Added folders are measured with every Scan Now.").foregroundStyle(.secondary) }
                ForEach(model.preferences.customRoots, id: \.self) { path in
                    HStack { Text(path).font(.callout).lineLimit(1).truncationMode(.middle); Spacer(); Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
                }
                Button("Add Folder…") { model.addRoot() }.disabled(model.running || model.inspecting || model.discovering)
            }
            Section("Other exclusions") {
                let catalog = Set(Coverage.entries.map { $0.path(home: model.home) })
                let excluded = model.preferences.locations.filter { $0.value.excluded && !catalog.contains($0.key) }.map(\.key).sorted()
                if excluded.isEmpty { Text("None. Right-click any location to exclude it.").foregroundStyle(.secondary) }
                ForEach(excluded, id: \.self) { path in
                    HStack { Text(path).font(.callout).lineLimit(1).truncationMode(.middle); Spacer(); Button("Include Again") { model.policy(path) { $0.excluded = false } } }
                }
            }
            Section("Not scanned") {
                ForEach(Coverage.notScanned, id: \.self) { Text($0).font(.callout) }
                Text("Context Cleaner is not a whole-disk scanner. It measures the places where tools accumulate data, so the totals here never equal your used space.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(.top, 4)
    }
}
