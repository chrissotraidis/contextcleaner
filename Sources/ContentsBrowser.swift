import SwiftUI

struct SnapshotContentsView: View {
    let detail: FolderContents
    let tint: Color
    let busy: Bool
    let measure: (ChildSummary) -> Void
    @State private var query = ""
    @State private var order = "Largest"
    @State private var foldersOnly = false
    @State private var shown = 30
    @State private var allTypes = false
    var matching: [ChildSummary] {
        detail.children.filter { (!foldersOnly || $0.directory) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }.sorted {
            if order == "Name" { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if $0.bytes == $1.bytes { return $0.name < $1.name }
            return $0.bytes > $1.bytes
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File types at this observation").font(.headline)
            Text("Based on extensions, not file contents. Folder metadata is excluded from these type totals.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(detail.fileTypes.prefix(allTypes ? detail.fileTypes.count : 12))) { type in
                VStack(spacing: 5) {
                    HStack { Text(type.kind); Spacer(); Text("\(type.files.formatted()) files · \(byteLabel(type.bytes))").monospacedDigit() }.font(.caption)
                    ProportionBar(value: Double(type.bytes) / Double(max(detail.fileTypes.map(\.bytes).max() ?? 1, 1)), tint: tint)
                }
            }
            if detail.fileTypes.count > 12 {
                Button(allTypes ? "Show fewer file types" : "Show all \(detail.fileTypes.count) file types") { allTypes.toggle() }.font(.caption)
            }
            Divider()
            Text("Measured children").font(.headline)
            Text("\(detail.children.count) retained of \(detail.listedChildren) listed entries. Scans retain up to \(detail.retainedLimit) names alphabetically. \(detail.omittedEntries) entries skipped for exclusions, links or other volumes.").font(.caption).foregroundStyle(.secondary)
            TextField("Find a retained child", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Find a retained child")
            HStack {
                Picker("Sort children", selection: $order) { Text("Largest").tag("Largest"); Text("Name").tag("Name") }.labelsHidden().frame(maxWidth: 150).accessibilityLabel("Sort children")
                Toggle("Folders only", isOn: $foldersOnly).toggleStyle(.checkbox)
            }
            HStack {
                Text("Showing \(min(shown, matching.count)) of \(matching.count) retained matches").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if shown < matching.count { Button("Show more") { shown += 30 }.font(.caption).accessibilityLabel("Show 30 more retained children") }
            }
            if matching.isEmpty {
                Text("No retained entries match. Search covers this saved breakdown, not every item on disk.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(matching.prefix(shown))) { child in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        Image(systemName: child.directory ? "folder" : "doc").foregroundStyle(tint).accessibilityHidden(true)
                        Button(child.name) { measure(child) }.buttonStyle(.link).lineLimit(2).disabled(busy)
                            .accessibilityLabel("Measure \(child.directory ? "folder" : "file") \(child.name)")
                            .help("Measure this location and open its history")
                        Spacer(minLength: 6)
                        Text(byteLabel(child.bytes)).font(.caption).monospacedDigit()
                    }
                    ProportionBar(value: Double(child.bytes) / Double(max(detail.children.map(\.bytes).max() ?? 1, 1)), tint: tint)
                }.padding(.vertical, 2)
            }
            if shown < matching.count { Button("Show next \(min(30, matching.count - shown)) entries") { shown += 30 } }
            if shown > 30 { Button("Show fewer entries") { shown = 30 }.font(.caption) }
        }
        .onChange(of: query) { _, _ in shown = 30 }
        .onChange(of: order) { _, _ in shown = 30 }
        .onChange(of: foldersOnly) { _, _ in shown = 30 }
    }
}

struct ChildEventsView: View {
    let events: [ChildChange]
    @State private var query = ""
    @State private var shown = 30
    var matching: [ChildChange] { events.filter { query.isEmpty || ($0.name + " " + $0.event).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Changes since the previous comparable scan").font(.headline)
            if events.isEmpty { Text("No changes in retained child sizes, identities or modification metadata.").font(.caption) }
            else {
                TextField("Find a child or change", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Find a child or change")
                Text("Showing \(min(shown, matching.count)) of \(matching.count) matching changes").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(matching.prefix(shown))) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.name).fontWeight(.medium).textSelection(.enabled)
                        Text(event.event + (event.delta.map { " · " + ($0 > 0 ? "+" : $0 < 0 ? "−" : "") + byteLabel(abs($0)) } ?? "")).foregroundStyle(.secondary)
                    }.font(.caption)
                }
                if matching.isEmpty { Text("No changes match this search.").font(.caption) }
                if shown < matching.count { Button("Show more changes") { shown += 30 } }
            }
            Text("Observations cannot establish what happened between scans. A matching filesystem identity only suggests a rename; identifiers may be reused.").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: query) { _, _ in shown = 30 }
    }
}
