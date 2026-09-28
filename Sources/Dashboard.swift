import SwiftUI
import Charts
import AppKit


extension FolderCategory {
    var symbol: String {
        switch self {
        case .packageCache: return "shippingbox"
        case .installCache: return "iphone.and.arrow.forward"
        case .buildOutput: return "hammer"
        case .debugSymbols: return "ladybug"
        case .simulator: return "iphone.gen3.radiowaves.left.and.right"
        case .workspace: return "folder.badge.gearshape"
        case .backup: return "externaldrive.badge.timemachine"
        case .history: return "text.bubble"
        case .model: return "cpu"
        case .appData: return "app.dashed"
        case .download: return "arrow.down.circle"
        case .unknown: return "questionmark.folder"
        }
    }
    var shortPurpose: String {
        switch self {
        case .simulator: return "Virtual iPhones and iPads used to test apps. Each device can hold installed apps, databases, photos and saves."
        case .workspace: return "Project working folders. Source, build results, private inputs and diagnostics can coexist here."
        case .packageCache: return "Previously downloaded dependencies, reused to make future commands faster."
        case .installCache: return "Reusable data from installing apps on physical devices."
        case .buildOutput: return "Generated compiler output and indexes. Usually reproducible, but rebuilding takes time."
        case .debugSymbols: return "Files used to debug specific devices and interpret crash reports."
        case .backup: return "Recovery copies that may hold the only version of unfinished work."
        case .history: return "Saved conversations and records of previous work."
        case .model: return "Downloaded AI models and datasets used by local tools."
        case .appData: return "Application libraries, settings, databases and saves. Size alone does not make them disposable."
        case .download: return "Downloaded installers, documents and other files. Some may be unique."
        case .unknown: return "A location whose purpose has not yet been established."
        }
    }
}
struct CapsuleLabel: View {
    var text: String; var symbol: String; var color: Color = .accentColor
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.12), in: Capsule())
    }
}
struct ProportionBar: View {
    var value: Double; var tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.12))
                Capsule().fill(tint.gradient).frame(width: geo.size.width * min(1, max(0, value.isFinite ? value : 0)))
            }
        }.frame(height: 7).accessibilityHidden(true)
    }
}
struct FolderTrend: View {
    let path: String
    let records: [ScanRecord]
    var compact = false
    @State private var selectedDate: Date?
    private var points: [HistoryPoint] { historyPoints(path, records: records) }
    private var series: [TracePoint] {
        var out: [TracePoint] = [], segment = 0, scope: String?
        for point in points {
            guard let bytes = point.bytes else { segment += 1; scope = nil; continue }
            if let scope, scope != point.scopeID { segment += 1 }; scope = point.scopeID
            out.append(TracePoint(id: point.id, date: point.date, bytes: bytes, segment: segment))
        }
        return out
    }
    private var picked: TracePoint? {
        guard let selectedDate else { return nil }
        return series.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Size over time").font(.headline)
                Spacer()
                Text("\(series.count) \(series.count == 1 ? "observation" : "observations")").font(.caption).foregroundStyle(.secondary)
            }
            if series.isEmpty {
                Text("Scan this folder to start its timeline.").foregroundStyle(.secondary)
            } else {
                Chart(series) { p in
                    LineMark(x: .value("Date", p.date), y: .value("GiB", Double(p.bytes) / 1_073_741_824), series: .value("Comparable scope", p.segment)).foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Date", p.date), y: .value("GiB", Double(p.bytes) / 1_073_741_824)).foregroundStyle(Color.accentColor).symbolSize(35)
                    if let picked, picked.id == p.id {
                        RuleMark(x: .value("Selected", picked.date)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [3]))
                    }
                }.chartXSelection(value: $selectedDate).chartYAxisLabel("GiB").frame(height: compact ? 105 : 170)
                    .accessibilityLabel("Recorded folder sizes. Gaps and changed scan scope break the line.")
                if let picked { Text("\(picked.date.formatted(date: .abbreviated, time: .shortened)) · \(byteLabel(picked.bytes))").font(.caption).monospacedDigit() }
                else { Text(series.count < 2 ? "First measurement. Rescan to see a change; earlier growth is unknown." : "Hover or drag across the chart to inspect an observation.").font(.caption).foregroundStyle(.secondary) }
                let change = growth(path, records: records)
                if let delta = change.delta, let interval = change.interval {
                    Label("\(delta > 0 ? "+" : delta < 0 ? "−" : "")\(byteLabel(abs(delta))) over \(elapsedLabel(interval))", systemImage: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal").font(.caption.weight(.semibold)).foregroundStyle(delta > 0 ? Color.growing : Color.accentColor)
                } else if series.count > 1 { Text("No comparable recent pair. Scan scope changes and failed observations break the comparison.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
struct Dashboard: View {
    @ObservedObject var model: CleanerModel
    @State private var selectedDate: Date?
    private var groups: [StorageGroup] { overviewGroups(model.latest, preferences: model.preferences) }
    private var measured: [FolderMeasurement] { model.latest.filter { $0.state == .measured && !model.preferences.excluded($0.profile.path) } }
    private var total: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    private var growthCount: Int {
        model.latest.filter { item in
            let policy = model.preferences.policy(item.profile.path), delta = growth(item.profile.path, records: model.records).delta ?? 0
            return delta > 0 && delta >= (policy.growthThresholdBytes ?? 0) && !policy.expected && (policy.reviewAfter ?? .distantPast) <= Date() && !model.preferences.excluded(item.profile.path)
        }.count
    }
    private var freeRange: ClosedRange<Double> {
        let values = freeHistory.compactMap { $0.freeBytes }.map { Double($0) / 1_073_741_824 }
        let lower = values.min() ?? 0, upper = values.max() ?? 1
        let padding = max((upper - lower) * 0.2, 1)
        return max(0, lower - padding)...(upper + padding)
    }
    private var freeHistory: [ScanRecord] { model.records.filter { $0.freeBytes != nil }.sorted { $0.finishedAt < $1.finishedAt } }
    private func show(_ category: FolderCategory? = nil) { model.categoryFilter = category; model.search = ""; model.section = .locations; model.locationFilter = .all; model.selected = nil; model.inspector = "Overview" }
    private func open(_ item: FolderMeasurement) { model.categoryFilter = nil; model.search = ""; model.selected = item.profile.path; model.inspector = "Overview"; model.section = .locations; model.locationFilter = .all }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    driveCard.frame(maxWidth: .infinity)
                    freeSpaceChart.frame(maxWidth: .infinity)
                }
                HStack(spacing: 12) {
                    metric("Locations measured", value: measured.count.formatted(), detail: "Saved observations", symbol: "folder", tint: .blue) { show() }
                    metric("Growing", value: growthCount.formatted(), detail: "Comparable baselines: \(measured.filter { growth($0.profile.path, records: model.records).delta != nil }.count)", symbol: "chart.line.uptrend.xyaxis", tint: .growing) { model.categoryFilter = nil; model.section = .locations; model.locationFilter = .growing }
                    metric("Watching", value: model.preferences.locations.filter { $0.value.watched && !model.preferences.excluded($0.key) }.count.formatted(), detail: "Your recurring checkpoints", symbol: "eye", tint: .accentColor) { model.categoryFilter = nil; model.section = .watching }
                }
                HStack(alignment: .top, spacing: 20) {
                    categories.frame(maxWidth: .infinity)
                    largest.frame(maxWidth: .infinity)
                }
                Panel(title: "How much of this Mac is understood?", symbol: "viewfinder", tint: .blue) {
                    HStack(alignment: .top, spacing: 25) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(byteLabel(total)).font(.title2.weight(.semibold)).monospacedDigit()
                            Text("in measured, non-nested locations").font(.caption).foregroundStyle(.secondary)
                        }.frame(width: 230, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scans cover recognized development and cache locations, plus folders you select. This is not a whole-disk scan.")
                            Text("Category totals use each location's latest saved measurement, which can be from different times. Parent folders include their children. APFS shared blocks mean these estimates are not reclaimable-space totals.").font(.caption).foregroundStyle(.secondary)
                            HStack { Button("Browse locations") { show() }; Button("Add a location…") { model.addRoot() }.disabled(model.running || model.inspecting || model.discovering) }
                        }
                    }
                }
            }.padding(22)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func metric(_ title: String, value: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint).frame(width: 44, height: 44).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel("\(title): \(value). \(detail)")
    }
    private var driveCard: some View {
        Panel(title: "Your Mac’s storage", symbol: "internaldrive", tint: .accentColor) {
            if let volume = model.volume {
                HStack(spacing: 22) {
                    ZStack {
                        Chart {
                            SectorMark(angle: .value("Used", volume.used), innerRadius: .ratio(0.78), angularInset: 2).foregroundStyle(Color.indigo.gradient)
                            SectorMark(angle: .value("Free", volume.free), innerRadius: .ratio(0.78), angularInset: 2).foregroundStyle(Color.accentColor.gradient)
                        }.chartLegend(.hidden)
                        VStack(spacing: 3) { Text((Double(volume.used) / Double(volume.total)).formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 27, weight: .semibold, design: .rounded)); Text("used").font(.caption).foregroundStyle(.secondary) }
                    }.frame(width: 148, height: 148).accessibilityElement(children: .ignore).accessibilityLabel("\(byteLabel(volume.used)) used of \(byteLabel(volume.total)) total")
                    VStack(alignment: .leading, spacing: 10) {
                        Text(byteLabel(volume.free)).font(.system(size: 30, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                        Text("available on your home volume").font(.caption).foregroundStyle(.secondary)
                        Label("\(byteLabel(volume.used)) used", systemImage: "circle.fill").foregroundStyle(.indigo).font(.caption)
                        Label("\(byteLabel(volume.total)) total", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack { Text("Capacity checked \(volume.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Refresh", systemImage: "arrow.clockwise") { model.refreshVolume() }.buttonStyle(.borderless) }
                Text("Volume capacity is separate from folder scanning. Sizes use binary units; APFS shares capacity across volumes.").font(.caption2).foregroundStyle(.secondary)
            } else { Text("Volume capacity is unavailable."); Button("Try again") { model.refreshVolume() } }
        }
    }
    private var freeSpaceChart: some View {
        Panel(title: "Free space over time", symbol: "chart.xyaxis.line", tint: .accentColor) {
            if let last = freeHistory.last, let bytes = last.freeBytes {
                HStack(alignment: .firstTextBaseline) { Text(byteLabel(bytes)).font(.title2.weight(.semibold)); Text("at last scan").font(.caption).foregroundStyle(.secondary) }
                Chart(freeHistory) { record in
                    LineMark(x: .value("Date", record.finishedAt), y: .value("Free GiB", Double(record.freeBytes ?? 0) / 1_073_741_824)).foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Date", record.finishedAt), y: .value("Free GiB", Double(record.freeBytes ?? 0) / 1_073_741_824)).foregroundStyle(Color.accentColor)
                    if let selectedDate, let picked = freeHistory.min(by: { abs($0.finishedAt.timeIntervalSince(selectedDate)) < abs($1.finishedAt.timeIntervalSince(selectedDate)) }), picked.id == record.id {
                        RuleMark(x: .value("Selected", picked.finishedAt)).foregroundStyle(.secondary).annotation(position: .top, alignment: .leading) { Text(byteLabel(picked.freeBytes ?? 0)).font(.caption).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)) }
                    }
                }.chartXSelection(value: $selectedDate).chartYScale(domain: freeRange).chartYAxisLabel("GiB").frame(height: 122)
                Text("\(freeHistory.count) scan-time observations · Last \(last.finishedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                Text("Zoomed vertical scale. Changes include all disk activity; their cause is not recorded.").font(.caption2).foregroundStyle(.secondary)
            } else { ContentUnavailableView("History starts with a scan", systemImage: "chart.xyaxis.line", description: Text("Each completed observation adds a real point. No earlier data is invented.")) }
        }
    }
    private var categories: some View {
        Panel(title: "Where the measured space goes", symbol: "square.stack.3d.up", tint: .purple) {
            if groups.isEmpty { Text("Scan a location to start mapping its storage.").foregroundStyle(.secondary) }
            ForEach(groups) { group in
                Button { show(group.category) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Label(group.category.rawValue, systemImage: group.category.symbol).foregroundStyle(group.category.tint); Spacer(); Text(byteLabel(group.bytes)).fontWeight(.semibold).monospacedDigit(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                        ProportionBar(value: Double(group.bytes) / Double(max(groups.first?.bytes ?? 1, 1)), tint: group.category.tint)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain).help(group.category.shortPurpose)
            }
            Text("Latest saved sizes, with nested folders counted once. Click a category to explore its locations.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var largest: some View {
        Panel(title: "Start with the biggest locations", symbol: "magnifyingglass", tint: .blue) {
            ForEach(measured.sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }.prefix(6)) { item in
                Button { open(item) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.profile.category.symbol).font(.title3).foregroundStyle(item.profile.category.tint).frame(width: 32, height: 32).background(item.profile.category.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) { Text(item.profile.name).fontWeight(.medium).lineLimit(2); Text(item.profile.project ?? item.profile.associatedApp).font(.caption).foregroundStyle(.secondary); Text(item.observedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary) }
                        Spacer(); Text(item.allocatedBytes.map(byteLabel) ?? "—").monospacedDigit(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Text("Large does not mean unused. Open a location to understand its purpose and the cost of manual removal.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
