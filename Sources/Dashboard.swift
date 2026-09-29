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
        case .simulator: return "Virtual iPhones and iPads used to test apps. Each can hold apps, photos and saves."
        case .workspace: return "Project working folders. Source, build results and private inputs can sit side by side."
        case .packageCache: return "Downloaded dependencies, kept so future installs are faster."
        case .installCache: return "Reusable data from installing apps on physical devices."
        case .buildOutput: return "Compiler output and indexes. Usually rebuildable, but rebuilding takes time."
        case .debugSymbols: return "Files used to debug specific devices and read crash reports."
        case .backup: return "Recovery copies that may hold the only copy of unfinished work."
        case .history: return "Saved conversations and records of earlier work."
        case .model: return "Downloaded AI models and datasets used by local tools."
        case .appData: return "App libraries, settings, databases and saves. Being large doesn't make them disposable."
        case .download: return "Installers, documents and other downloads. Some may be the only copy."
        case .unknown: return "A folder whose purpose isn't known yet."
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
/// A tiny trend line drawn as a path, so long tables stay fast.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .secondary
    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let flat = high - low < max(high * 0.0005, 1)
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = flat ? geo.size.height / 2 : geo.size.height * (1 - CGFloat((value - low) / (high - low)))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }.frame(width: 64, height: 18).accessibilityHidden(true)
    }
}
extension Array where Element == Double {
    /// Orange when the latest value is noticeably above the first, otherwise quiet.
    var trendTint: Color {
        guard let first, let last, count > 1 else { return .secondary }
        return last - first > Swift.max(first * 0.01, 1_048_576) ? .growing : .secondary
    }
}
let gibibyte = 1_073_741_824.0
extension View {
    /// Reports the date under the pointer while hovering a chart's plot area.
    func chartHover(_ date: Binding<Date?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let plot = geometry[frame]
                            date.wrappedValue = plot.contains(location) ? proxy.value(atX: location.x - plot.minX, as: Date.self) : nil
                        case .ended: date.wrappedValue = nil
                        }
                    }
            }
        }
    }
}

/// A folder's size over time in the inspector.
struct FolderTrend: View {
    let points: [HistoryPoint]
    let change: GrowthSummary
    @State private var hover: Date?
    private var series: [TracePoint] {
        var out: [TracePoint] = [], segment = 0, scope: String?
        for point in points where point.state != .cancelled {
            guard let bytes = point.bytes, point.state == .measured else { segment += 1; scope = nil; continue }
            if let scope, scope != point.scopeID { segment += 1 }
            scope = point.scopeID
            out.append(TracePoint(id: point.id, date: point.date, bytes: bytes, segment: segment))
        }
        return out
    }
    var body: some View {
        let series = self.series
        if let first = series.first, series.count == 1 {
            Text("One scan so far (\(first.date.formatted(date: .abbreviated, time: .omitted))). Scan again later to see how it changes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if let first = series.first {
            let picked = hover.flatMap { date in series.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
            let top = Double(series.map(\.bytes).max() ?? 1) / gibibyte
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Size over time").font(.headline)
                    Spacer()
                    if let delta = change.delta, let interval = change.interval {
                        Text(delta == 0 ? "No change in \(elapsedLabel(interval))" : "\(signedBytes(delta)) in \(elapsedLabel(interval))").font(.callout.weight(.medium)).monospacedDigit()
                            .foregroundStyle(delta > 0 ? Color.growing : delta < 0 ? Color.stable : .secondary)
                    }
                }
                Chart {
                    ForEach(series) { point in
                        AreaMark(x: .value("Date", point.date), yStart: .value("Zero", 0), yEnd: .value("Size", Double(point.bytes) / gibibyte), series: .value("Run", point.segment))
                            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
                        LineMark(x: .value("Date", point.date), y: .value("Size", Double(point.bytes) / gibibyte), series: .value("Run", point.segment))
                            .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
                        if series.count <= 30 { PointMark(x: .value("Date", point.date), y: .value("Size", Double(point.bytes) / gibibyte)).foregroundStyle(Color.accentColor).symbolSize(18) }
                    }
                    if let picked { RuleMark(x: .value("Selected", picked.date)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [3])) }
                }
                .chartYScale(domain: 0...max(top * 1.1, 0.001))
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.18)); AxisValueLabel { if let v = value.as(Double.self) { Text(byteLabel(Int64(v * gibibyte))).font(.caption).foregroundStyle(.secondary) } } } }
                .chartXAxis {
                    // Within two days, dates alone repeat; show the day and hour instead.
                    let short = (series.last?.date.timeIntervalSince(first.date) ?? 0) < 2 * 86400
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: short ? .dateTime.weekday(.abbreviated).hour() : .dateTime.month(.abbreviated).day()) }
                }
                .chartHover($hover)
                .frame(height: 110)
                .accessibilityLabel("Folder size from \(byteLabel(first.bytes)) to \(byteLabel(series.last!.bytes)) across \(series.count) scans")
                Text(picked.map { "\($0.date.formatted(date: .abbreviated, time: .shortened)) · \(byteLabel($0.bytes))" } ?? "\(series.count) scans since \(first.date.formatted(date: .abbreviated, time: .omitted)). Gaps mean the scan scope changed or a scan failed.")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
            }
        }
    }
}

/// Used space over time, filling upward under the disk's capacity.
struct UsageChart: View {
    @ObservedObject var model: CleanerModel
    var chartHeight: CGFloat = 136
    @State private var range: UsageRange = .week
    @State private var perBucket = false
    @State private var hover: Date?
    @State private var span: ClosedRange<Date>?
    var body: some View {
        let readings = model.usage
        let window = range.window(endingAt: readings.last?.date ?? Date())
        let points = usageSeries(readings, in: window, gapLimit: range.gapLimit)
        let active = span ?? window
        let change = usageChange(readings, from: active.lowerBound, to: active.upperBound)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                headline(change)
                Spacer(minLength: 8)
                Picker("Range", selection: $range) { ForEach(UsageRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Group {
                if perBucket { bucketChart(readings, window: window) }
                else if points.count < 2 { emptyChart }
                else { levelChart(points, window: window) }
            }.frame(height: chartHeight)
            HStack(spacing: 10) {
                Picker("Chart", selection: $perBucket) { Text("Space used").tag(false); Text("Change per \(range.bucketName)").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                Spacer()
                if span != nil { Button("Clear Selection") { span = nil }.controlSize(.small) }
                else if !perBucket { Text("Drag across the chart to compare two times").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            grew(from: active.lowerBound, to: active.upperBound)
        }
        .onChange(of: range) { _, _ in span = nil; hover = nil }
        .onChange(of: perBucket) { _, _ in span = nil; hover = nil }
    }
    @ViewBuilder private func headline(_ change: UsageChange?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let change {
                let delta = change.delta
                (Text(delta == 0 ? "No change" : signedBytes(delta)).foregroundColor(delta > 0 ? .growing : delta < 0 ? .stable : .primary)
                 + Text(delta > 0 ? " more space used" : delta < 0 ? " of space freed" : " in used space").foregroundColor(.primary))
                    .font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(span == nil ? "Not enough readings yet" : "No readings in this span").font(.title2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(detail(change)).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }.accessibilityElement(children: .combine)
    }
    private func detail(_ change: UsageChange?) -> String {
        if let hover {
            if perBucket {
                let bucket = usageBuckets(model.usage, window: range.window(endingAt: model.usage.last?.date ?? Date()), component: range.bucket).first { $0.start <= hover && hover < $0.end }
                guard let bucket else { return " " }
                let label = bucket.start.formatted(range == .day ? .dateTime.weekday(.abbreviated).hour() : .dateTime.weekday(.wide).month(.abbreviated).day())
                return label + " · " + (bucket.delta.map { signedBytes($0) + " used" } ?? "no readings")
            }
            if let reading = model.usage.min(by: { abs($0.date.timeIntervalSince(hover)) < abs($1.date.timeIntervalSince(hover)) }) {
                return "\(reading.date.formatted(date: .abbreviated, time: .shortened)) · \(byteLabel(reading.used)) used · \(byteLabel(reading.free)) free"
            }
        }
        let window = range.window(endingAt: model.usage.last?.date ?? Date())
        let firstReading = model.usage.first { $0.date >= window.lowerBound }?.date
        let startsLate = firstReading.map { chartStartsLate($0, window: window) } ?? false
        let when = span.map { "\($0.lowerBound.formatted(.dateTime.month(.abbreviated).day().hour())) – \($0.upperBound.formatted(.dateTime.month(.abbreviated).day().hour()))" }
            ?? (startsLate ? "Since \(firstReading!.formatted(.dateTime.weekday(.abbreviated).day().hour())), the first reading" : "Last " + range.rawValue)
        guard let change else { return when + (span == nil ? " · Disk space is noted every hour while the app is open" : " · Drag across the blue area instead") }
        return "\(when) · \(byteLabel(change.from.used)) → \(byteLabel(change.to.used)) used"
    }
    /// True when readings begin well after the range starts. The chart then starts at the first reading
    /// instead of drawing an empty stretch.
    private func chartStartsLate(_ first: Date, window: ClosedRange<Date>) -> Bool {
        first.timeIntervalSince(window.lowerBound) > window.upperBound.timeIntervalSince(window.lowerBound) * 0.08
    }
    private func xStride(_ domain: ClosedRange<Date>) -> (Calendar.Component, Int) {
        let days = domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400
        return days <= 1.05 ? (.hour, 6) : days <= 3 ? (.hour, 8) : days <= 8 ? (.day, 1) : (.day, 5)
    }
    private func xFormat(_ domain: ClosedRange<Date>) -> Date.FormatStyle {
        let days = domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400
        return days <= 1.05 ? .dateTime.hour() : days <= 3 ? .dateTime.weekday(.abbreviated).hour() : days <= 8 ? .dateTime.weekday(.abbreviated).day() : .dateTime.month(.abbreviated).day()
    }
    /// Axis dates on round hours or days, leaving out any too close to the edges to show in full.
    private func xTicks(_ domain: ClosedRange<Date>) -> [Date] {
        let (component, step) = xStride(domain)
        let calendar = Calendar.current
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        var date = calendar.dateInterval(of: component == .hour ? .hour : .day, for: domain.lowerBound)?.start ?? domain.lowerBound
        if component == .hour { while calendar.component(.hour, from: date) % step != 0 { date = date.addingTimeInterval(3600) } }
        var ticks: [Date] = []
        while date <= domain.upperBound, ticks.count < 60 {
            let fromStart = date.timeIntervalSince(domain.lowerBound), toEnd = domain.upperBound.timeIntervalSince(date)
            if fromStart >= span * 0.04 && toEnd >= span * 0.09 { ticks.append(date) }
            date = calendar.date(byAdding: component, value: step, to: date) ?? domain.upperBound.addingTimeInterval(1)
        }
        return ticks
    }
    private func levelChart(_ points: [UsagePoint], window: ClosedRange<Date>) -> some View {
        let axis = usageAxis(points.map(\.reading))
        let capacity = axis.upperBound
        // The capacity line carries its own label, so the top tick would only repeat it.
        let ticks = [axis.lowerBound, (axis.lowerBound + axis.upperBound) / 2]
        let picked = hover.flatMap { date in points.min { abs($0.reading.date.timeIntervalSince(date)) < abs($1.reading.date.timeIntervalSince(date)) } }
        let first = points.first?.reading.date ?? window.lowerBound
        // Run from the first reading (or the range start) to the latest reading, so the line always reaches both edges.
        let lower = chartStartsLate(first, window: window) ? first : window.lowerBound
        let upper = max(points.last?.reading.date ?? window.upperBound, lower.addingTimeInterval(3600))
        let domain = lower...upper
        let fill = LinearGradient(colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        return Chart {
            if let span { RectangleMark(xStart: .value("From", span.lowerBound), xEnd: .value("To", span.upperBound)).foregroundStyle(Color.accentColor.opacity(0.10)) }
            RuleMark(y: .value("Capacity", capacity)).foregroundStyle(Color.secondary.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                .annotation(position: .top, alignment: .trailing, spacing: 2) { Text("Capacity \(byteLabel(Int64(capacity * gibibyte)))").font(.caption).foregroundStyle(.secondary) }
            ForEach(points) { point in
                let used = Double(point.reading.used) / gibibyte
                AreaMark(x: .value("Time", point.reading.date), yStart: .value("Floor", axis.lowerBound), yEnd: .value("Used", used), series: .value("Series", "used-\(point.segment)"))
                    .foregroundStyle(fill).interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.reading.date), y: .value("Used", used), series: .value("Series", "line-\(point.segment)"))
                    .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
            }
            if let last = points.last, picked == nil {
                let used = Double(last.reading.used) / gibibyte
                PointMark(x: .value("Time", last.reading.date), y: .value("Used", used)).foregroundStyle(Color.accentColor.opacity(0.2)).symbolSize(180)
                PointMark(x: .value("Time", last.reading.date), y: .value("Used", used)).foregroundStyle(Color.accentColor).symbolSize(45)
                    .annotation(position: .bottom, alignment: .trailing, spacing: 6) {
                        Text(byteLabel(last.reading.used)).font(.caption.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.regularMaterial, in: Capsule())
                    }
            }
            if let picked {
                let used = Double(picked.reading.used) / gibibyte
                RuleMark(x: .value("Reading", picked.reading.date)).foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Reading", picked.reading.date), y: .value("Used", used)).foregroundStyle(Color.accentColor).symbolSize(60)
                    .annotation(position: .top, alignment: .center, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(byteLabel(picked.reading.used) + " used").font(.caption.weight(.semibold)).monospacedDigit()
                            Text(picked.reading.date.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal, 8).padding(.vertical, 4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: axis)
        .chartXAxis { AxisMarks(values: xTicks(domain)) { _ in AxisValueLabel(format: xFormat(domain)).font(.caption).foregroundStyle(Color.secondary) } }
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel { if let v = value.as(Double.self) { Text(byteLabel(Int64(v * gibibyte))).font(.caption).foregroundStyle(.secondary) } }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in interactionLayer(proxy) }
        .accessibilityLabel("Used disk space \(range.phrase). \(points.count) readings. The dashed line is capacity.")
    }
    private func bucketChart(_ readings: [UsageReading], window: ClosedRange<Date>) -> some View {
        let buckets = usageBuckets(readings, window: window, component: range.bucket).filter { $0.delta != nil }
        return Group {
            if buckets.isEmpty {
                placeholder("No complete \(range.bucketName)s of readings yet. They build up while the app is open.")
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(x: .value("When", bucket.start, unit: range.bucket), y: .value("Change", Double(bucket.delta!) / gibibyte))
                            .foregroundStyle(bucket.delta! > 0 ? Color.growing.gradient : Color.stable.gradient).cornerRadius(3)
                            .opacity(hover.map { bucket.start <= $0 && $0 < bucket.end } ?? true ? 1 : 0.45)
                    }
                    RuleMark(y: .value("No change", 0)).foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.75))
                }
                .chartXScale(domain: window)
                .chartXAxis { AxisMarks(values: .stride(by: xStride(window).0, count: xStride(window).1)) { _ in AxisValueLabel(format: xFormat(window)).font(.caption).foregroundStyle(Color.secondary) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.18)); AxisValueLabel { if let v = value.as(Double.self) { Text(signedBytes(Int64(v * gibibyte))).font(.caption).foregroundStyle(.secondary) } } } }
                .chartHover($hover)
                .accessibilityLabel("Change in used space per \(range.bucketName). Orange bars used more space, green bars freed space.")
            }
        }
    }
    private var emptyChart: some View { placeholder("Not enough readings yet. Context Cleaner notes your disk space every hour while it's open, and at every scan.") }
    private func placeholder(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.06))
    }
    /// Hover shows a reading; dragging selects a span; a click clears it.
    private func interactionLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let frame = proxy.plotFrame else { return }
                        let plot = geometry[frame]
                        hover = plot.contains(location) ? proxy.value(atX: location.x - plot.minX, as: Date.self) : nil
                    case .ended: hover = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard let frame = proxy.plotFrame else { return }
                    let plot = geometry[frame]
                    guard abs(value.translation.width) > 6,
                          let a: Date = proxy.value(atX: min(max(value.startLocation.x, plot.minX), plot.maxX) - plot.minX),
                          let b: Date = proxy.value(atX: min(max(value.location.x, plot.minX), plot.maxX) - plot.minX) else { span = nil; return }
                    span = min(a, b)...max(a, b)
                })
        }
    }
    @ViewBuilder private func grew(from: Date, to: Date) -> some View {
        let grown = model.foldersThatGrew(from: from, to: to, limit: 3)
        HStack(spacing: 8) {
            if grown.isEmpty {
                Label("Folders scanned twice in this span will show here if they grew.", systemImage: "folder.badge.questionmark").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Grew most:").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(grown) { item in
                Button { model.open(item.path) } label: {
                    HStack(spacing: 5) {
                        Circle().fill(item.category.tint).frame(width: 7, height: 7)
                        Text(item.name).lineLimit(1)
                        Text("+" + byteLabel(item.delta)).foregroundStyle(Color.growing).monospacedDigit()
                    }.font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(Color.secondary.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain).help("Show this folder")
            }
            Spacer(minLength: 0)
        }
    }
}

struct Dashboard: View {
    @ObservedObject var model: CleanerModel
    @State private var hoveredSegment: String?
    @State private var hoveredBucket: String?
    @State private var mapByType = false
    @State private var showLargest = false
    private var groups: [StorageGroup] { model.overview.groups }
    private var measured: [FolderMeasurement] { model.overview.measuredBySize }
    private func show(_ category: FolderCategory? = nil, filter: LocationFilter = .all) {
        model.categoryFilter = category; model.search = ""; model.section = .locations
        model.locationFilter = filter; model.selected = nil; model.inspector = "Overview"
    }
    var body: some View {
        GeometryReader { geometry in
            // The chart grows into spare height on large windows; everything else keeps its size.
            let chartHeight = min(300, max(136, geometry.size.height - 690))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    hero(chartHeight)
                    diskMap
                    statusLine
                    HStack(alignment: .top, spacing: 16) {
                        idlePanel.frame(maxWidth: .infinity)
                        foldersPanel.frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 16)
            }.scrollBounceBehavior(.basedOnSize)
        }
    }
    private func hero(_ chartHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 22) {
            capacity.frame(width: 190)
            Divider()
            UsageChart(model: model, chartHeight: chartHeight)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background.secondary)
    }
    @ViewBuilder private var capacity: some View {
        if let v = model.volume {
            let fraction = Double(v.used) / Double(max(v.total, 1))
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Chart {
                        SectorMark(angle: .value("Used", v.used), innerRadius: .ratio(0.78), angularInset: 1.5).foregroundStyle(Color.accentColor)
                        SectorMark(angle: .value("Free", v.free), innerRadius: .ratio(0.78), angularInset: 1.5).foregroundStyle(Color.secondary.opacity(0.22))
                    }.chartLegend(.hidden)
                    VStack(spacing: 0) {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)))).font(.title2.weight(.semibold)).monospacedDigit()
                        Text("used").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(width: 104, height: 104).accessibilityElement(children: .ignore).accessibilityLabel("\(byteLabel(v.used)) used of \(byteLabel(v.total))")
                VStack(alignment: .leading, spacing: 2) {
                    Text(byteLabel(v.free)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text("free of \(byteLabel(v.total))").font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text("Checked \(v.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Button { model.refreshVolume() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).controlSize(.small)
                        .help("Check disk space now. Doesn't scan folders.").accessibilityLabel("Check disk space now")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) { Text("Disk space is unavailable.").font(.callout); Button("Try Again") { model.refreshVolume() } }
        }
    }
    private var statusLine: some View {
        HStack(spacing: 6) {
            link("\(measured.count) scanned", tint: .primary) { show(filter: .all) }
            if model.overview.pendingCount > 0 { dot; link("\(model.overview.pendingCount) not scanned yet", tint: .secondary) { show(filter: .unscanned) } }
            if model.overview.growthCount > 0 { dot; link("\(model.overview.growthCount) growing", tint: .growing) { show(filter: .growing) } }
            dot
            if model.attentionCount > 0 { link("\(model.attentionCount) couldn't be scanned", tint: .attention) { model.categoryFilter = nil; model.search = ""; model.section = .needsAttention } }
            else { Text("nothing needs attention").foregroundStyle(.secondary) }
            Spacer()
            // Most sizes come from the last full scan; say plainly when that's old.
            if let full = model.records.last(where: { $0.measurements.count >= 20 })?.finishedAt, Date().timeIntervalSince(full) > 86400 {
                link("Sizes are from \(ageText(full)) · Scan to refresh", tint: .growing) { model.showingScanPlan = true }
            } else if let scan = model.lastScan { Text("Last scan \(scan.finishedAt.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary) }
            Button("What gets scanned?") { model.showingScanPlan = true }.buttonStyle(.link)
        }.font(.callout).lineLimit(1)
    }
    private var dot: some View { Text("·").foregroundStyle(.tertiary) }
    private func link(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).foregroundStyle(tint).underline(false) }.buttonStyle(.plain).onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
    /// One whole-disk picture: what's safe, what to check, what apps keep, what you keep, everything else and free space.
    private struct Segment: Identifiable {
        let id: String, title: String, detail: String, bytes: Int64, color: Color
        var outlined = false
        let action: (() -> Void)?
    }
    private var segments: [Segment] {
        guard let volume = model.volume else { return [] }
        var list: [Segment] = [], tracked: Int64 = 0
        if mapByType {
            for group in groups {
                list.append(Segment(id: group.category.rawValue, title: group.category.displayName, detail: group.category.shortPurpose, bytes: group.bytes, color: group.category.tint, action: { show(group.category) }))
                tracked += group.bytes
            }
        } else {
            for verdict in Verdict.allCases {
                let total = model.verdictTotal(verdict)
                list.append(Segment(id: verdict.title, title: verdict.title, detail: verdict.meaning.prefix(1).uppercased() + verdict.meaning.dropFirst(), bytes: total.bytes, color: verdict.tint, action: { show(filter: verdict.filter) }))
                tracked += total.bytes
            }
            let kept = model.keptSummary
            list.append(Segment(id: "kept", title: "Kept by you", detail: "Never suggested", bytes: kept.keptBytes + kept.offBytes, color: .purple, action: { model.search = ""; model.categoryFilter = nil; model.section = .kept }))
            tracked += kept.keptBytes + kept.offBytes
        }
        list.append(Segment(id: "other", title: "Everything else", detail: "macOS, apps and files outside the scanned folders", bytes: max(0, volume.used - tracked), color: Color.primary.opacity(0.16), action: nil))
        list.append(Segment(id: "free", title: "Free", detail: "Space you have now", bytes: volume.free, color: .clear, outlined: true, action: nil))
        return list.filter { $0.bytes > 0 }
    }
    private var diskMap: some View {
        let safe = model.verdictTotal(.safe)
        let capacity = Double(max(model.volume?.total ?? 1, 1))
        let parts = segments
        func share(_ bytes: Int64) -> String { (Double(bytes) / capacity).formatted(.percent.precision(.fractionLength(0))) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(safe.count == 0 ? "Nothing is clearly safe to remove yet" : "About \(byteLabel(safe.bytes)) looks safe to remove")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(safe.count == 0 ? "Scan your folders so Context Cleaner can see when each was last used." : "\(safe.count) \(safe.count == 1 ? "folder" : "folders") that tools recreate and you haven't needed lately. You remove them yourself.")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Picker("Map", selection: $mapByType) { Text("By answer").tag(false); Text("By type").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                if safe.count == 0 { Button("Scan Folders…") { model.showingScanPlan = true } }
                else { Button("Review Safe Folders") { show(filter: .safe) }.buttonStyle(.borderedProminent) }
            }
            GeometryReader { geo in
                let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        let width = max(3, (geo.size.width - gaps) * Double(part.bytes) / capacity)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(part.color.opacity(hoveredSegment == nil || hoveredSegment == part.id ? 1 : 0.3))
                            .overlay { if part.outlined { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) } }
                            .frame(width: width)
                            .contentShape(Rectangle())
                            .onHover { inside in hoveredSegment = inside ? part.id : (hoveredSegment == part.id ? nil : hoveredSegment) }
                            .onTapGesture { part.action?() }
                            .accessibilityElement().accessibilityLabel("\(part.title), \(byteLabel(part.bytes)), \(share(part.bytes)) of your disk").accessibilityAddTraits(part.action == nil ? [] : .isButton)
                    }
                }
            }.frame(height: 30)
            Group {
                if let id = hoveredSegment, let part = parts.first(where: { $0.id == id }) {
                    Text("\(part.title) · \(byteLabel(part.bytes)) · \(share(part.bytes)) of your disk · \(part.detail)" + (part.action == nil ? "" : " · click to list"))
                } else { Text("Your whole disk, \(byteLabel(Int64(capacity))). Point at a color to see what it is; click to list those folders.") }
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(parts) { part in
                    Button { part.action?() } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(part.color).frame(width: 10, height: 10)
                                .overlay { if part.outlined { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2])) } }
                            Text(part.title).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(byteLabel(part.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.callout).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(hoveredSegment == part.id ? part.color.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(part.action == nil)
                        .onHover { inside in hoveredSegment = inside ? part.id : (hoveredSegment == part.id ? nil : hoveredSegment) }
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background.secondary)
    }
    /// How long scanned space has sat unused, colored by answer. Big idle bars are the best places to look.
    private var idlePanel: some View {
        let buckets = model.idleBuckets
        let stale = buckets.filter { $0.id == 2 || $0.id == 3 }.reduce(Int64(0)) { $0 + $1.total }
        let staleSafe = buckets.filter { $0.id == 2 || $0.id == 3 }.reduce(Int64(0)) { $0 + ($1.bytes[.safe] ?? 0) }
        return Panel(title: "How long it's sat unused", symbol: "hourglass") {
            Text(stale > 0 ? "\(byteLabel(stale)) hasn't been touched in a month or more; \(byteLabel(staleSafe)) of it looks safe to remove." : "Most scanned space was used this month.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Chart {
                ForEach(buckets) { bucket in
                    ForEach(Verdict.allCases) { verdict in
                        BarMark(x: .value("Last used", bucket.title), y: .value("Size", Double(bucket.bytes[verdict] ?? 0) / gibibyte))
                            .foregroundStyle(by: .value("Answer", verdict.title))
                            .cornerRadius(3)
                            .opacity(hoveredBucket == nil || hoveredBucket == bucket.title ? 1 : 0.4)
                    }
                }
            }
            .chartForegroundStyleScale(domain: Verdict.allCases.map(\.title), range: Verdict.allCases.map(\.tint))
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel { if let v = value.as(Double.self) { Text(byteLabel(Int64(v * gibibyte))).font(.caption) } }
            } }
            .chartLegend(position: .bottom, alignment: .leading)
            .chartOverlay { proxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let point) = phase { hoveredBucket = proxy.value(atX: point.x, as: String.self) } else { hoveredBucket = nil }
                    }
                    .onTapGesture { show(filter: .all) }
            }
            .frame(height: 170)
            .accessibilityLabel("Scanned space by time since last use: " + buckets.map { "\($0.title) \(byteLabel($0.total))" }.joined(separator: ", "))
            Text(hoveredBucket.flatMap { title in buckets.first { $0.title == title } }.map { bucket in
                "\(bucket.title): \(byteLabel(bucket.total)) · " + Verdict.allCases.compactMap { v in (bucket.bytes[v] ?? 0) > 0 ? "\(v.title) \(byteLabel(bucket.bytes[v]!))" : nil }.joined(separator: " · ")
            } ?? "Folders are listed biggest and longest unused first. Click the chart to see them.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    /// What you can remove, biggest first, with the largest folders one click away.
    private var foldersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label { Text(showLargest ? "Largest folders" : "Safe to remove").foregroundStyle(.primary) }
                    icon: { Image(systemName: showLargest ? "folder" : Verdict.safe.symbol).foregroundStyle(showLargest ? Color.accentColor : Verdict.safe.tint) }.font(.headline)
                Spacer()
                Picker("Show", selection: $showLargest) { Text("Safe").tag(false); Text("Largest").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
            if showLargest { largestRows } else { safeRows }
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading).background(.background.secondary)
    }
    @ViewBuilder private var safeRows: some View {
        let safe = model.overview.safe
        ForEach(safe.prefix(6)) { item in
            let advice = model.adviceFor(item)
            HStack(spacing: 10) {
                Image(systemName: Verdict.safe.symbol).foregroundStyle(Verdict.safe.tint).frame(width: 20).accessibilityHidden(true)
                Button { model.open(item.profile.path) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.profile.displayName).font(.callout).lineLimit(1)
                            Text([locationHint(item.profile.path) ?? item.profile.category.displayName, advice.lastUsed.map { "used " + ageText($0) }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help(advice.reason)
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.profile.path)]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show in Finder. You remove it yourself.").accessibilityLabel("Show \(item.profile.displayName) in Finder")
            }.padding(.vertical, 2).contextMenu { LocationActions(model: model, path: item.profile.path) }
        }
        if safe.isEmpty {
            Text("Nothing is clearly safe to remove yet. Scan your folders so Context Cleaner can see when each was last used.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Button(safe.count > 6 ? "See all \(safe.count) safe folders" : "See safe folders") { show(filter: .safe) }.buttonStyle(.link).font(.callout)
        }
    }
    @ViewBuilder private var largestRows: some View {
        Group {
            ForEach(measured.prefix(6)) { item in
                let values = model.sparkline(item.profile.path)
                Button { model.open(item.profile.path) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.profile.category.symbol).foregroundStyle(item.profile.category.tint).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.profile.displayName).font(.callout).lineLimit(1)
                            Text(locationHint(item.profile.path).map { $0 + " · " + item.profile.category.displayName } ?? item.profile.category.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Sparkline(values: values, tint: values.trendTint)
                        Image(systemName: model.adviceFor(item).verdict.symbol).foregroundStyle(model.adviceFor(item).verdict.tint)
                            .help(model.adviceFor(item).verdict.title + ": " + model.adviceFor(item).reason).accessibilityLabel(model.adviceFor(item).verdict.title)
                        Text(item.allocatedBytes.map(byteLabel) ?? "—").font(.callout).monospacedDigit().frame(minWidth: 78, alignment: .trailing)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }.padding(.vertical, 2).contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu { LocationActions(model: model, path: item.profile.path) }
            }
            if measured.isEmpty { Text("Scan folders to see the largest ones here.").font(.callout).foregroundStyle(.secondary) }
            Button("See all folders") { show() }.buttonStyle(.link).font(.callout)
        }
    }
}
