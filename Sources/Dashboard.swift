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
    let points: [HistoryPoint]
    let change: GrowthSummary
    var compact = false
    @State private var selectedDate: Date?
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
            } else if series.count == 1, let first = series.first {
                Text("First reading: \(byteLabel(first.bytes)) on \(first.date.formatted(date: .abbreviated, time: .shortened)).").font(.callout)
                Text("Scan this folder again to see how its size changes.").font(.caption).foregroundStyle(.secondary)
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
    @State private var showingCaveats = false
    private var groups: [StorageGroup] { model.overview.groups }
    private var measured: [FolderMeasurement] { model.overview.measuredBySize }
    private var total: Int64 { model.overview.total }
    private var readings: [FreeSpaceReading] { freeSpaceReadings(model.records, current: model.volume) }
    private func show(_ category: FolderCategory? = nil, filter: LocationFilter = .all) {
        model.categoryFilter = category; model.search = ""; model.section = .locations
        model.locationFilter = filter; model.selected = nil; model.inspector = "Overview"
    }
    private func open(_ item: FolderMeasurement) {
        show(); model.selected = item.profile.path
    }
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    if let scan = model.lastScan {
                        Text("Last scan: " + scan.folderSummary + " · " + scan.finishedAt.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
                    } else { Text("Start a scan to find your largest folders.") }
                    Spacer()
                    Button("What gets scanned?") { model.showingScanPlan = true }.buttonStyle(.link)
                }.font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    driveCard.frame(maxWidth: .infinity)
                    freeSpaceChart.frame(maxWidth: .infinity)
                }.frame(height: 214)
                HStack(spacing: 10) {
                    metric("Scanned", value: measured.count, symbol: "folder", tint: .accentColor) { show(filter: .scanned) }
                    metric("Not scanned", value: model.overview.pendingCount, symbol: "clock", tint: .secondary) { show(filter: .unscanned) }
                    metric("Growing", value: model.overview.growthCount, symbol: "chart.line.uptrend.xyaxis", tint: .growing) { show(filter: .growing) }
                    metric("Scan issues", value: model.attentionCount, symbol: "exclamationmark.triangle", tint: model.attentionCount > 0 ? .attention : .secondary) { model.categoryFilter = nil; model.search = ""; model.section = .needsAttention }
                }
                HStack(alignment: .top, spacing: 16) {
                    categories.frame(maxWidth: .infinity)
                    largest.frame(maxWidth: .infinity)
                }
            }.padding(.horizontal, 22).padding(.bottom, 14)
        }.scrollBounceBehavior(.basedOnSize)
    }
    private func metric(_ title: String, value: Int, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
                Text(value.formatted()).font(.title3.weight(.semibold)).monospacedDigit()
                Text(title).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            }.padding(10).background(.background.secondary)
        }.buttonStyle(.plain).accessibilityLabel("\(value) folders · \(title)")
    }
    private var driveCard: some View {
        Panel(title: "Storage on your Mac", symbol: "internaldrive", minimumHeight: 214) {
            if let v = model.volume {
                HStack(spacing: 18) {
                    ZStack {
                        Chart {
                            SectorMark(angle: .value("Used", v.used), innerRadius: .ratio(0.80), angularInset: 2).foregroundStyle(Color.secondary.opacity(0.22))
                            SectorMark(angle: .value("Free", v.free), innerRadius: .ratio(0.80), angularInset: 2).foregroundStyle(Color.accentColor)
                        }.chartLegend(.hidden)
                        VStack(spacing: 2) {
                            Text((Double(v.used) / Double(v.total)).formatted(.percent.precision(.fractionLength(0)))).font(.title2.weight(.semibold))
                            Text("used").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(width: 96, height: 96).accessibilityElement(children: .ignore).accessibilityLabel("\(byteLabel(v.used)) used of \(byteLabel(v.total))")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(byteLabel(v.free) + " free").font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text("of \(byteLabel(v.total)) total").font(.callout).foregroundStyle(.secondary)
                        Text("Checked \(v.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Volume containing your home folder").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refreshVolume() }.controlSize(.small).help("Check disk capacity without scanning folders")
                }
            } else { Text("Storage information is unavailable."); Button("Try Again") { model.refreshVolume() } }
        }
    }
    private var freeSpaceChart: some View {
        Panel(title: "Free space over time", symbol: "chart.xyaxis.line") {
            let points = readings
            if let first = points.first, let last = points.last, points.count > 1 {
                let change = last.bytes - first.bytes
                let picked = selectedDate.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
                Text(picked.map { byteLabel($0.bytes) + " free · " + $0.date.formatted(date: .abbreviated, time: .shortened) }
                     ?? (change == 0 ? "No change in free space" : byteLabel(abs(change)) + (change < 0 ? " less free space" : " more free space")))
                    .font(.callout.weight(.medium)).foregroundStyle(picked == nil && change < 0 ? Color.growing : .primary).lineLimit(1).minimumScaleFactor(0.8)
                Chart(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("GiB free", Double(point.bytes) / 1_073_741_824)).foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Time", point.date), y: .value("GiB free", Double(point.bytes) / 1_073_741_824)).foregroundStyle(Color.accentColor).symbolSize(point.isCurrent ? 50 : 22)
                    if let picked, picked.id == point.id { RuleMark(x: .value("Reading", point.date)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [3])) }
                }.chartXScale(domain: readingTimeRange(points)).chartXSelection(value: $selectedDate)
                    .chartYScale(domain: 0...max(50, ceil(Double(points.map(\.bytes).max() ?? 0) / 1_073_741_824 / 50) * 50))
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { location in
                                guard let frame = proxy.plotFrame else { return }
                                let plot = geometry[frame]
                                if plot.contains(location) { selectedDate = proxy.value(atX: location.x - plot.minX) }
                            }
                        }
                    }
                    .chartXAxis(.hidden).chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .chartYAxisLabel("GiB free").frame(height: 78)
                    .accessibilityLabel("\(byteLabel(first.bytes)) free on \(first.date.formatted()), \(byteLabel(last.bytes)) free on \(last.date.formatted()). Readings, not continuous monitoring.")
                HStack {
                    Text(first.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    Spacer()
                    Text(last.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                }.font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("Saved scans + latest reading · whole disk").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    if picked != nil { Button("Show change") { selectedDate = nil }.buttonStyle(.link) }
                }.font(.caption2)
            } else {
                Text("Scan a folder to start recording free-space history.").font(.callout).foregroundStyle(.secondary)
                Text("There are no earlier scan readings yet.").font(.caption)
            }
        }
    }
    private var categories: some View {
        Panel(title: "What’s taking up space", symbol: "square.stack.3d.up") {
            HStack(alignment: .firstTextBaseline) {
                Text(byteLabel(total)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("in scanned folders").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showingCaveats.toggle() } label: { Image(systemName: "info.circle") }.buttonStyle(.borderless).accessibilityLabel("About these folder totals")
                    .popover(isPresented: $showingCaveats) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Folder totals, not your entire disk").font(.headline)
                            Text("The latest saved size of each folder. A parent and its subfolders are counted once. Some sizes come from older scans.")
                            Text("Shared APFS storage means deleting a folder yourself may free less space than its listed size. These are estimates, not cleanup promises.")
                        }.padding(18).frame(width: 320)
                    }
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(groups) { group in
                        Rectangle().fill(group.category.tint).frame(width: geo.size.width * Double(group.bytes) / Double(max(total, 1)))
                            .help(group.category.displayName + " · " + byteLabel(group.bytes))
                    }
                }.clipShape(Capsule())
            }.frame(height: 12).accessibilityHidden(true)
            ForEach(groups.prefix(5)) { group in categoryRow(group) }
            if groups.count > 5 {
                Menu("\(groups.count - 5) more types") {
                    ForEach(groups.dropFirst(5)) { group in Button(group.category.displayName + " · " + byteLabel(group.bytes)) { show(group.category) } }
                }.menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading).font(.caption)
            }
            if groups.isEmpty { Text("Scan folders to see a breakdown.").foregroundStyle(.secondary) }
        }
    }
    private func categoryRow(_ group: StorageGroup) -> some View {
        Button { show(group.category) } label: {
            HStack {
                Circle().fill(group.category.tint).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(group.category.displayName)
                Spacer()
                Text(byteLabel(group.bytes)).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            }.font(.callout).contentShape(Rectangle())
        }.buttonStyle(.plain).help(group.category.shortPurpose)
    }
    private var largest: some View {
        Panel(title: "Your largest folders", symbol: "folder") {
            ForEach(measured.prefix(4)) { item in
                Button { open(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.profile.category.symbol).foregroundStyle(item.profile.category.tint).frame(width: 22).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.profile.displayName).font(.callout).lineLimit(1)
                            Text(item.profile.category.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu { LocationActions(model: model, path: item.profile.path) }
            }
            Button("See all folders") { show() }.buttonStyle(.link).font(.caption)
        }
    }
}
