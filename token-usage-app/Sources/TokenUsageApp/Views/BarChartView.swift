import SwiftUI
import Charts

enum ChartMode: String, CaseIterable, Identifiable {
    case cost
    case credits
    case efficiency
    case eventCount
    case cacheHitRate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cost:         return "Spend"
        case .credits:      return "Credits"
        case .efficiency:   return "Cost per event"
        case .eventCount:   return "Event count"
        case .cacheHitRate: return "Cache hit"
        }
    }

    var icon: String {
        switch self {
        case .cost:         return "dollarsign"
        case .credits:      return "creditcard"
        case .efficiency:   return "chart.line.uptrend.xyaxis"
        case .eventCount:   return "number"
        case .cacheHitRate: return "memorychip"
        }
    }
}

struct ChartPoint: Identifiable {
    var id: String { "\(bucketDate.timeIntervalSinceReferenceDate)-\(project)-\(source)" }
    let bucketDate: Date
    let project: String
    let source: String
    let cost: Double
    let credits: Double
    let totalTokens: Int
    let eventCount: Int
}

// Pre-computed chart data passed from ContentView — no raw entries inside BarChartView
struct ChartData {
    let points: [ChartPoint]
    let totalCost: Double
    let totalCredits: Double        // 0 for Claude (no credits field)
    let totalEntries: Int
    let bucketCounts: [Date: Int]
    let bucketCredits: [Date: Double]
    let bucketCacheRead:  [Date: Int]   // numerator for cache hit rate
    let bucketCacheTotal: [Date: Int]   // denominator = cache_read + cache_write_5m + cache_write_1h + input

    static let empty = ChartData(points: [], totalCost: 0, totalCredits: 0,
                                 totalEntries: 0, bucketCounts: [:], bucketCredits: [:],
                                 bucketCacheRead: [:], bucketCacheTotal: [:])
}

struct BarChartView: View {
    let data: ChartData
    let kind: TimeRangeKind
    let barCount: Int
    let scrollDate: Date            // for x-axis domain
    @Binding var scrollDateBinding: Date
    let projectColors: [String: Int]
    var showCredits: Bool = false
    var chartMode: ChartMode = .cost
    var useUTCDateRange: Bool = false

    @Environment(\.displayMode) private var displayMode

    private var chartMinHeight: CGFloat { 150 }
    private var chartMaxHeight: CGFloat { displayMode == .window ? 280 : 150 }

    private static let palette: [Color] = [
        .blue, .purple, .orange, .teal, .pink, .indigo, .mint
    ]

    // Strip " (claude)" / " (codex)" suffix that's appended when the visible
    // window spans multiple sources, so colour lookup keys to the base project.
    private static let sourceSuffixes = [" (claude)", " (codex)"]
    private func baseProjectKey(_ key: String) -> String {
        for suffix in Self.sourceSuffixes where key.hasSuffix(suffix) {
            return String(key.dropLast(suffix.count))
        }
        return key
    }

    private func colorFor(_ projectKey: String) -> Color {
        let base = baseProjectKey(projectKey)
        if let idx = projectColors[base] {
            return Self.palette[idx % Self.palette.count]
        }
        return Self.palette[abs(base.hashValue) % Self.palette.count]
    }

    @State private var selectedBucket: Date? = nil

    private var barDuration: TimeInterval {
        switch kind {
        case .day:   return 24 * 3600
        case .week:  return 7  * 24 * 3600
        case .month: return 31 * 24 * 3600
        }
    }

    private var visibleDuration: TimeInterval {
        Double(max(barCount, 1)) * barDuration
    }

    private var visibleEnd: Date { scrollDate.addingTimeInterval(visibleDuration) }
    private var dateDisplayCalendar: Calendar {
        useUTCDateRange ? Calendar.cycleAnchored : Calendar.current
    }
    private var dateDisplayTimeZone: TimeZone {
        dateDisplayCalendar.timeZone
    }

    // One bar per bucket: total cost / event count
    private var efficiencyPoints: [ChartPoint] {
        var bucketCosts: [Date: Double] = [:]
        for point in data.points {
            bucketCosts[point.bucketDate, default: 0] += point.cost
        }
        return bucketCosts.compactMap { date, cost in
            guard let count = data.bucketCounts[date], count > 0 else { return nil }
            return ChartPoint(bucketDate: date, project: "avg", source: "",
                              cost: cost / Double(count), credits: 0, totalTokens: 0, eventCount: count)
        }.sorted { $0.bucketDate < $1.bucketDate }
    }

    private var cacheHitRatePoints: [ChartPoint] {
        data.bucketCacheTotal.compactMap { date, total in
            guard total > 0 else { return nil }
            let read = data.bucketCacheRead[date] ?? 0
            let pct  = Double(read) / Double(total) * 100   // 0…100
            return ChartPoint(bucketDate: date, project: "rate", source: "",
                              cost: pct, credits: 0, totalTokens: 0, eventCount: 0)
        }.sorted { $0.bucketDate < $1.bucketDate }
    }

    private var activePoints: [ChartPoint] {
        switch chartMode {
        case .efficiency:   return efficiencyPoints
        case .cacheHitRate: return cacheHitRatePoints
        default:            return data.points
        }
    }

    // Selected-bucket aggregate, semantics depend on mode.
    private var selectedBucketCost: Double? {
        guard let bucket = selectedBucket else { return nil }
        let matching = data.points.filter { $0.bucketDate == bucket }
        return matching.isEmpty ? nil : matching.reduce(0) { $0 + $1.cost }
    }

    private var selectedBucketCredits: Double? {
        guard let bucket = selectedBucket else { return nil }
        let matching = data.points.filter { $0.bucketDate == bucket }
        return matching.isEmpty ? nil : matching.reduce(0) { $0 + $1.credits }
    }

    private var selectedBucketEfficiency: Double? {
        guard let bucket = selectedBucket else { return nil }
        let matching = efficiencyPoints.first(where: { $0.bucketDate == bucket })
        return matching?.cost
    }

    private var selectedBucketCacheHitRate: Double? {
        guard let bucket = selectedBucket else { return nil }
        return cacheHitRatePoints.first(where: { $0.bucketDate == bucket })?.cost
    }

    private var selectedBucketEventCount: Int? {
        guard let bucket = selectedBucket else { return nil }
        return data.bucketCounts[bucket]
    }

    private var overallEfficiency: Double {
        guard data.totalEntries > 0 else { return 0 }
        return data.totalCost / Double(data.totalEntries)
    }

    private var overallCacheHitRate: Double {
        let totalRead  = data.bucketCacheRead.values.reduce(0, +)
        let totalDenom = data.bucketCacheTotal.values.reduce(0, +)
        guard totalDenom > 0 else { return 0 }
        return Double(totalRead) / Double(totalDenom) * 100
    }

    private var allProjects: [String] { Array(Set(data.points.map(\.project))).sorted() }

    @ViewBuilder
    private func dayLabel(for date: Date) -> some View {
        let isToday = useUTCDateRange
            ? dateDisplayCalendar.isDate(date, inSameDayAs: Date())
            : Calendar.current.isDateInToday(date)
        if isToday {
            Text("Today")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
        } else {
            VStack(spacing: 1) {
                Text(dayLabelWeekdayText(for: date))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(dayLabelDayText(for: date))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func dayLabelWeekdayText(for date: Date) -> String {
        if useUTCDateRange {
            return DateDisplayFormatting.weekday(date, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func dayLabelDayText(for date: Date) -> String {
        if useUTCDateRange {
            return DateDisplayFormatting.day(date, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
        }
        return date.formatted(.dateTime.day())
    }

    @ViewBuilder
    private func weekLabel(for date: Date) -> some View {
        VStack(spacing: 1) {
            Text(weekLabelMonthText(for: date))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(weekLabelDayText(for: date))
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func weekLabelMonthText(for date: Date) -> String {
        if useUTCDateRange {
            return DateDisplayFormatting.month(date, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private func weekLabelDayText(for date: Date) -> String {
        if useUTCDateRange {
            return DateDisplayFormatting.day(date, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
        }
        return date.formatted(.dateTime.day())
    }

    private func monthLabelText(for date: Date) -> String {
        if useUTCDateRange {
            return DateDisplayFormatting.month(date, calendar: dateDisplayCalendar, timeZone: dateDisplayTimeZone)
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private func hitBucket(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        guard let frame = proxy.plotFrame else { return nil }
        let origin = geo[frame].origin
        let xInPlot = location.x - origin.x
        let yInPlot = location.y - origin.y

        guard let clickedDate = proxy.value(atX: xInPlot, as: Date.self),
              let clickedValue = proxy.value(atY: yInPlot, as: Double.self),
              clickedValue >= 0
        else { return nil }

        let cal = Calendar.cycleAnchored
        guard let interval = cal.dateInterval(of: kind.bucketComponent, for: clickedDate) else { return nil }
        let bucketStart = interval.start

        switch chartMode {
        case .efficiency, .cacheHitRate:
            // Line chart: accept tap anywhere in the bucket column
            return activePoints.contains { $0.bucketDate == bucketStart } ? bucketStart : nil
        case .cost:
            let bucketTotal = activePoints.filter { $0.bucketDate == bucketStart }.reduce(0.0) { $0 + $1.cost }
            guard bucketTotal > 0, clickedValue <= bucketTotal else { return nil }
            return bucketStart
        case .credits:
            let bucketTotal = activePoints.filter { $0.bucketDate == bucketStart }.reduce(0.0) { $0 + $1.credits }
            guard bucketTotal > 0, clickedValue <= bucketTotal else { return nil }
            return bucketStart
        case .eventCount:
            let bucketTotal = data.bucketCounts[bucketStart] ?? 0
            guard bucketTotal > 0, clickedValue <= Double(bucketTotal) else { return nil }
            return bucketStart
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch chartMode {
            case .efficiency:
                efficiencyChart
            case .cost:
                costChart
            case .credits:
                creditsChart
            case .eventCount:
                eventCountChart
            case .cacheHitRate:
                cacheHitRateChart
            }

            // ── Footer ─────────────────────────────────────────────────
            ZStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    primaryFooterMetric
                    Spacer()
                    if chartMode != .efficiency && chartMode != .cacheHitRate {
                        let count = selectedBucketEventCount ?? data.totalEntries
                        Text("\(count) event\(count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                if showCredits && chartMode == .cost {
                    let displayCredits = selectedBucket.flatMap { data.bucketCredits[$0] } ?? data.totalCredits
                    Text(String(format: "%.2f cr", displayCredits))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.yellow.opacity(0.85))
                }
            }
            .frame(minHeight: 32, alignment: .top)
            .overlay(alignment: .bottomTrailing) {
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                Text("v\(appVersion)")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .animation(.easeInOut(duration: 0.2), value: selectedBucket)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var primaryFooterMetric: some View {
        switch chartMode {
        case .cost:
            let displayCost = selectedBucketCost ?? data.totalCost
            Text(String(format: "$%.4f", displayCost))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        case .credits:
            let displayCredits = selectedBucketCredits ?? data.totalCredits
            Text(String(format: "%.2f cr", displayCredits))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.yellow)
        case .efficiency:
            let displayAvg = selectedBucketEfficiency ?? overallEfficiency
            Text(String(format: "$%.4f/event", displayAvg))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.green)
        case .eventCount:
            let count = selectedBucketEventCount ?? data.totalEntries
            Text("\(count)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        case .cacheHitRate:
            let pct = selectedBucketCacheHitRate ?? overallCacheHitRate
            Text(String(format: "%.1f%% cache hit", pct))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(pct >= 70 ? Color.green : pct >= 40 ? Color.yellow : Color.red)
        }
    }

    // MARK: - Chart variants

    private var commonXScale: ClosedRange<Date> {
        scrollDate.addingTimeInterval(-barDuration / 2) ... visibleEnd.addingTimeInterval(barDuration / 2)
    }

    @ViewBuilder
    private var costChart: some View {
        Chart(data.points) { point in
            BarMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("Cost", point.cost)
            )
            .foregroundStyle(by: .value("Project", point.project))
            .cornerRadius(3)
            .opacity(selectedBucket == nil || selectedBucket == point.bucketDate ? 1.0 : 0.3)
        }
        .chartForegroundStyleScale(domain: allProjects, range: allProjects.map { colorFor($0) })
        .chartXAxis { categoricalXAxis }
        .chartYAxis { costYAxis }
        .chartXScale(domain: commonXScale)
        .chartLegend(.hidden)
        .frame(minHeight: chartMinHeight, maxHeight: chartMaxHeight)
        .animation(nil, value: kind)
        .animation(nil, value: scrollDate)
        .animation(nil, value: barCount)
        .chartOverlay { proxy in tapOverlay(proxy: proxy) }
        .environment(\.calendar, dateDisplayCalendar)
        .environment(\.timeZone, dateDisplayTimeZone)
        .onChange(of: scrollDate) { _, _ in selectedBucket = nil }
        .onChange(of: kind)       { _, _ in selectedBucket = nil }
        .onChange(of: chartMode)  { _, _ in selectedBucket = nil }
    }

    @ViewBuilder
    private var creditsChart: some View {
        Chart(data.points) { point in
            BarMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("Credits", point.credits)
            )
            .foregroundStyle(by: .value("Project", point.project))
            .cornerRadius(3)
            .opacity(selectedBucket == nil || selectedBucket == point.bucketDate ? 1.0 : 0.3)
        }
        .chartForegroundStyleScale(domain: allProjects, range: allProjects.map { colorFor($0) })
        .chartXAxis { categoricalXAxis }
        .chartYAxis { creditsYAxis }
        .chartXScale(domain: commonXScale)
        .chartLegend(.hidden)
        .frame(minHeight: chartMinHeight, maxHeight: chartMaxHeight)
        .animation(nil, value: kind)
        .animation(nil, value: scrollDate)
        .animation(nil, value: barCount)
        .chartOverlay { proxy in tapOverlay(proxy: proxy) }
        .environment(\.calendar, dateDisplayCalendar)
        .environment(\.timeZone, dateDisplayTimeZone)
        .onChange(of: scrollDate) { _, _ in selectedBucket = nil }
        .onChange(of: kind)       { _, _ in selectedBucket = nil }
        .onChange(of: chartMode)  { _, _ in selectedBucket = nil }
    }

    @ViewBuilder
    private var eventCountChart: some View {
        Chart(data.points) { point in
            BarMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("Events", point.eventCount)
            )
            .foregroundStyle(by: .value("Project", point.project))
            .cornerRadius(3)
            .opacity(selectedBucket == nil || selectedBucket == point.bucketDate ? 1.0 : 0.3)
        }
        .chartForegroundStyleScale(domain: allProjects, range: allProjects.map { colorFor($0) })
        .chartXAxis { categoricalXAxis }
        .chartYAxis { eventCountYAxis }
        .chartXScale(domain: commonXScale)
        .chartLegend(.hidden)
        .frame(minHeight: chartMinHeight, maxHeight: chartMaxHeight)
        .animation(nil, value: kind)
        .animation(nil, value: scrollDate)
        .animation(nil, value: barCount)
        .chartOverlay { proxy in tapOverlay(proxy: proxy) }
        .environment(\.calendar, dateDisplayCalendar)
        .environment(\.timeZone, dateDisplayTimeZone)
        .onChange(of: scrollDate) { _, _ in selectedBucket = nil }
        .onChange(of: kind)       { _, _ in selectedBucket = nil }
        .onChange(of: chartMode)  { _, _ in selectedBucket = nil }
    }

    @ViewBuilder
    private var efficiencyChart: some View {
        Chart(efficiencyPoints) { point in
            LineMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("$/event", point.cost)
            )
            .foregroundStyle(Color.green.opacity(0.85))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("$/event", point.cost)
            )
            .foregroundStyle(selectedBucket == nil || selectedBucket == point.bucketDate
                ? Color.green
                : Color.green.opacity(0.3))
            .symbolSize(selectedBucket == point.bucketDate ? 60 : 30)
        }
        .chartXAxis { categoricalXAxis }
        .chartYAxis { efficiencyYAxis }
        .chartXScale(domain: commonXScale)
        .chartLegend(.hidden)
        .frame(minHeight: chartMinHeight, maxHeight: chartMaxHeight)
        .animation(nil, value: kind)
        .animation(nil, value: scrollDate)
        .animation(nil, value: barCount)
        .chartOverlay { proxy in tapOverlay(proxy: proxy) }
        .environment(\.calendar, dateDisplayCalendar)
        .environment(\.timeZone, dateDisplayTimeZone)
        .onChange(of: scrollDate) { _, _ in selectedBucket = nil }
        .onChange(of: kind)       { _, _ in selectedBucket = nil }
        .onChange(of: chartMode)  { _, _ in selectedBucket = nil }
    }

    @ViewBuilder
    private var cacheHitRateChart: some View {
        Chart(cacheHitRatePoints) { point in
            LineMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("Cache hit %", point.cost)
            )
            .foregroundStyle(Color.cyan.opacity(0.85))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Time", point.bucketDate, unit: kind.bucketComponent),
                y: .value("Cache hit %", point.cost)
            )
            .foregroundStyle(selectedBucket == nil || selectedBucket == point.bucketDate
                ? Color.cyan
                : Color.cyan.opacity(0.3))
            .symbolSize(selectedBucket == point.bucketDate ? 60 : 30)
        }
        .chartXAxis { categoricalXAxis }
        .chartYAxis { cacheHitRateYAxis }
        .chartXScale(domain: commonXScale)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .frame(minHeight: chartMinHeight, maxHeight: chartMaxHeight)
        .animation(nil, value: kind)
        .animation(nil, value: scrollDate)
        .animation(nil, value: barCount)
        .chartOverlay { proxy in tapOverlay(proxy: proxy) }
        .environment(\.calendar, dateDisplayCalendar)
        .environment(\.timeZone, dateDisplayTimeZone)
        .onChange(of: scrollDate) { _, _ in selectedBucket = nil }
        .onChange(of: kind)       { _, _ in selectedBucket = nil }
        .onChange(of: chartMode)  { _, _ in selectedBucket = nil }
    }

    @ViewBuilder
    private func tapOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { location in
                    if let bucket = hitBucket(at: location, proxy: proxy, geo: geo) {
                        selectedBucket = (selectedBucket == bucket) ? nil : bucket
                    } else {
                        selectedBucket = nil
                    }
                }
        }
    }

    @AxisContentBuilder
    private var categoricalXAxis: some AxisContent {
        AxisMarks(values: .stride(by: kind.bucketComponent)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(0.18))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    if kind == .day {
                        dayLabel(for: date)
                    } else if kind == .week {
                        weekLabel(for: date)
                    } else {
                        Text(monthLabelText(for: date))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    @AxisContentBuilder
    private var costYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(0.18))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(String(format: "$%.0f", v))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @AxisContentBuilder
    private var creditsYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(0.18))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(String(format: "%.0f", v))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @AxisContentBuilder
    private var efficiencyYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(0.18))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(String(format: "$%.4f", v))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @AxisContentBuilder
    private var eventCountYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(0.18))
            AxisValueLabel {
                if let v = value.as(Int.self) {
                    Text("\(v)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @AxisContentBuilder
    private var cacheHitRateYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(0.18))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(String(format: "%.0f%%", v))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
