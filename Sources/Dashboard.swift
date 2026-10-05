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
        case .virtualMachine: return "desktopcomputer"
        case .temporary: return "clock.arrow.circlepath"
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
        case .virtualMachine: return "Virtual computers and container disks. Each holds a whole system and its files."
        case .temporary: return "Work files apps and tools leave behind. macOS clears ones nothing has used for 3 days."
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
            // A scan that couldn't read the folder says nothing about its size; the line carries on across it.
            guard let bytes = point.bytes, point.state == .measured else { continue }
            // One continuous line: every saved size of this folder, in order.
            _ = scope
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
                .frame(height: 110)
                .accessibilityLabel("Folder size from \(byteLabel(first.bytes)) to \(byteLabel(series.last!.bytes)) across \(series.count) scans")
                Text(picked.map { "\($0.date.formatted(date: .abbreviated, time: .shortened)) · \(byteLabel($0.bytes))" } ?? "\(series.count) scans since \(first.date.formatted(date: .abbreviated, time: .omitted)). Point at the chart for a reading.")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
            }
        }
    }
}

/// Used space over time, filling upward under the disk's capacity.
struct UsageChart: View {
    @ObservedObject var model: CleanerModel
    var chartHeight: CGFloat = 136
    @State private var perBucket = false
    @State private var hover: Date?
    // Range and selection live in the model so "Where the space went" follows them.
    private var range: UsageRange { model.chartRange }
    private var span: ClosedRange<Date>? { model.chartSpan }
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
                Picker("Range", selection: $model.chartRange) { ForEach(UsageRange.allCases) { Text($0.rawValue).tag($0) } }
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
                if span != nil { Button("Show All \(range.rawValue)") { model.chartSpan = nil }.controlSize(.small) }
                else {
                    Text(perBucket ? "Up: that \(range.bucketName) used more space. Down: space came back." : "The line climbs as your disk fills. Point for a reading; click a \(range.bucketName) or drag to look closer.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
        }
        .onChange(of: model.chartRange) { _, _ in hover = nil }
        .onChange(of: perBucket) { _, _ in model.chartSpan = nil; hover = nil }
    }
    @ViewBuilder private func headline(_ change: UsageChange?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let change {
                let delta = change.delta
                // One framing everywhere: space used. Up and blue means the disk filled; down and green means space came back.
                (Text(delta == 0 ? "No change" : byteLabel(abs(delta))).foregroundColor(delta > 0 ? .growing : delta < 0 ? .stable : .primary)
                 + Text(delta > 0 ? " more space used" : delta < 0 ? " of space freed" : " in space used").foregroundColor(.primary))
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
                // Hours and days without readings say nothing rather than "no readings".
                if let bucket, let delta = bucket.delta {
                    let label = bucket.start.formatted(range == .day ? .dateTime.weekday(.abbreviated).hour() : .dateTime.weekday(.wide).month(.abbreviated).day())
                    return label + " · " + usedChangeText(delta)
                }
            } else if let reading = model.usage.min(by: { abs($0.date.timeIntervalSince(hover)) < abs($1.date.timeIntervalSince(hover)) }) {
                return "\(reading.date.formatted(date: .abbreviated, time: .shortened)) · \(byteLabel(reading.used)) used · \(byteLabel(reading.free)) free"
            }
        }
        let window = range.window(endingAt: model.usage.last?.date ?? Date())
        let firstReading = model.usage.first { $0.date >= window.lowerBound }?.date
        let startsLate = firstReading.map { chartStartsLate($0, window: window) } ?? false
        let when = span.map { "\($0.lowerBound.formatted(.dateTime.month(.abbreviated).day().hour())) – \($0.upperBound.formatted(.dateTime.month(.abbreviated).day().hour()))" }
            ?? (startsLate ? "Since \(firstReading!.formatted(.dateTime.weekday(.abbreviated).day().hour())), the first reading" : "Last " + range.rawValue)
        guard let change else { return when + (span == nil ? " · Disk space is noted every hour while the app is open" : " · Drag across the blue area instead") }
        return "\(when) · used \(byteLabel(change.from.used)) → \(byteLabel(change.to.used)) · \(byteLabel(change.to.free)) free"
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
        // Used space, climbing toward the dashed Full line as the disk fills. Straight lines between readings:
        // smoothing overshoots the jumps that removing a big folder makes.
        let axis = usageAxis(points.map(\.reading))
        let full = axis.upperBound
        let ticks = [axis.lowerBound, (axis.lowerBound + full) / 2, full]
        let picked = hover.flatMap { date in points.min { abs($0.reading.date.timeIntervalSince(date)) < abs($1.reading.date.timeIntervalSince(date)) } }
        let first = points.first?.reading.date ?? window.lowerBound
        let lower = chartStartsLate(first, window: window) ? first : window.lowerBound
        let upper = max(points.last?.reading.date ?? window.upperBound, lower.addingTimeInterval(3600))
        let domain = lower...upper
        let fill = LinearGradient(colors: [Color.growing.opacity(0.35), Color.growing.opacity(0.05)], startPoint: .top, endPoint: .bottom)
        return Chart {
            if let span { RectangleMark(xStart: .value("From", span.lowerBound), xEnd: .value("To", span.upperBound)).foregroundStyle(Color.accentColor.opacity(0.10)) }
            RuleMark(y: .value("Full", full)).foregroundStyle(Color.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(points) { point in
                let used = Double(point.reading.used) / gibibyte
                AreaMark(x: .value("Time", point.reading.date), yStart: .value("Base", axis.lowerBound), yEnd: .value("Used", used), series: .value("Series", "used-\(point.segment)"))
                    .foregroundStyle(fill).interpolationMethod(.linear)
                LineMark(x: .value("Time", point.reading.date), y: .value("Used", used), series: .value("Series", "line-\(point.segment)"))
                    .foregroundStyle(Color.growing).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).interpolationMethod(.linear)
            }
            if let last = points.last, picked == nil {
                let used = Double(last.reading.used) / gibibyte
                PointMark(x: .value("Time", last.reading.date), y: .value("Used", used)).foregroundStyle(Color.growing.opacity(0.25)).symbolSize(180)
                PointMark(x: .value("Time", last.reading.date), y: .value("Used", used)).foregroundStyle(Color.growing).symbolSize(45)
                    .annotation(position: .bottom, alignment: .trailing, spacing: 6) {
                        Text("\(byteLabel(last.reading.free)) free now").font(.caption.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.regularMaterial, in: Capsule())
                    }
            }
            if let picked {
                let used = Double(picked.reading.used) / gibibyte
                RuleMark(x: .value("Reading", picked.reading.date)).foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Reading", picked.reading.date), y: .value("Used", used)).foregroundStyle(Color.growing).symbolSize(60)
                    .annotation(position: .bottom, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: 0) {
                            Text("\(byteLabel(picked.reading.used)) used · \(byteLabel(picked.reading.free)) free").font(.caption.weight(.semibold)).monospacedDigit()
                            Text(picked.reading.date.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.horizontal, 6).padding(.vertical, 3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: axis)
        .chartXAxis { AxisMarks(values: xTicks(domain)) { _ in AxisValueLabel(format: xFormat(domain)).font(.caption).foregroundStyle(Color.secondary) } }
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel { if let v = value.as(Double.self) { Text(v == full ? "Full" : byteLabel(Int64(v * gibibyte))).font(.caption).foregroundStyle(.secondary) } }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in interactionLayer(proxy) }
        .accessibilityLabel("Space used \(range.phrase). \(points.count) readings. The dashed line at the top means the disk is full.")
    }
    private func bucketChart(_ readings: [UsageReading], window: ClosedRange<Date>) -> some View {
        let buckets = usageBuckets(readings, window: window, component: range.bucket).filter { $0.delta != nil }
        // Start at the first hour or day with readings, so days before tracking began aren't drawn as empty.
        let first = buckets.first?.start ?? window.lowerBound
        let domain = (chartStartsLate(first, window: window) ? first : window.lowerBound)...window.upperBound
        return Group {
            if buckets.isEmpty {
                placeholder("No complete \(range.bucketName)s of readings yet. They build up while the app is open.")
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        // Change in space used: bars above the line used space, bars below it freed space.
                        BarMark(x: .value("When", bucket.start, unit: range.bucket), y: .value("Change", Double(bucket.delta!) / gibibyte))
                            .foregroundStyle(bucket.delta! > 0 ? Color.growing.gradient : Color.stable.gradient).cornerRadius(3)
                            .opacity(hover.map { bucket.start <= $0 && $0 < bucket.end } ?? true ? 1 : 0.45)
                    }
                    RuleMark(y: .value("No change", 0)).foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.75))
                }
                .chartXScale(domain: domain)
                .chartXAxis { AxisMarks(values: .stride(by: xStride(domain).0, count: xStride(domain).1)) { _ in AxisValueLabel(format: xFormat(domain)).font(.caption).foregroundStyle(Color.secondary) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.18)); AxisValueLabel { if let v = value.as(Double.self) { Text(signedBytes(Int64(v * gibibyte))).font(.caption).foregroundStyle(.secondary) } } } }
                .chartHover($hover)
                .chartOverlay { proxy in interactionLayer(proxy) }
                .accessibilityLabel("Change in space used per \(range.bucketName). Blue bars above the line used space, green bars below it freed space.")
            }
        }
    }
    private var emptyChart: some View { placeholder("Not enough readings yet. Context Cleaner notes your disk space every hour while it's open, and at every scan.") }
    private func placeholder(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.06))
    }
    /// Hover shows a reading. Dragging selects a span; clicking selects the hour or day under the pointer,
    /// and clicking inside a selection clears it.
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
                    guard let a: Date = proxy.value(atX: min(max(value.startLocation.x, plot.minX), plot.maxX) - plot.minX),
                          let b: Date = proxy.value(atX: min(max(value.location.x, plot.minX), plot.maxX) - plot.minX) else { model.chartSpan = nil; return }
                    if abs(value.translation.width) > 6 { model.chartSpan = min(a, b)...max(a, b); return }
                    if let span, span.contains(a) { model.chartSpan = nil; return }
                    let calendar = Calendar.current
                    if range == .day, let hour = calendar.dateInterval(of: .hour, for: a) {
                        model.chartSpan = hour.start.addingTimeInterval(-2 * 3600)...hour.end.addingTimeInterval(2 * 3600)
                    } else if let day = calendar.dateInterval(of: .day, for: a) { model.chartSpan = day.start...day.end }
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
    var body: some View {
        GeometryReader { geometry in
            // Free up space is where the work happens, so it comes first after the two headline numbers,
            // and its list fills the first screen. The chart and where the space went explain it below.
            let wide = geometry.size.width > 1180
            let lower = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    // Freshness and counts first, so you know how current everything below is.
                    StatusLine(model: model)
                    // Free space now, and how much you can get back.
                    HStack(alignment: .top, spacing: 16) {
                        CapacityRing(model: model).padding(16).frame(width: 210).frame(maxHeight: .infinity, alignment: .topLeading).background(.background.secondary)
                        DiskMap(model: model).frame(maxHeight: .infinity, alignment: .top).background(.background.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    // Free Up Space has its own page; here, one line says what's waiting there.
                    FreeUpSummary(model: model)
                    lower {
                        UsageChart(model: model, chartHeight: 150).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background.secondary)
                        WentPanel(model: model).frame(width: wide ? 520 : nil).frame(maxWidth: wide ? 520 : .infinity)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 16)
            }.scrollBounceBehavior(.basedOnSize)
        }
    }
}
/// Free space now, as a ring and a number.
struct CapacityRing: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        if let v = model.volume {
            let fraction = Double(v.used) / Double(max(v.total, 1))
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Chart {
                        SectorMark(angle: .value("Used", v.used), innerRadius: .ratio(0.78), angularInset: 1.5).foregroundStyle(Color.accentColor)
                        SectorMark(angle: .value("Free", v.free), innerRadius: .ratio(0.78), angularInset: 1.5).foregroundStyle(Color.stable.opacity(0.35))
                    }.chartLegend(.hidden)
                    VStack(spacing: 0) {
                        Text(usedPercentText(fraction)).font(.title2.weight(.semibold)).monospacedDigit()
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
}
/// How current the numbers are, first thing on the page. Scanning lives in the toolbar.
struct StatusLine: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        let full = model.records.last(where: { $0.measurements.count >= 20 })
        let stale = full.map { Date().timeIntervalSince($0.finishedAt) > 86400 } ?? true
        let overview = model.overview
        HStack(spacing: 6) {
            Image(systemName: "clock").foregroundStyle(stale ? Color.caution : .secondary).accessibilityHidden(true)
            if let full {
                Text("Sizes from the scan \(full.finishedAt.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(stale ? Color.caution : .primary)
                    .help("Took \(elapsedLabel(full.finishedAt.timeIntervalSince(full.startedAt))) · \(full.measurements.count) folders. Scan again with Scan Folders in the toolbar.")
            } else { Text("No scan yet. Choose Scan Folders in the toolbar.").foregroundStyle(Color.caution) }
            dot
            link("\(overview.measuredBySize.count) folders", tint: .secondary) { model.showFolders(filter: .all) }
            if overview.pendingCount > 0 { dot; link("\(overview.pendingCount) not scanned yet", tint: .secondary) { model.showFolders(filter: .unscanned) } }
            if overview.growthCount > 0 { dot; link("\(overview.growthCount) growing", tint: .growing) { model.showFolders(filter: .growing) } }
            if model.attentionCount > 0 { dot; link("\(model.attentionCount) couldn't be scanned", tint: .attention) { model.categoryFilter = nil; model.search = ""; model.section = .needsAttention } }
            Spacer()
        }.font(.callout).lineLimit(1)
    }
    private var dot: some View { Text("·").foregroundStyle(.tertiary) }
    private func link(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).foregroundStyle(tint) }.buttonStyle(.plain).pointingHand()
    }
}
/// The whole disk in one bar, ranked by what removing costs.
struct DiskMap: View {
    @ObservedObject var model: CleanerModel
    @State private var hovered: String?
    @State private var byType = false
    private struct Segment: Identifiable {
        let id: String, title: String, detail: String, bytes: Int64, color: Color
        var outlined = false
        let action: (() -> Void)?
    }
    private var segments: [Segment] {
        guard let volume = model.volume else { return [] }
        var list: [Segment] = [], tracked: Int64 = 0
        if byType {
            for group in model.overview.groups {
                list.append(Segment(id: group.category.rawValue, title: group.category.displayName, detail: group.category.shortPurpose, bytes: group.bytes, color: group.category.tint, action: { model.showFolders(group.category) }))
                tracked += group.bytes
            }
        } else {
            let r = model.reclaim
            list.append(Segment(id: "safe", title: "Safe to remove", detail: "Not needed again; nothing is lost", bytes: r.safe.bytes, color: Verdict.safe.tint, action: { model.showFolders(filter: .safe) }))
            list.append(Segment(id: "inside", title: "Old items", detail: "Builds and downloads untouched for a week or more, inside folders still in use. Click to list them one by one", bytes: r.inside.bytes, color: .insideTint, action: { model.showFreeUp(quietHours: 168) }))
            list.append(Segment(id: "rebuild", title: "Rebuildable", detail: "In use; the next build recreates it", bytes: r.rebuild.bytes, color: Verdict.rebuild.tint, action: { model.showFolders(filter: .rebuild) }))
            list.append(Segment(id: "check", title: "Review first", detail: "May hold something only here; look inside first", bytes: r.check.bytes, color: Verdict.check.tint, action: { model.showFolders(filter: .check) }))
            list.append(Segment(id: "keep", title: "Not for the Trash", detail: "App data, or takes no space here", bytes: r.keep.bytes, color: Verdict.keep.tint, action: { model.showFolders(filter: .keep) }))
            tracked = r.safe.bytes + r.inside.bytes + r.rebuild.bytes + r.check.bytes + r.keep.bytes
            let kept = model.keptSummary
            list.append(Segment(id: "kept", title: "Ignored by you", detail: "You chose to ignore or not scan these", bytes: kept.keptBytes + kept.offBytes, color: .ignored, action: { model.search = ""; model.categoryFilter = nil; model.section = .kept }))
            tracked += kept.keptBytes + kept.offBytes
        }
        list.append(Segment(id: "other", title: "Everything else", detail: "macOS, apps and folders it doesn't scan. Click to see what's in it", bytes: max(0, volume.used - tracked), color: Color.primary.opacity(0.16), action: { model.showingElsewhere = true }))
        list.append(Segment(id: "free", title: "Free", detail: "Space you have now", bytes: volume.free, color: .clear, outlined: true, action: nil))
        return list.filter { $0.bytes > 0 }
    }
    var body: some View {
        let r = model.reclaim
        let capacity = Double(max(model.volume?.total ?? 1, 1))
        let parts = segments
        func share(_ bytes: Int64) -> String {
            let fraction = Double(bytes) / capacity
            return fraction > 0 && fraction < 0.005 ? "under 1%" : fraction.formatted(.percent.precision(.fractionLength(0)))
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.total > 0 ? "You can get back about \(byteLabel(r.total))" : "Nothing to get back yet")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(r.total > 0 ? "\(byteLabel(r.safe.bytes)) safe, \(byteLabel(r.inside.bytes)) in old items, \(byteLabel(r.rebuild.bytes)) rebuildable. You remove it; nothing here deletes."
                         : "Scan your folders so Context Cleaner can see when each was last used.")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Picker("Map", selection: $byType) { Text("By answer").tag(false); Text("By type").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
            GeometryReader { geo in
                let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(part.color.opacity(hovered == nil || hovered == part.id ? 1 : 0.3))
                            .overlay { if part.outlined { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) } }
                            .frame(width: max(3, (geo.size.width - gaps) * Double(part.bytes) / capacity))
                            .contentShape(Rectangle())
                            .onHover { inside in hovered = inside ? part.id : (hovered == part.id ? nil : hovered) }
                            .onTapGesture { part.action?() }
                            .accessibilityElement().accessibilityLabel("\(part.title), \(byteLabel(part.bytes)), \(share(part.bytes)) of your disk").accessibilityAddTraits(part.action == nil ? [] : .isButton)
                    }
                }
            }.frame(height: 30)
            Group {
                if let id = hovered, let part = parts.first(where: { $0.id == id }) {
                    Text("\(part.title) · \(byteLabel(part.bytes)) · \(share(part.bytes)) of your disk · \(part.detail)" + (part.action == nil ? "" : " · click to list"))
                } else { Text("Your whole disk, \(byteLabel(Int64(capacity))). Point at a color for details; click it to list those folders.") }
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
                            .background(hovered == part.id ? part.color.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(part.action == nil)
                        .onHover { inside in hovered = inside ? part.id : (hovered == part.id ? nil : hovered) }
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Where used space went in the chart's range or selection. Select a place to see its folders.
struct WentPanel: View {
    @ObservedObject var model: CleanerModel
    @State private var selected: String?
    var body: some View {
        Panel(title: "Where the space went", symbol: "chart.bar.xaxis", tint: .growing) {
            let active = model.chartActiveWindow
            if let went = model.spaceWent(from: active.lowerBound, to: active.upperBound), let change = went.diskChange {
                let grew = Array(went.places.filter { $0.bytes >= 256 << 20 }.prefix(5))
                let shrank = Array(went.places.filter { $0.bytes <= -(256 << 20) }.sorted { $0.bytes < $1.bytes }.prefix(2))
                let named = (grew + shrank).reduce(Int64(0)) { $0 + $1.bytes }
                let outside = change - named
                let largest = Double(max((grew + shrank).map { abs($0.bytes) }.max() ?? 1, abs(outside), 1))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(change >= 0 ? "\(byteLabel(change)) more used" : "\(byteLabel(-change)) freed").font(.callout.weight(.semibold)).foregroundStyle(change >= 0 ? Color.growing : Color.stable)
                    Text("· about \(byteLabel(Int64(Double(abs(change)) / went.days))) a day · \(model.chartWindowPhrase)").font(.callout).foregroundStyle(.secondary)
                }.monospacedDigit()
                // Two groups around one center line: what grew reaches right, what was freed reaches left.
                let elsewhere = abs(outside) >= 1 << 30
                // A center line only when there's something on each side; otherwise bars use the full width.
                let split = (!grew.isEmpty || (elsewhere && outside > 0)) && (!shrank.isEmpty || (elsewhere && outside < 0))
                VStack(spacing: 2) {
                    if !grew.isEmpty || (elsewhere && outside > 0) {
                        heading("Grew", bytes: grew.reduce(Int64(0)) { $0 + $1.bytes } + (elsewhere && outside > 0 ? outside : 0), tint: .growing)
                        ForEach(grew) { place in placeRow(place, largest: largest, days: went.days, split: split) }
                        if elsewhere && outside > 0 { elsewhereRow(outside, largest: largest, days: went.days, split: split) }
                    }
                    if !shrank.isEmpty || (elsewhere && outside < 0) {
                        heading("Freed", bytes: -(shrank.reduce(Int64(0)) { $0 + $1.bytes } + (elsewhere && outside < 0 ? outside : 0)), tint: .stable)
                        ForEach(shrank) { place in placeRow(place, largest: largest, days: went.days, split: split) }
                        if elsewhere && outside < 0 { elsewhereRow(outside, largest: largest, days: went.days, split: split) }
                    }
                }
                Text((split ? "Bars reach right for space used, left for space freed. " : "") + "Click a place to see its folders. \"Everything else\" is outside the scanned folders; click it to look inside. The range follows the chart.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Needs disk readings from two times in this range. Context Cleaner notes disk space every hour while it's open.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private func rateText(_ bytes: Int64, days: Double) -> String { "\(byteLabel(Int64(Double(abs(bytes)) / days))) a day" }
    @ViewBuilder private func placeRow(_ place: SpaceChange, largest: Double, days: Double, split: Bool) -> some View {
        let open = selected == place.title
        Button { withAnimation(.easeOut(duration: 0.15)) { selected = open ? nil : place.title } } label: {
            bar(place.title, detail: ([rateText(place.bytes, days: days)] + (place.newFolders > 0 ? ["\(place.newFolders) new"] : []) + (place.removedFolders > 0 ? ["\(place.removedFolders) removed"] : [])).joined(separator: " · "), bytes: place.bytes, largest: largest, open: open, split: split)
        }.buttonStyle(.plain).accessibilityHint(open ? "Hides its folders" : "Shows its folders")
        if open {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(place.examples, id: \.path) { item in
                    Button { model.open(item.path) } label: {
                        HStack(spacing: 8) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            if let hint = locationHint(item.path) { Text(hint).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                            Spacer(minLength: 8)
                            Text((item.bytes >= 0 ? "grew " : "freed ") + byteLabel(abs(item.bytes))).monospacedDigit().foregroundStyle(item.bytes >= 0 ? Color.growing : .stable)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.font(.caption).padding(.vertical, 3).padding(.horizontal, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).pointingHand().help("Open in Folders")
                }
            }.padding(.leading, 18).padding(.bottom, 4)
        }
    }
    private func heading(_ title: String, bytes: Int64, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(byteLabel(bytes)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
        }.padding(.top, 6).padding(.leading, 24)
    }
    private func elsewhereRow(_ bytes: Int64, largest: Double, days: Double, split: Bool) -> some View {
        Button { model.showingElsewhere = true } label: {
            bar("Everything else", detail: rateText(bytes, days: days), bytes: bytes, largest: largest, open: false, opens: false, split: split)
        }.buttonStyle(.plain).help("See what's outside the scanned folders")
    }
    private func bar(_ title: String, detail: String?, bytes: Int64, largest: Double, open: Bool, opens: Bool = true, split: Bool) -> some View {
        let tint: Color = bytes >= 0 ? .growing : .stable
        return HStack(spacing: 10) {
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.tertiary).frame(width: 10)
                .opacity(opens ? 1 : 0)
            // One line per place: name, a bar from the center line, the amount, and the rate beside it.
            Text(title).font(.callout).lineLimit(1).frame(width: 160, alignment: .leading)
            GeometryReader { geo in
                let half = split ? geo.size.width / 2 : 0
                let width = max(3, (geo.size.width - half) * Double(abs(bytes)) / largest)
                ZStack(alignment: .leading) {
                    if split { Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 14).offset(x: half) }
                    RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.85)).frame(width: width, height: 8).offset(x: !split ? 0 : bytes >= 0 ? half + 1 : half - width)
                }.frame(height: 14)
            }.frame(height: 14)
            Text(byteLabel(abs(bytes))).font(.callout).monospacedDigit().foregroundStyle(tint).frame(width: 84, alignment: .trailing)
            Text(detail ?? "").font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).frame(width: 118, alignment: .trailing)
        }.padding(.vertical, 3).padding(.horizontal, 4)
            .background(open ? Color.secondary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(bytes >= 0 ? "grew" : "freed") \(byteLabel(abs(bytes)))")
    }
}
/// The Free Up Space page: freshness and free space in one line, then the list, which fills the window.
struct FreeUpView: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                StatusLine(model: model)
                StartPanel(model: model, listHeight: max(260, geometry.size.height - 230))
            }.padding(.horizontal, 22).padding(.bottom, 12)
        }
    }
}
/// On the Overview: what's waiting in Free Up Space, by what removing it costs, one click from it.
struct FreeUpSummary: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        let list = model.suggestionList
        let total = list.reduce(Int64(0)) { $0 + $1.bytes }
        let free = list.filter(\.losesNothing), review = list.filter { !$0.losesNothing }
        HStack(spacing: 14) {
            Image(systemName: "checklist").font(.title2).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(list.isEmpty ? "Nothing has sat untouched for \(quietPhrase(model.quietHours))" : "\(byteLabel(total)) you could get back now")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                HStack(spacing: 12) {
                    if !free.isEmpty { HStack(spacing: 5) { Circle().fill(Verdict.safe.tint).frame(width: 8, height: 8); Text("Nothing lost \(byteLabel(free.reduce(Int64(0)) { $0 + $1.bytes }))").monospacedDigit() } }
                    if !review.isEmpty { HStack(spacing: 5) { Circle().fill(Verdict.check.tint).frame(width: 8, height: 8); Text("Review first \(byteLabel(review.reduce(Int64(0)) { $0 + $1.bytes }))").monospacedDigit() } }
                    Text("\(list.count) \(list.count == 1 ? "item" : "items") untouched for \(quietPhrase(model.quietHours)) or longer").foregroundStyle(.secondary)
                }.font(.callout)
            }
            Spacer()
            Button { model.showFreeUp() } label: { Label("Free Up Space", systemImage: "arrow.right") }.buttonStyle(.borderedProminent)
                .help("Tick what to remove and copy one Terminal command")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background.secondary)
    }
}
struct KindGroup: Identifiable { let kind: String; let items: [Suggestion]; var id: String { kind } }
/// "12 hours", "a day", "3 days", "a week".
func quietPhrase(_ hours: Int) -> String {
    switch hours { case 12: return "12 hours"; case 24: return "a day"; case 72: return "3 days"; case 168: return "a week"; default: return hours >= 24 ? "\(hours / 24) days" : "\(hours) hours" }
}
/// What to remove now: one list, biggest first, each with what removing it costs.
/// The controls sit above the list, so Select All and Copy are in reach however long the list is.
struct StartPanel: View {
    @ObservedObject var model: CleanerModel
    var listHeight: CGFloat = 420
    /// Nothing lost (Safe to remove and Rebuildable together) or Review first; nil shows everything.
    @State private var filter: Bool?
    /// Groups the list by what each item is, each group with its own tick box.
    @AppStorage("freeUpByKind") private var byKind = false
    /// The row ticked or unticked last, for Shift-click ranges.
    @State private var anchor: String?
    var body: some View {
        let list = model.suggestionList
        let free = list.filter(\.losesNothing), review = list.filter { !$0.losesNothing }
        // A filter that's emptied, by a scan or a cleanup, falls back to everything.
        let active: Bool? = filter == true && free.isEmpty || filter == false && review.isEmpty ? nil : filter
        let filtered = active.map { $0 ? free : review } ?? list
        let groups = byKind ? kindGroups(filtered) : [KindGroup(kind: "", items: filtered)]
        let shown = groups.flatMap(\.items)
        let chosen = list.filter { model.selectedSuggestions.contains($0.path) }
        let chosenBytes = chosen.reduce(Int64(0)) { $0 + $1.bytes }
        let chosenReview = chosen.filter { !$0.losesNothing }
        let selectable = shown.filter { !$0.backup }
        let allTicked = !selectable.isEmpty && selectable.allSatisfy { model.selectedSuggestions.contains($0.path) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(list.isEmpty ? "Nothing has sat untouched that long" : byteLabel(list.reduce(Int64(0)) { $0 + $1.bytes }) + " you could get back")
                    .font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1)
                if !list.isEmpty { Text("\(list.count) \(list.count == 1 ? "item" : "items") untouched for \(quietPhrase(model.quietHours)) or longer").font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
                Spacer(minLength: 8)
                Text("Untouched for").font(.caption).foregroundStyle(.secondary).fixedSize()
                Picker("Untouched for", selection: $model.quietHours) {
                    Text("12 hours").tag(12); Text("1 day").tag(24); Text("3 days").tag(72); Text("1 week").tag(168)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            // Filters by what removing costs, each with its count and size; an empty one isn't shown.
            HStack(spacing: 6) {
                chip(nil, title: "All", tint: .accentColor, items: list, on: active == nil)
                if !free.isEmpty { chip(true, title: "Nothing lost", tint: Verdict.safe.tint, items: free, on: active == true) }
                if !review.isEmpty { chip(false, title: Verdict.check.title, tint: Verdict.check.tint, items: review, on: active == false) }
                Picker("Show", selection: $byKind) { Text("Biggest first").tag(false); Text("By kind").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().padding(.leading, 6)
                    .help("By kind groups the list, such as build output or Codex scratch, each group with its own tick box")
                Spacer(minLength: 0)
                trashStatus
            }
            Text(explanation(active)).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            // Select, total, copy: above the list, always in reach.
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { allTicked }, set: { on in
                    if on { model.selectedSuggestions.formUnion(selectable.map(\.path)) } else { model.selectedSuggestions.subtract(shown.map(\.path)) }
                })) {
                    Text(selectable.isEmpty ? "Nothing to select" : "Select all \(selectable.count) shown").font(.callout)
                }.toggleStyle(.checkbox).disabled(selectable.isEmpty)
                    .help("Ticks every row shown except backups, which you tick yourself.")
                if shown.contains(where: \.backup) {
                    Text("skips \(shown.filter(\.backup).count) \(shown.filter(\.backup).count == 1 ? "backup" : "backups")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if !chosen.isEmpty {
                    Text("\(chosen.count) ticked · \(byteLabel(chosenBytes))").font(.callout.weight(.semibold)).monospacedDigit()
                    Button("Clear") { model.selectedSuggestions = [] }.controlSize(.small)
                }
                TrashCopyButton(paths: chosen.map(\.path), bytes: chosenBytes, prominent: true, shortcut: true,
                                confirm: trashConfirmation(count: chosen.count, bytes: chosenBytes, review: chosenReview.count, reviewBytes: chosenReview.reduce(Int64(0)) { $0 + $1.bytes }))
            }.padding(.horizontal, 10).padding(.vertical, 7).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(groups) { group in
                        if byKind { groupHeader(group.kind, group.items) }
                        ForEach(group.items) { row($0, in: shown) }
                    }
                }.padding(.trailing, 6)
            }.frame(maxHeight: shown.isEmpty ? 40 : min(listHeight, CGFloat(shown.count) * 42 + CGFloat(byKind ? groups.count * 34 : 0) + 8))
                .overlay { if shown.isEmpty && !list.isEmpty { Text("Nothing in this list untouched that long.").font(.callout).foregroundStyle(.secondary) } }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.background.secondary)
    }
    private func explanation(_ active: Bool?) -> String {
        switch active {
        case true?: return "Removing these loses nothing. Safe to remove: not needed again. Rebuildable: the next build or download recreates it, so you wait for that. Shift-click ticks a range."
        case false?: return LocationFilter.check.explanation + " Shift-click ticks a range."
        case nil: return "Nothing lost: safe to remove, or recreated by the next build or download. Review first: may hold something that's only here, so look inside first. Shift-click ticks a range."
        }
    }
    /// Groups by kind, biggest group first; each group keeps biggest first.
    private func kindGroups(_ items: [Suggestion]) -> [KindGroup] {
        Dictionary(grouping: items, by: \.kind).map { KindGroup(kind: $0.key, items: $0.value) }
            .sorted { $0.items.reduce(Int64(0)) { $0 + $1.bytes } > $1.items.reduce(Int64(0)) { $0 + $1.bytes } }
    }
    private func groupHeader(_ kind: String, _ items: [Suggestion]) -> some View {
        let selectable = items.filter { !$0.backup }
        let ticked = !selectable.isEmpty && selectable.allSatisfy { model.selectedSuggestions.contains($0.path) }
        let some = items.contains { model.selectedSuggestions.contains($0.path) }
        let review = items.filter { !$0.losesNothing }.count
        return HStack(spacing: 10) {
            Toggle(kind, isOn: Binding(get: { ticked }, set: { on in
                if on { model.selectedSuggestions.formUnion(selectable.map(\.path)) } else { model.selectedSuggestions.subtract(items.map(\.path)) }
            })).toggleStyle(.checkbox).labelsHidden().disabled(selectable.isEmpty)
                .help(selectable.isEmpty ? "Backups are ticked one at a time" : "Ticks every \(kind.lowercased()) item here" + (selectable.count < items.count ? " except backups" : ""))
            Text(kind).font(.callout.weight(.semibold)) + Text(some && !ticked ? "  some ticked" : "").font(.caption).foregroundColor(.secondary)
            Text(review == 0 ? "nothing lost" : review == items.count ? "review first" : "\(review) to review first").font(.caption)
                .foregroundStyle(review == 0 ? Verdict.safe.tint : Verdict.check.tint)
            Spacer(minLength: 8)
            Text("\(items.count) · \(byteLabel(items.reduce(Int64(0)) { $0 + $1.bytes }))").font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }.padding(.top, 8).padding(.bottom, 2).frame(height: 32)
    }
    /// How much the Trash holds, beside the controls, since that's where everything goes and space only comes back once it's emptied.
    private var trashStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: "trash").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(model.trashBytes.map { "Trash holds \(byteLabel($0))" } ?? "Space comes back when you empty the Trash").monospacedDigit()
            Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: homeDirectory + "/.Trash")) }.buttonStyle(.link)
                .help("Opens the Trash in Finder. Space comes back when you empty it; Context Cleaner never does.")
        }.font(.caption).foregroundStyle(.secondary).fixedSize()
    }
    private func chip(_ value: Bool?, title: String, tint: Color, items: [Suggestion], on: Bool) -> some View {
        Button { withAnimation(.snappy(duration: 0.15)) { filter = value } } label: {
            HStack(spacing: 6) {
                if value != nil { Circle().fill(tint).frame(width: 8, height: 8) }
                Text(title).fontWeight(on ? .semibold : .regular)
                Text("\(items.count) · \(byteLabel(items.reduce(Int64(0)) { $0 + $1.bytes }))").foregroundStyle(.secondary).monospacedDigit()
            }.font(.callout).padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? tint.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? tint.opacity(0.6) : .clear))
                .contentShape(Capsule())
        }.buttonStyle(.plain).help(value == nil ? "Everything in the list" : value! ? "Safe to remove and Rebuildable: removing them loses nothing" : Verdict.check.title + ": " + LocationFilter.check.explanation)
    }
    private func row(_ s: Suggestion, in shown: [Suggestion]) -> some View {
        // The value is read here, not inside the binding, so the row redraws when it changes.
        let isTicked = model.selectedSuggestions.contains(s.path)
        let ticked = Binding(get: { isTicked }, set: { on in
            // Shift-click ticks or unticks every row between the last one you clicked and this one.
            var paths = [s.path]
            if NSEvent.modifierFlags.contains(.shift), let anchor, let a = shown.firstIndex(where: { $0.path == anchor }), let b = shown.firstIndex(where: { $0.path == s.path }) {
                paths = shown[min(a, b)...max(a, b)].map(\.path)
            }
            if on { model.selectedSuggestions.formUnion(paths) } else { model.selectedSuggestions.subtract(paths) }
            anchor = s.path
        })
        return HStack(spacing: 10) {
            Toggle(s.name, isOn: ticked).toggleStyle(.checkbox).labelsHidden()
            RoundedRectangle(cornerRadius: 2).fill(s.cost.tint).frame(width: 4, height: 30).accessibilityHidden(true)
            Button { model.open(s.owner ?? s.path) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(s.name).font(.callout).lineLimit(1).truncationMode(.middle)
                            if s.backup { Image(systemName: "lock.shield").font(.caption).foregroundStyle(Verdict.check.tint).help("Looks like a backup or save. Select All leaves it unticked.") }
                        }
                        // Cost and quiet time first; the location is the part that can be cut off.
                        (Text(s.cost.title).foregroundColor(s.cost.tint) + Text(" · " + ([s.why, s.place].compactMap { $0 }.joined(separator: " · "))).foregroundColor(.secondary))
                            .font(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(byteLabel(s.bytes)).font(.callout).monospacedDigit()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(abbreviatedPath(s.path))
        }.padding(.vertical, 2).frame(height: 40)
            .contextMenu { LocationActions(model: model, path: s.owner ?? s.path) }
    }
}
extension View {
    /// Shows the pointing hand over plain buttons that look like text.
    func pointingHand() -> some View { onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } } }
}

/// What "Everything else" is, and a read-only look inside it.
struct ElsewhereView: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let volumeUsed = model.volume?.used ?? 0
        let other = model.everythingElseBytes
        let found = model.elsewhere.compactMap(\.bytes).reduce(0, +)
        let largest = Double(max(model.elsewhere.compactMap(\.bytes).max() ?? 1, max(other - found, 1)))
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything else · \(byteLabel(other))").font(.title2.weight(.semibold))
            Text("Space outside the places Context Cleaner scans: macOS and its system data, your apps, Photos, Mail and Messages, local snapshots, and your own folders. It's sized each time you open this, biggest first; open any row to see what's in it. Projects say whether they're backed up.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.lookingElsewhere {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Sizing your home folder, Library and Applications. It reads sizes only and can take a few minutes. If macOS asks about other apps' data, sizing waits for your answer.").font(.callout).fixedSize(horizontal: false, vertical: true); Spacer(); Button("Stop") { model.stopLookingElsewhere() } }
            } else if model.elsewhere.isEmpty {
                HStack {
                    Button("Look Inside", systemImage: "magnifyingglass") { model.lookElsewhere() }.buttonStyle(.borderedProminent)
                    Text("Sizes the top-level folders of your home, Library and Applications, leaving out what's already scanned. It reads sizes only and saves nothing.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.elsewhere.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.elsewhere.prefix(40)) { item in ElsewhereRow(model: model, item: item, depth: 0, largest: largest) }
                        if other - found > 0 {
                            HStack(spacing: 8) {
                                Color.clear.frame(width: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("macOS, system data and the rest").font(.callout)
                                    Text("macOS itself, system caches and logs, local Time Machine snapshots, other users, and anything these folders couldn't read.").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                SizeBar(fraction: Double(other - found) / largest, color: Color.primary.opacity(0.16))
                                Text(byteLabel(other - found)).font(.callout).monospacedDigit().frame(width: 84, alignment: .trailing)
                                Color.clear.frame(width: 18)
                            }
                        }
                    }.padding(.trailing, 8)
                }.frame(minHeight: 260, maxHeight: 460)
                Text("Measured \(model.elsewhereDate?.formatted(date: .omitted, time: .shortened) ?? "") · \(byteLabel(found)) found in these folders, of \(byteLabel(volumeUsed)) used on your disk. These sizes aren't saved or used in any answer. Backed up means pushed as of the last fetch.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("To have Context Cleaner track a folder here, add it with File › Add Folder to Scan.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !model.elsewhere.isEmpty && !model.lookingElsewhere { Button("Look Again") { model.lookElsewhere() } }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 780)
        // Look on its own: an unknown 1.6 TiB isn't useful. Sizes stay for the session, so reopening is instant.
        .onAppear { if model.elsewhere.isEmpty && !model.lookingElsewhere { model.lookElsewhere() } }
    }
}
private struct SizeBar: View {
    let fraction: Double
    var color: Color = Color.secondary.opacity(0.5)
    var body: some View {
        GeometryReader { geo in RoundedRectangle(cornerRadius: 3).fill(color).frame(width: max(3, geo.size.width * min(1, max(0, fraction)))) }
            .frame(width: 150, height: 10)
    }
}
/// One place in Everything else. Opening it sizes what's inside, one level at a time.
private struct ElsewhereRow: View {
    @ObservedObject var model: CleanerModel
    let item: ElsewhereItem
    let depth: Int
    let largest: Double
    @State private var open = false
    private var openable: Bool { item.isFolder && item.bytes != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12).opacity(openable ? 1 : 0).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    if let line = subtitle { Text(line).font(.caption).foregroundStyle(tint).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let bytes = item.bytes {
                    SizeBar(fraction: Double(bytes) / largest)
                    Text(byteLabel(bytes)).font(.callout).monospacedDigit().frame(width: 84, alignment: .trailing)
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show in Finder").accessibilityLabel("Show in Finder")
            }
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            .help(item.path + (subtitle.map { "\n" + $0 } ?? ""))
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: open ? "Close" : "Open") { toggle() }
            if open { inside }
        }
    }
    private func toggle() {
        guard openable else { return }
        withAnimation(.snappy(duration: 0.18)) { open.toggle() }
        if open { model.openElsewhere(item.path) }
    }
    /// What it is, whether it's backed up, when it was last used, and what's scanned apart.
    private var subtitle: String? {
        var parts: [String] = []
        if let note = item.note { parts.append(note) }
        else if let backup = item.backup { parts.append(backup.line) }
        else if let about = item.about { parts.append(about) }
        if item.backup != nil || depth > 0, let used = item.lastUsed { parts.append("last used " + ageText(used)) }
        if item.scannedInside > 0 { parts.append("+\(byteLabel(item.scannedInside)) scanned") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var tint: Color {
        guard let backup = item.backup else { return .secondary }
        return backup.removable ? .stable : .caution
    }
    @ViewBuilder private var inside: some View {
        let indent = CGFloat(depth + 1) * 18 + 20
        if model.elsewhereOpening.contains(item.path) {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Sizing what's inside…").font(.caption).foregroundStyle(.secondary) }.padding(.leading, indent)
        } else if let children = model.elsewhereChildren[item.path] {
            let idle = idleBackedUp(children)
            if !idle.isEmpty {
                let bytes = idle.reduce(Int64(0)) { $0 + $1.totalBytes }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.icloud").foregroundStyle(Color.stable)
                    Text("\(idle.count) \(idle.count == 1 ? "project is" : "projects are") backed up and unchanged for a month: \(byteLabel(bytes)) with build folders. Nothing in \(idle.count == 1 ? "it" : "them") exists only on this Mac.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    TrashCopyButton(paths: idle.map(\.path), sizes: Dictionary(idle.map { ($0.path, $0.totalBytes) }, uniquingKeysWith: { a, _ in a }))
                }.padding(8).background(Color.stable.opacity(0.08), in: RoundedRectangle(cornerRadius: 6)).padding(.leading, indent)
            }
            if children.isEmpty {
                Text("Nothing else inside. What's here is scanned separately.").font(.caption).foregroundStyle(.secondary).padding(.leading, indent)
            }
            let biggest = Double(max(children.compactMap(\.bytes).max() ?? 1, 1))
            ForEach(children.prefix(30)) { child in AnyView(ElsewhereRow(model: model, item: child, depth: depth + 1, largest: biggest)) }
            if children.count > 30 { Text("and \(children.count - 30) smaller items").font(.caption).foregroundStyle(.secondary).padding(.leading, indent) }
        }
    }
}
