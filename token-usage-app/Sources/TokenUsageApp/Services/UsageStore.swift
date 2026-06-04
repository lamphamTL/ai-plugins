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
    @Published private(set) var isWritingCodexCycleEndMarker = false
    // Stable palette index per projectDisplayName, persisted across launches.
    @Published private(set) var projectColors: [String: Int] = [:]
    private static let projectColorsKey = "projectColorIndex"

    private var claudeWatcher: FileWatcher?
    private var codexWatcher: FileWatcher?
    private var claudeLineBuffer = ""
    private var codexLineBuffer = ""
    private var codexCreditCycleEndMarkers: [CodexCreditCycleMarker] = []
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
            func decode(_ data: Data, source: String) -> ParsedUsageLines {
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    return ParsedUsageLines(entries: [], codexCreditCycleEndMarkers: [])
                }
                var lines = text.components(separatedBy: "\n")
                lines.removeLast()
                return UsageStore.decodeUsageLines(lines, source: source)
            }
            let claudeParsed = decode(claudeInitial, source: "claude")
            let codexParsed = decode(codexInitial, source: "codex")
            let all = (claudeParsed.entries + codexParsed.entries)
                .sorted { $0.ts < $1.ts }
            let derived = UsageStore.buildDerived(from: all, codexCycleEndMarkers: codexParsed.codexCreditCycleEndMarkers)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries             = all
                self.codexCreditCycleEndMarkers = codexParsed.codexCreditCycleEndMarkers
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
        isWritingCodexCycleEndMarker = false
        codexCreditCycleEndMarkers = []
        isLoaded = false
        load()
    }

    func appendCodexCreditCycleEndMarker() async throws {
        guard !isWritingCodexCycleEndMarker else { return }
        isWritingCodexCycleEndMarker = true
        defer { isWritingCodexCycleEndMarker = false }

        let marker = CodexCreditCycleMarker(
            ts: Date(),
            type: CodexCreditCycleMarker.endType,
            source: "token-usage-app"
        )
        try await Self.appendCodexCreditCycleEndMarkerToLog(marker)
    }

    /// Latest end marker is "undoable" only when it is the most recent codex event —
    /// i.e. no later codex event of any kind has been logged after it.
    var canUndoCodexCreditCycleEnd: Bool {
        Self.canUndoCodexCreditCycleEnd(
            entries: entriesBySource["codex"] ?? [],
            endMarkers: codexCreditCycleEndMarkers
        )
    }

    func removeLastCodexCreditCycleEndMarker() async throws {
        guard !isWritingCodexCycleEndMarker else { return }
        guard let target = Self.latestCodexCreditCycleEndMarker(in: codexCreditCycleEndMarkers)?.marker else { return }
        isWritingCodexCycleEndMarker = true
        defer { isWritingCodexCycleEndMarker = false }

        try await Self.removeCodexCreditCycleEndMarkerFromLog(target)
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

        var lines = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n")
        let remainder = lines.removeLast()
        if source == "claude" { claudeLineBuffer = remainder } else { codexLineBuffer = remainder }

        let parsed = Self.decodeUsageLines(lines, source: source)
        let fresh = parsed.entries

        entries.removeAll { $0.source == source }
        entries.append(contentsOf: fresh)
        entries.sort { $0.ts < $1.ts }
        if source == "codex" {
            codexCreditCycleEndMarkers = parsed.codexCreditCycleEndMarkers
        }

        let derived = UsageStore.buildDerived(from: entries, codexCycleEndMarkers: codexCreditCycleEndMarkers)
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

        let parsed = Self.decodeUsageLines(lines, source: source)
        let newEntries = parsed.entries
        let newMarkers = parsed.codexCreditCycleEndMarkers
        guard !newEntries.isEmpty || !newMarkers.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        entries.sort { $0.ts < $1.ts }
        if source == "codex" {
            codexCreditCycleEndMarkers.append(contentsOf: newMarkers)
        }
        let derived = UsageStore.buildDerived(from: entries, codexCycleEndMarkers: codexCreditCycleEndMarkers)
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
        let cycle = Self.computeCodexCreditCycle(
            from: entriesBySource["codex"] ?? [],
            endMarkers: codexCreditCycleEndMarkers,
            now: now
        )
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

    private struct ParsedUsageLines {
        let entries: [UsageEntry]
        let codexCreditCycleEndMarkers: [CodexCreditCycleMarker]
    }

    nonisolated private static func decodeUsageLines(_ lines: [String], source: String) -> ParsedUsageLines {
        let decoder = JSONDecoder.usageDecoder
        var entries: [UsageEntry] = []
        var markers: [CodexCreditCycleMarker] = []

        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8) else { continue }
            if var entry = try? decoder.decode(UsageEntry.self, from: data) {
                entry.source = source
                entries.append(entry)
                continue
            }
            guard source == "codex",
                  let marker = try? decoder.decode(CodexCreditCycleMarker.self, from: data),
                  marker.type == CodexCreditCycleMarker.endType else { continue }
            markers.append(marker)
        }

        return ParsedUsageLines(entries: entries, codexCreditCycleEndMarkers: markers)
    }

    nonisolated private static func buildDerived(from entries: [UsageEntry], codexCycleEndMarkers: [CodexCreditCycleMarker]) -> Derived {
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

        let codexCreditCycle = Self.computeCodexCreditCycle(
            from: bySource["codex"] ?? [],
            endMarkers: codexCycleEndMarkers,
            now: Date()
        )

        return Derived(bySource: bySource, projects: projects, models: models, codexCreditCycle: codexCreditCycle)
    }

    nonisolated static func canUndoCodexCreditCycleEnd(
        entries: [UsageEntry],
        endMarkers: [CodexCreditCycleMarker]
    ) -> Bool {
        guard let latestEvent = latestCodexCreditCycleEvent(from: entries, endMarkers: endMarkers) else { return false }
        if case .endMarker = latestEvent {
            return true
        }
        return false
    }

    nonisolated static func computeCodexCreditCycle(
        from entries: [UsageEntry],
        endMarkers: [CodexCreditCycleMarker] = [],
        now: Date
    ) -> CodexCreditCycle {
        let events = orderedCodexCreditCycleEvents(from: entries, endMarkers: endMarkers)
        var cycleStart: Date?
        var cycleEnd: Date?
        var used = 0.0

        for event in events {
            switch event {
            case .endMarker:
                cycleStart = nil
                cycleEnd = nil
                used = 0

            case .entry(let entry):
                let isStartMarker = entry.type == UsageEntry.codexCreditCycleStartType
                if isStartMarker {
                    cycleStart = entry.ts
                    cycleEnd = entry.ts.addingTimeInterval(Self.codexCreditCycleDuration)
                    used = entry.credits ?? 0
                    continue
                }

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
        }

        guard let cycleStart, let cycleEnd, now < cycleEnd else {
            let inactiveReason: CodexCreditCycleInactiveReason = {
                guard let latestEvent = latestCodexCreditCycleEvent(from: entries, endMarkers: endMarkers) else {
                    return .awaitingNextUse
                }
                if case .endMarker = latestEvent {
                    return .manuallyEnded
                }
                return .awaitingNextUse
            }()
            return CodexCreditCycle.inactive(reason: inactiveReason)
        }
        return CodexCreditCycle(used: used, start: cycleStart, end: cycleEnd, inactiveReason: nil)
    }

    nonisolated private static func appendCodexCreditCycleEndMarkerToLog(_ marker: CodexCreditCycleMarker) async throws {
        try await Task.detached {
            let directory = codexURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(marker)
            data.append(0x0A)

            if !FileManager.default.fileExists(atPath: codexURL.path) {
                FileManager.default.createFile(atPath: codexURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: codexURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }.value
    }

    nonisolated private static func removeCodexCreditCycleEndMarkerFromLog(_ marker: CodexCreditCycleMarker) async throws {
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: codexURL.path) else { return }
            let data = try Data(contentsOf: codexURL)
            guard let text = String(data: data, encoding: .utf8) else { return }

            let decoder = JSONDecoder.usageDecoder
            var lines = text.components(separatedBy: "\n")
            // last component is "" if file ends with newline, or trailing partial line otherwise
            let trailing = lines.removeLast()

            var matchIdx: Int?
            for (i, line) in lines.enumerated().reversed() where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let candidate = try? decoder.decode(CodexCreditCycleMarker.self, from: lineData),
                      candidate.type == CodexCreditCycleMarker.endType,
                      candidate.ts == marker.ts,
                      candidate.source == marker.source else { continue }
                matchIdx = i
                break
            }
            guard let idx = matchIdx else { return }
            lines.remove(at: idx)

            var rebuilt = lines.joined(separator: "\n")
            if !lines.isEmpty { rebuilt.append("\n") }
            rebuilt.append(trailing)

            let outData = rebuilt.data(using: .utf8) ?? Data()
            let tmpURL = codexURL.appendingPathExtension("tmp")
            try outData.write(to: tmpURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(codexURL, withItemAt: tmpURL)
        }.value
    }

    nonisolated private static let codexCreditCycleDuration: TimeInterval = 7 * 24 * 60 * 60

    nonisolated private static func orderedCodexCreditCycleEvents(
        from entries: [UsageEntry],
        endMarkers: [CodexCreditCycleMarker]
    ) -> [CodexCreditCycleEvent] {
        (entries.map(CodexCreditCycleEvent.entry) + endMarkers.map(CodexCreditCycleEvent.endMarker))
            .sorted {
                if $0.ts == $1.ts { return $0.sortRank < $1.sortRank }
                return $0.ts < $1.ts
            }
    }

    nonisolated private static func latestCodexCreditCycleEvent(
        from entries: [UsageEntry],
        endMarkers: [CodexCreditCycleMarker]
    ) -> CodexCreditCycleEvent? {
        orderedCodexCreditCycleEvents(from: entries, endMarkers: endMarkers).last
    }

    nonisolated private static func latestCodexCreditCycleEndMarker(
        in markers: [CodexCreditCycleMarker]
    ) -> (index: Int, marker: CodexCreditCycleMarker)? {
        markers.enumerated().max { lhs, rhs in
            if lhs.element.ts == rhs.element.ts {
                return lhs.offset < rhs.offset
            }
            return lhs.element.ts < rhs.element.ts
        }
        .map { (index: $0.offset, marker: $0.element) }
    }
}

private enum CodexCreditCycleEvent {
    case entry(UsageEntry)
    case endMarker(CodexCreditCycleMarker)

    var ts: Date {
        switch self {
        case .entry(let entry): return entry.ts
        case .endMarker(let marker): return marker.ts
        }
    }

    var sortRank: Int {
        switch self {
        case .entry: return 0
        case .endMarker: return 1
        }
    }
}

enum CodexCreditCycleInactiveReason: Equatable {
    case awaitingNextUse
    case manuallyEnded
}

struct CodexCreditCycle: Equatable {
    let used: Double
    let start: Date?
    let end: Date?
    let inactiveReason: CodexCreditCycleInactiveReason?

    static let inactive = CodexCreditCycle.inactive(reason: .awaitingNextUse)

    static func inactive(reason: CodexCreditCycleInactiveReason) -> CodexCreditCycle {
        CodexCreditCycle(used: 0, start: nil, end: nil, inactiveReason: reason)
    }

    var isActive: Bool {
        start != nil && end != nil
    }
}
