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
    private var growthCount: Int { model.overview.growthCount }
    private var freeHistory: [ScanRecord] { model.records.filter { $0.freeBytes != nil }.sorted { $0.finishedAt < $1.finishedAt } }
    @State private var timeWindow: ClosedRange<Date>
    @State private var freeRange: ClosedRange<Double>
    init(model: CleanerModel) {
        self.model = model
        let window = freeSpaceWindow(at: Date())
        _timeWindow = State(initialValue: window)
        _freeRange = State(initialValue: freeSpaceRange(model.records.filter { window.contains($0.finishedAt) }.compactMap(\.freeBytes)))
    }
    private func updateChartForScan() {
        let window = freeSpaceWindow(at: Date())
        timeWindow = window
        freeRange = freeSpaceRange(freeHistory.filter { window.contains($0.finishedAt) }.compactMap(\.freeBytes), preserving: freeRange)
    }
    private func show(_ category: FolderCategory? = nil) { model.categoryFilter = category; model.search = ""; model.section = .locations; model.locationFilter = .all; model.selected = nil; model.inspector = "Overview" }
    private func open(_ item: FolderMeasurement) { model.categoryFilter = nil; model.search = ""; model.selected = item.profile.path; model.inspector = "Overview"; model.section = .locations; model.locationFilter = .all }
    var body: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 12) {
            scanStatus
            HStack(alignment: .top, spacing: 12) {
                driveCard.frame(maxWidth: .infinity)
                freeSpaceChart.frame(maxWidth: .infinity)
            }.frame(height: 172)
            HStack(spacing: 10) {
                metric("Measured", value: measured.count.formatted(), detail: "locations", symbol: "folder", tint: .accentColor) { show() }
                metric("Growing", value: growthCount.formatted(), detail: "locations", symbol: "chart.line.uptrend.xyaxis", tint: growthCount > 0 ? .growing : .secondary) { model.categoryFilter = nil; model.section = .locations; model.locationFilter = .growing }
                metric("Watching", value: model.overview.watchingCount.formatted(), detail: "checked first", symbol: "eye", tint: .accentColor) { model.categoryFilter = nil; model.section = .watching }
                metric("Needs attention", value: model.attentionCount.formatted(), detail: "not measured", symbol: "exclamationmark.triangle", tint: model.attentionCount > 0 ? .attention : .secondary) { model.categoryFilter = nil; model.section = .needsAttention }
            }
            HStack(alignment: .top, spacing: 12) {
                categories.frame(maxWidth: .infinity)
                largest.frame(maxWidth: .infinity)
            }
        }.padding(.horizontal, 22).padding(.bottom, 10)
        }.scrollBounceBehavior(.basedOnSize)
        .onChange(of: model.lastScan?.id) { _, _ in updateChartForScan() }
    }
    @ViewBuilder private var scanStatus: some View {
        if model.running || model.discovering {
            HStack(spacing: 12) {
                ProgressView(value: model.running ? Double(model.completed) : 0, total: Double(max(model.targetCount, 1))).frame(width: 160)
                Text(model.running ? "Scanning \(model.completed) of \(model.targetCount) · \(model.progress)" : model.progress).font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Cancel") { model.cancelWork() }.controlSize(.small)
            }.padding(10).background(.background.secondary)
        } else if let last = model.lastScan {
            HStack(spacing: 8) {
                Image(systemName: last.complete ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(last.complete ? Color.stable : Color.growing).accessibilityHidden(true)
                Text("Last scan \(last.finishedAt.formatted(date: .abbreviated, time: .shortened)) · \(last.scope.lowercased()) · \(last.measurements.count) \(last.measurements.count == 1 ? "location" : "locations")\(last.complete ? "" : " · stopped early")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Scan Now", systemImage: "arrow.clockwise") { model.scan() }.controlSize(.small).disabled(model.inspecting || model.store == nil)
            }.padding(.horizontal, 4)
        }
    }
    private func metric(_ title: String, value: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.body).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                VStack(alignment: .leading, spacing: 0) { Text(title).font(.caption.weight(.medium)); Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).background(.background.secondary)
        }.buttonStyle(.plain).accessibilityLabel("\(title): \(value) \(detail)")
    }
    private var driveCard: some View {
        Panel(title: "Your Mac’s storage", symbol: "internaldrive") {
            if let volume = model.volume {
                HStack(spacing: 18) {
                    ZStack {
                        Chart {
                            SectorMark(angle: .value("Used", volume.used), innerRadius: .ratio(0.78), angularInset: 2).foregroundStyle(Color.secondary.opacity(0.35))
                            SectorMark(angle: .value("Free", volume.free), innerRadius: .ratio(0.78), angularInset: 2).foregroundStyle(Color.accentColor)
                        }.chartLegend(.hidden)
                        VStack(spacing: 2) { Text((Double(volume.used) / Double(volume.total)).formatted(.percent.precision(.fractionLength(0)))).font(.title2.weight(.semibold)).monospacedDigit(); Text("used").font(.caption2).foregroundStyle(.secondary) }
                    }.frame(width: 96, height: 96).accessibilityElement(children: .ignore).accessibilityLabel("\(byteLabel(volume.used)) used of \(byteLabel(volume.total)) total")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(byteLabel(volume.free)).font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                        Text("free on your home volume").font(.caption).foregroundStyle(.secondary)
                        Label("\(byteLabel(volume.used)) used of \(byteLabel(volume.total))", systemImage: "circle.fill").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text("Checked \(volume.date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.tertiary)
                            Button("Refresh") { model.refreshVolume() }.buttonStyle(.link).font(.caption2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else { Text("Volume capacity is unavailable."); Button("Try again") { model.refreshVolume() } }
        }
    }
    private var freeSpaceChart: some View {
        Panel(title: "Free space, last 7 days", symbol: "chart.xyaxis.line") {
            let points = freeHistory.filter { timeWindow.contains($0.finishedAt) }
            if points.isEmpty {
                Text("Each scan records the free space at that moment. Run a scan to add the first point.").font(.caption).foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                Chart(points) { record in
                    LineMark(x: .value("Date", record.finishedAt), y: .value("Free GiB", Double(record.freeBytes ?? 0) / 1_073_741_824)).foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                    PointMark(x: .value("Date", record.finishedAt), y: .value("Free GiB", Double(record.freeBytes ?? 0) / 1_073_741_824)).foregroundStyle(Color.accentColor).symbolSize(28)
                    if let selectedDate, let picked = points.min(by: { abs($0.finishedAt.timeIntervalSince(selectedDate)) < abs($1.finishedAt.timeIntervalSince(selectedDate)) }), picked.id == record.id {
                        RuleMark(x: .value("Selected", picked.finishedAt)).foregroundStyle(.tertiary)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXScale(domain: timeWindow)
                .chartYScale(domain: freeRange)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Free space over the last seven days, \(points.count) observations")
                HStack {
                    if let selectedDate, let picked = points.min(by: { abs($0.finishedAt.timeIntervalSince(selectedDate)) < abs($1.finishedAt.timeIntervalSince(selectedDate)) }) {
                        Text("\(picked.finishedAt.formatted(date: .abbreviated, time: .shortened)) · \(byteLabel(picked.freeBytes ?? 0)) free").font(.caption).monospacedDigit()
                    } else if let first = points.first?.freeBytes, let last = points.last?.freeBytes, points.count > 1 {
                        let delta = last - first
                        Text("\(delta >= 0 ? "+" : "−")\(byteLabel(abs(delta))) free since \(points.first!.finishedAt.formatted(date: .abbreviated, time: .omitted)) · \(points.count) scans").font(.caption).foregroundStyle(delta < 0 ? Color.growing : .secondary).monospacedDigit()
                    } else { Text("One observation so far.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("GiB, all disk activity").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
    private var categories: some View {
        Panel(title: "Where the measured space goes", symbol: "square.stack.3d.up") {
            if groups.isEmpty { Text("Scan a location to start mapping its storage.").foregroundStyle(.secondary) }
            else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(byteLabel(total)).font(.title2.weight(.semibold)).monospacedDigit()
                    Text("in \(groups.reduce(0) { $0 + $1.count }) measured locations").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { showingCaveats.toggle() } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.borderless).accessibilityLabel("How these totals are counted")
                        .popover(isPresented: $showingCaveats, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("How these totals are counted").font(.headline)
                                Text("Latest saved size per location, nested folders counted once. Measurements can be from different scans. Parent folders include their children. APFS shares blocks between files, so this is not reclaimable space and never equals the used space on the volume.")
                                Text("Coverage is the catalog in Settings › Coverage plus folders you add. It is not a whole-disk scan.").foregroundStyle(.secondary)
                            }.font(.callout).padding(16).frame(width: 360)
                        }
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(groups) { group in
                            Rectangle().fill(group.category.tint).frame(width: max(2, geo.size.width * Double(group.bytes) / Double(max(total, 1)) - 2))
                                .help("\(group.category.rawValue) · \(byteLabel(group.bytes))")
                        }
                    }.clipShape(Capsule())
                }.frame(height: 18).accessibilityElement(children: .ignore).accessibilityLabel(groups.map { "\($0.category.rawValue) \(byteLabel($0.bytes))" }.joined(separator: ", "))
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 3) {
                    ForEach(groups) { group in
                        Button { show(group.category) } label: {
                            HStack(spacing: 7) {
                                Circle().fill(group.category.tint).frame(width: 9, height: 9).accessibilityHidden(true)
                                Text(group.category.rawValue).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(byteLabel(group.bytes)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).help(group.category.shortPurpose).accessibilityLabel("\(group.category.rawValue), \(byteLabel(group.bytes)), show locations")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private var largest: some View {
        Panel(title: "Largest locations", symbol: "arrow.down.right.and.arrow.up.left") {
            ForEach(measured.prefix(5)) { item in
                Button { open(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.profile.category.symbol).foregroundStyle(item.profile.category.tint).frame(width: 22).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) { Text(item.profile.name).font(.callout).lineLimit(1); Text(item.profile.project ?? item.profile.associatedApp).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }.padding(.vertical, 1).contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu { LocationActions(model: model, path: item.profile.path) }
            }
            Spacer(minLength: 0)
            Text("Large does not mean unused. Context Cleaner never deletes files. You decide, in Finder.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
