import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var entries: [UsageEntry] = []
    @Published private(set) var isLoaded = false

    // Pre-indexed caches — updated once when entries change, not on every render
    @Published private(set) var entriesBySource: [String: [UsageEntry]] = [:]
    @Published private(set) var projectsBySource: [String: [String]] = [:]
    @Published private(set) var modelsBySource: [String: [String]] = [:]
    @Published private(set) var weeklyCodexCredits: Double = 0
    @Published private(set) var codexCreditCycle: CodexCreditCycle = .inactive
    // Stable palette index per projectDisplayName, persisted across launches.
    @Published private(set) var projectColors: [String: Int] = [:]
    private static let projectColorsKey = "projectColorIndex"

    private var claudeWatcher: FileWatcher?
    private var codexWatcher: FileWatcher?
    private var claudeLineBuffer = ""
    private var codexLineBuffer = ""
    private var creditCycleTimer: AnyCancellable?

    nonisolated static let home = FileManager.default.homeDirectoryForCurrentUser
    nonisolated init() {}
    nonisolated static let claudeURL: URL = home.appendingPathComponent(".claude/token-usage/usage.jsonl")
    nonisolated static let codexURL:  URL = home.appendingPathComponent(".codex/token-usage/usage.jsonl")

    func load() {
        startCreditCycleTimer()

        if let saved = UserDefaults.standard.dictionary(forKey: Self.projectColorsKey) as? [String: Int] {
            projectColors = saved
        }

        let cw = FileWatcher(url: UsageStore.claudeURL)
        cw.onNewData = { [weak self] data in
            Task { @MainActor [weak self] in self?.ingest(data: data, source: "claude") }
        }
        cw.onReload = { [weak self] data in
            Task { @MainActor [weak self] in self?.reload(data: data, source: "claude") }
        }
        let claudeInitial = cw.start()
        claudeWatcher = cw

        let dw = FileWatcher(url: UsageStore.codexURL)
        dw.onNewData = { [weak self] data in
            Task { @MainActor [weak self] in self?.ingest(data: data, source: "codex") }
        }
        dw.onReload = { [weak self] data in
            Task { @MainActor [weak self] in self?.reload(data: data, source: "codex") }
        }
        let codexInitial = dw.start()
        codexWatcher = dw

        // Decode + derive caches entirely off the main thread
        Task.detached { [weak self] in
            let decoder = JSONDecoder.usageDecoder
            func decode(_ data: Data, source: String) -> [UsageEntry] {
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return [] }
                var lines = text.components(separatedBy: "\n")
                lines.removeLast()
                return lines.filter { !$0.isEmpty }.compactMap { line -> UsageEntry? in
                    guard let d = line.data(using: .utf8),
                          var e = try? decoder.decode(UsageEntry.self, from: d) else { return nil }
                    e.source = source
                    return e
                }
            }
            let all = (decode(claudeInitial, source: "claude") + decode(codexInitial, source: "codex"))
                .sorted { $0.ts < $1.ts }
            let derived = UsageStore.buildDerived(from: all)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries             = all
                self.entriesBySource     = derived.bySource
                self.projectsBySource    = derived.projects
                self.modelsBySource      = derived.models
                self.codexCreditCycle    = derived.codexCreditCycle
                self.weeklyCodexCredits  = derived.codexCreditCycle.used
                self.assignMissingProjectColors(for: all)
                self.isLoaded            = true
            }
        }
    }

    func refresh() {
        claudeWatcher?.stop()
        codexWatcher?.stop()
        claudeWatcher = nil
        codexWatcher = nil
        creditCycleTimer?.cancel()
        creditCycleTimer = nil
        claudeLineBuffer = ""
        codexLineBuffer = ""
        entries = []
        entriesBySource = [:]
        projectsBySource = [:]
        modelsBySource = [:]
        weeklyCodexCredits = 0
        codexCreditCycle = .inactive
        isLoaded = false
        load()
    }

    private func assignMissingProjectColors(for entries: [UsageEntry]) {
        let names = Set(entries.map(\.projectDisplayName))
        var map = projectColors
        var nextIdx = (map.values.max() ?? -1) + 1
        var changed = false
        for name in names where map[name] == nil {
            map[name] = nextIdx
            nextIdx += 1
            changed = true
        }
        guard changed else { return }
        projectColors = map
        UserDefaults.standard.set(map, forKey: Self.projectColorsKey)
    }

    private func reload(data: Data, source: String) {
        if source == "claude" { claudeLineBuffer = "" } else { codexLineBuffer = "" }

        let decoder = JSONDecoder.usageDecoder
        var lines = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n")
        let remainder = lines.removeLast()
        if source == "claude" { claudeLineBuffer = remainder } else { codexLineBuffer = remainder }

        let fresh = lines.filter { !$0.isEmpty }.compactMap { line -> UsageEntry? in
            guard let d = line.data(using: .utf8),
                  var e = try? decoder.decode(UsageEntry.self, from: d) else { return nil }
            e.source = source
            return e
        }

        entries.removeAll { $0.source == source }
        entries.append(contentsOf: fresh)
        entries.sort { $0.ts < $1.ts }

        let derived = UsageStore.buildDerived(from: entries)
        entriesBySource    = derived.bySource
        projectsBySource   = derived.projects
        modelsBySource     = derived.models
        codexCreditCycle   = derived.codexCreditCycle
        weeklyCodexCredits = derived.codexCreditCycle.used
        assignMissingProjectColors(for: fresh)
    }

    private func ingest(data: Data, source: String) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

        let combined = (source == "claude" ? claudeLineBuffer : codexLineBuffer) + chunk
        var lines = combined.components(separatedBy: "\n")
        let remainder = lines.removeLast()
        if source == "claude" { claudeLineBuffer = remainder } else { codexLineBuffer = remainder }

        let decoder = JSONDecoder.usageDecoder
        let newEntries = lines.filter { !$0.isEmpty }.compactMap { line -> UsageEntry? in
            guard let d = line.data(using: .utf8),
                  var e = try? decoder.decode(UsageEntry.self, from: d) else { return nil }
            e.source = source
            return e
        }
        guard !newEntries.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        entries.sort { $0.ts < $1.ts }
        let derived = UsageStore.buildDerived(from: entries)
        entriesBySource    = derived.bySource
        projectsBySource   = derived.projects
        modelsBySource     = derived.models
        codexCreditCycle   = derived.codexCreditCycle
        weeklyCodexCredits = derived.codexCreditCycle.used
        assignMissingProjectColors(for: newEntries)
    }

    private func startCreditCycleTimer() {
        guard creditCycleTimer == nil else { return }
        creditCycleTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                Task { @MainActor [weak self] in
                    self?.refreshCodexCreditCycle(now: now)
                }
            }
    }

    private func refreshCodexCreditCycle(now: Date = Date()) {
        let cycle = Self.computeCodexCreditCycle(from: entriesBySource["codex"] ?? [], now: now)
        codexCreditCycle = cycle
        weeklyCodexCredits = cycle.used
    }

    // MARK: - Derived cache builder (nonisolated — runs off main thread for initial load)

    private struct Derived {
        let bySource: [String: [UsageEntry]]
        let projects: [String: [String]]
        let models: [String: [String]]
        let codexCreditCycle: CodexCreditCycle
    }

    nonisolated private static func buildDerived(from entries: [UsageEntry]) -> Derived {
        var bySource: [String: [UsageEntry]] = [:]
        var projectSets: [String: Set<String>] = [:]
        var modelSets: [String: Set<String>] = [:]

        for e in entries {
            bySource[e.source, default: []].append(e)
            if e.project != "unknown" {
                projectSets[e.source, default: []].insert(e.project)
            }
            if e.model != "unknown" {
                modelSets[e.source, default: []].insert(e.model)
            }
        }

        let projects = projectSets.mapValues { set in
            set.sorted { URL(fileURLWithPath: $0).lastPathComponent < URL(fileURLWithPath: $1).lastPathComponent }
        }
        let models = modelSets.mapValues { set in set.sorted() }

        let codexCreditCycle = Self.computeCodexCreditCycle(from: bySource["codex"] ?? [], now: Date())

        return Derived(bySource: bySource, projects: projects, models: models, codexCreditCycle: codexCreditCycle)
    }

    nonisolated static func computeCodexCreditCycle(from entries: [UsageEntry], now: Date) -> CodexCreditCycle {
        let sorted = entries.sorted { $0.ts < $1.ts }
        var cycleStart: Date?
        var cycleEnd: Date?
        var used = 0.0

        for entry in sorted {
            guard let start = cycleStart, let end = cycleEnd else {
                cycleStart = entry.ts
                cycleEnd = entry.ts.addingTimeInterval(Self.codexCreditCycleDuration)
                used = entry.credits ?? 0
                continue
            }

            if entry.ts >= end {
                cycleStart = entry.ts
                cycleEnd = entry.ts.addingTimeInterval(Self.codexCreditCycleDuration)
                used = entry.credits ?? 0
            } else if entry.ts >= start {
                used += entry.credits ?? 0
            }
        }

        guard let cycleStart, let cycleEnd, now < cycleEnd else { return .inactive }
        return CodexCreditCycle(used: used, start: cycleStart, end: cycleEnd)
    }

    nonisolated private static let codexCreditCycleDuration: TimeInterval = 7 * 24 * 60 * 60
}

struct CodexCreditCycle: Equatable {
    let used: Double
    let start: Date?
    let end: Date?

    static let inactive = CodexCreditCycle(used: 0, start: nil, end: nil)

    var isActive: Bool {
        start != nil && end != nil
    }
}
