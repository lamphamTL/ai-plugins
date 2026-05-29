import SwiftUI

enum DisplayMode { case popover, window }

private enum AgentScope: String, CaseIterable, Identifiable {
    case all
    case main
    case subagent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All events"
        case .main: return "Main-agent only"
        case .subagent: return "Sub-agent only"
        }
    }
}

private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue: DisplayMode = .popover
}

extension EnvironmentValues {
    var displayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }
}

private struct RootSizeModifier: ViewModifier {
    let mode: DisplayMode
    func body(content: Content) -> some View {
        switch mode {
        case .popover:
            content
                .frame(width: 320)
                .fixedSize(horizontal: true, vertical: false)
        case .window:
            content
                .frame(minWidth: 320, minHeight: 400)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.displayMode) private var displayMode
    @State private var selectedKind: TimeRangeKind = .day
    @State private var scrollDate: Date = Self.initialScrollDate(for: .day)
    @State private var selectedProject: String? = nil
    @State private var selectedSource: String? = nil
    @State private var selectedModel: String? = nil
    @State private var selectedAgentScope: AgentScope = .all
    @State private var chartMode: ChartMode = .cost
    @State private var isHovering = false
    @State private var barCount: Int = 7
    @State private var chartData: ChartData = .empty
    @State private var pendingBarCount: Int? = nil
    @State private var resizeWorkItem: DispatchWorkItem? = nil
    @State private var didFirstRender = false

    private let sources = [("All", String?.none), ("Claude", "claude"), ("Codex", "codex")]

    private var availableChartModes: [ChartMode] {
        ChartMode.allCases.filter { mode in
            mode != .credits || selectedSource == "codex"
        }
    }

    @ViewBuilder
    private var chartModeMenu: some View {
        Menu {
            ForEach(availableChartModes) { mode in
                Button {
                    chartMode = mode
                } label: {
                    if chartMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chartMode == .cost ? .secondary : Color.green)
                .frame(width: 22, height: 22)
                .background(
                    chartMode == .cost
                        ? Color.primary.opacity(0.05)
                        : Color.green.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var sourcePicker: some View {
        HStack(spacing: 2) {
            ForEach(sources, id: \.0) { label, value in
                Button {
                    selectedSource = value
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            selectedSource == value
                                ? Color.primary.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSource == value ? .primary : .secondary)
            }
        }
        .padding(3)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .focusEffectDisabled()
    }

    // Target px per bar (incl. spacing). Keep bar width visually stable across resizes.
    private static let targetBarPx: CGFloat = 36
    // Subtract horizontal chart padding (14*2) + approximate y-axis label area.
    private func resolvedBarCount(width: CGFloat) -> Int {
        let plotWidth = max(width - 28 - 40, 100)
        return max(3, Int(plotWidth / Self.targetBarPx))
    }

    private func codexCycleRangeText(_ cycle: CodexCreditCycle) -> String {
        guard let start = cycle.start, let end = cycle.end else {
            return "Not enough usage to compute the current cycle"
        }
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        return "\(start.formatted(format)) - \(end.formatted(format))"
    }

    var body: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(spacing: 0) {
                // ── Header ───────────────────────────────────────────────
                HStack(alignment: .center, spacing: 8) {
                    if displayMode == .window {
                        Text("AI Usage")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.8))
                    }

                    Spacer()

                    // Range picker – compact segmented
                    HStack(spacing: 2) {
                        ForEach(TimeRangeKind.allCases) { kind in
                            Button {
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) {
                                    selectedKind = kind
                                    scrollDate = centeredScrollDate(for: kind, count: barCount)
                                }
                            } label: {
                                Text(displayMode == .popover ? kind.shortLabel : kind.rawValue)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        selectedKind == kind
                                            ? Color.primary.opacity(0.12)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedKind == kind ? .primary : .secondary)
                        }
                    }
                    .padding(3)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .focusEffectDisabled()

                    chartModeMenu

                    Menu {
                        if !sourceFilteredProjects.isEmpty {
                            Section("Project") {
                                Button {
                                    selectedProject = nil
                                } label: {
                                    if selectedProject == nil {
                                        Label("All projects", systemImage: "checkmark")
                                    } else {
                                        Text("All projects")
                                    }
                                }
                                ForEach(sourceFilteredProjects, id: \.self) { path in
                                    Button {
                                        selectedProject = path
                                    } label: {
                                        if selectedProject == path {
                                            Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "checkmark")
                                        } else {
                                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                        }
                                    }
                                }
                            }
                        }
                        if availableModels.count > 1 {
                            Section("Model") {
                                Button {
                                    selectedModel = nil
                                } label: {
                                    if selectedModel == nil {
                                        Label("All models", systemImage: "checkmark")
                                    } else {
                                        Text("All models")
                                    }
                                }
                                ForEach(availableModels, id: \.self) { model in
                                    Button {
                                        selectedModel = model
                                    } label: {
                                        if selectedModel == model {
                                            Label(model, systemImage: "checkmark")
                                        } else {
                                            Text(model)
                                        }
                                    }
                                }
                            }
                        }
                        Section("Agent") {
                            ForEach(AgentScope.allCases) { scope in
                                Button {
                                    selectedAgentScope = scope
                                } label: {
                                    if selectedAgentScope == scope {
                                        Label(scope.label, systemImage: "checkmark")
                                    } else {
                                        Text(scope.label)
                                    }
                                }
                            }
                        }
                        Section {
                            if isAnyFilterActive {
                                Button("Reset filters") {
                                    selectedProject = nil
                                    selectedModel = nil
                                    selectedAgentScope = .all
                                }
                            }
                            Button("Reload") {
                                store.refresh()
                            }
                            if displayMode == .popover {
                                Button("Open in window") {
                                    NotificationCenter.default.post(name: .init("com.lampham.tokenusage.popout"), object: nil)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: isAnyFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isAnyFilterActive ? Color.accentColor : .secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                isAnyFilterActive
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .overlay(alignment: .topTrailing) {
                                if isAnyFilterActive {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 1, y: -1)
                                }
                            }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .focusEffectDisabled()

                    // Close (popover only — window has traffic lights)
                    if displayMode == .popover {
                        Button {
                            NotificationCenter.default.post(name: .init("com.lampham.tokenusage.close"), object: nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary.opacity(isHovering ? 0.9 : 0.4))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering = $0 }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 4)

                // ── Source picker row ────────────────────────────────────
                HStack {
                    Spacer()
                    sourcePicker
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

                // ── Weekly credit tracker (Codex only) ───────────────────
                if selectedSource == "codex" {
                    let cycle  = store.codexCreditCycle
                    let used   = cycle.used
                    let limit  = 1000.0
                    let pct    = min(used / limit, 1.0)
                    let color: Color = pct >= 0.9 ? .red : pct >= 0.7 ? .yellow : .green
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Weekly credit")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if cycle.isActive {
                                Text(String(format: "%.1f / 1000", used))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(color)
                            }
                        }
                        Text(codexCycleRangeText(cycle))
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.primary.opacity(0.72))
                        if cycle.isActive {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.primary.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color.opacity(0.8))
                                        .frame(width: geo.size.width * pct)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }

                // ── Nav bar ───────────────────────────────────────────────
                CompactNavigationBar(
                    scrollDate: $scrollDate,
                    kind: selectedKind,
                    barCount: barCount,
                    visibleDuration: visibleDuration,
                    minDate: store.entries.first?.ts ?? Date(),
                    onResetToPresent: {
                        scrollDate = centeredScrollDate(for: selectedKind, count: barCount)
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 2)

                // ── Chart ─────────────────────────────────────────────────
                if store.isLoaded {
                    BarChartView(
                        data: chartData,
                        kind: selectedKind,
                        barCount: barCount,
                        scrollDate: scrollDate,
                        scrollDateBinding: $scrollDate,
                        projectColors: store.projectColors,
                        showCredits: selectedSource == "codex",
                        chartMode: chartMode
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateBarCount(width: geo.size.width) }
                    .onChange(of: geo.size.width) { _, w in updateBarCount(width: w) }
            }
        )
        .onAppear {
            guard !didFirstRender, store.isLoaded else { return }
            scrollDate = centeredScrollDate(for: selectedKind, count: barCount)
            chartData = computeChartData()
            didFirstRender = true
        }
        .onChange(of: store.isLoaded) { _, loaded in
            if loaded {
                scrollDate = centeredScrollDate(for: selectedKind, count: barCount)
                chartData = computeChartData()
                didFirstRender = true
            }
        }
        .onChange(of: selectedSource)  { _, _ in
            if let m = selectedModel, !availableModels.contains(m) {
                selectedModel = nil
            }
            if chartMode == .credits && selectedSource != "codex" {
                chartMode = .cost
            }
            chartData = computeChartData()
        }
        .onChange(of: selectedProject) { _, _ in chartData = computeChartData() }
        .onChange(of: selectedModel)   { _, _ in chartData = computeChartData() }
        .onChange(of: selectedAgentScope) { _, _ in chartData = computeChartData() }
        .onChange(of: selectedKind)    { _, _ in chartData = computeChartData() }
        .onChange(of: scrollDate)      { _, _ in chartData = computeChartData() }
        .onChange(of: barCount)        { _, _ in chartData = computeChartData() }
        .onChange(of: store.entries.count) { _, _ in chartData = computeChartData() }
        .modifier(RootSizeModifier(mode: displayMode))
    }

    private func updateBarCount(width: CGFloat) {
        let newCount = resolvedBarCount(width: width)
        guard newCount != barCount, newCount != pendingBarCount else { return }
        pendingBarCount = newCount

        resizeWorkItem?.cancel()
        let work = DispatchWorkItem {
            applyPendingBarCount()
        }
        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func applyPendingBarCount() {
        guard let newCount = pendingBarCount, newCount != barCount else {
            pendingBarCount = nil
            return
        }
        let wasAtPresent = scrollDate.addingTimeInterval(visibleDuration) >= Date()
        barCount = newCount
        if wasAtPresent {
            scrollDate = centeredScrollDate(for: selectedKind, count: newCount)
        }
        pendingBarCount = nil
    }

    // Default scroll position: anchored at present, unless data span < bar count,
    // in which case centre the data with empty buckets on both sides.
    private func centeredScrollDate(for kind: TimeRangeKind, count: Int) -> Date {
        let presentAnchored = TimeWindow.initialScrollDate(for: kind, count: count)
        guard let firstEntry = store.entries.first else { return presentAnchored }

        var cal = Calendar.current
        if kind == .week { cal.firstWeekday = 2 }
        let comp = kind.bucketComponent

        guard let dataStart = cal.dateInterval(of: comp, for: firstEntry.ts)?.start else { return presentAnchored }
        let lastTs = store.entries.last?.ts ?? Date()
        let dataEnd = cal.dateInterval(of: comp, for: lastTs)?.start ?? dataStart

        let spanBuckets = (cal.dateComponents([comp], from: dataStart, to: dataEnd).value(for: comp) ?? 0) + 1
        guard spanBuckets < count else { return presentAnchored }

        let leftPad = (count - spanBuckets) / 2
        return cal.date(byAdding: comp, value: -leftPad, to: dataStart) ?? dataStart
    }

    private var barDuration: TimeInterval {
        switch selectedKind {
        case .day:   return 24 * 3600
        case .week:  return 7  * 24 * 3600
        case .month: return 31 * 24 * 3600
        }
    }

    private var visibleDuration: TimeInterval {
        Double(max(barCount, 1)) * barDuration
    }

    // Source+project+model filtered slice — uses pre-indexed store caches
    private var filteredEntries: [UsageEntry] {
        let base: [UsageEntry]
        if let src = selectedSource {
            base = store.entriesBySource[src] ?? []
        } else {
            base = store.entries
        }
        let byProject: [UsageEntry]
        if let proj = selectedProject {
            byProject = base.filter { $0.project == proj }
        } else {
            byProject = base
        }
        let byModel: [UsageEntry]
        if let m = selectedModel {
            byModel = byProject.filter { $0.model == m }
        } else {
            byModel = byProject
        }

        switch selectedAgentScope {
        case .all:
            return byModel
        case .main:
            return byModel.filter { !$0.isSubAgent }
        case .subagent:
            return byModel.filter { $0.isSubAgent }
        }
    }

    // Time-window slice via binary search — O(log n + k)
    private var visibleEntries: [UsageEntry] {
        let entries = filteredEntries
        guard !entries.isEmpty else { return [] }
        var cal = Calendar.current
        if selectedKind == .week { cal.firstWeekday = 2 }
        let end = cal.date(byAdding: selectedKind.bucketComponent,
                           value: barCount,
                           to: scrollDate) ?? scrollDate.addingTimeInterval(visibleDuration)
        let lo = lowerBound(entries, target: scrollDate)
        let hi = lowerBound(entries, target: end)
        guard lo < hi else { return [] }
        return Array(entries[lo..<hi])
    }

    private func lowerBound(_ entries: [UsageEntry], target: Date) -> Int {
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].ts < target { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // Pre-bucketed chart data — only 5-7 ChartPoints passed to BarChartView
    private func computeChartData() -> ChartData {
        let visible = visibleEntries
        guard !visible.isEmpty else { return .empty }

        let calendar = Calendar.current
        let component = selectedKind.bucketComponent
        let multiSource = Set(visible.map(\.source)).count > 1

        var grouped: [Date: [String: (cost: Double, credits: Double, tokens: Int, count: Int, source: String)]] = [:]
        var bucketCounts: [Date: Int] = [:]
        var bucketCredits: [Date: Double] = [:]
        var bucketCacheRead:  [Date: Int] = [:]
        var bucketCacheTotal: [Date: Int] = [:]

        for entry in visible {
            guard let interval = calendar.dateInterval(of: component, for: entry.ts) else { continue }
            let bucket = interval.start
            let proj = entry.projectDisplayName
            let key = multiSource ? "\(proj) (\(entry.source))" : proj
            let prev = grouped[bucket]?[key] ?? (cost: 0, credits: 0, tokens: 0, count: 0, source: entry.source)
            grouped[bucket, default: [:]][key] = (
                cost:   prev.cost + entry.cost_usd,
                credits: prev.credits + (entry.credits ?? 0),
                tokens: prev.tokens + entry.tokens.total,
                count:  prev.count + 1,
                source: entry.source
            )
            bucketCounts[bucket, default: 0] += 1
            if let cr = entry.credits { bucketCredits[bucket, default: 0] += cr }
            let t = entry.tokens
            bucketCacheRead[bucket,  default: 0] += t.cache_read
            bucketCacheTotal[bucket, default: 0] += t.cache_read + (t.cache_write ?? 0) + t.input
        }

        var points: [ChartPoint] = []
        for (date, projects) in grouped {
            for (key, agg) in projects {
                points.append(ChartPoint(bucketDate: date, project: key, source: agg.source,
                                         cost: agg.cost, credits: agg.credits, totalTokens: agg.tokens,
                                         eventCount: agg.count))
            }
        }
        points.sort { $0.bucketDate == $1.bucketDate ? $0.project < $1.project : $0.bucketDate < $1.bucketDate }

        return ChartData(
            points: points,
            totalCost: visible.reduce(0) { $0 + $1.cost_usd },
            totalCredits: visible.compactMap(\.credits).reduce(0, +),
            totalEntries: visible.count,
            bucketCounts: bucketCounts,
            bucketCredits: bucketCredits,
            bucketCacheRead: bucketCacheRead,
            bucketCacheTotal: bucketCacheTotal
        )
    }

    private var sourceFilteredProjects: [String] {
        if let src = selectedSource {
            return store.projectsBySource[src] ?? []
        }
        let all = store.projectsBySource.values.flatMap { $0 }
        return Array(Set(all)).sorted {
            URL(fileURLWithPath: $0).lastPathComponent < URL(fileURLWithPath: $1).lastPathComponent
        }
    }

    private var availableModels: [String] {
        if let src = selectedSource {
            return store.modelsBySource[src] ?? []
        }
        let all = store.modelsBySource.values.flatMap { $0 }
        return Array(Set(all)).sorted()
    }

    private var isAnyFilterActive: Bool {
        selectedProject != nil || selectedModel != nil || selectedAgentScope != .all
    }

    private static func initialScrollDate(for kind: TimeRangeKind) -> Date {
        TimeWindow.initialScrollDate(for: kind)
    }
}
