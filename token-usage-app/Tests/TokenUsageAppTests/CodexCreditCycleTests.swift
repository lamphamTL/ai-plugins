import XCTest
@testable import TokenUsageApp

final class CodexCreditCycleTests: XCTestCase {
    func testNoEntriesReturnsInactiveCycle() {
        let cycle = UsageStore.computeCodexCreditCycle(from: [], now: date("2026-05-27T10:00:00Z"))

        XCTAssertEqual(cycle, .inactive)
    }

    func testSingleEntryStartsActiveCycle() {
        let start = date("2026-05-27T10:00:00Z")
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [entry(at: start, credits: 12.5)],
            now: date("2026-05-28T10:00:00Z")
        )

        XCTAssertEqual(cycle.used, 12.5)
        XCTAssertEqual(cycle.start, start)
        XCTAssertEqual(cycle.end, date("2026-06-03T10:00:00Z"))
    }

    func testEntriesInsideSevenDaysUseSameCycle() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 12.5),
                entry(at: date("2026-05-29T12:00:00Z"), credits: 2.0),
                entry(at: date("2026-06-03T09:59:59Z"), credits: 1.5)
            ],
            now: date("2026-06-03T09:59:59Z")
        )

        XCTAssertEqual(cycle.used, 16.0)
        XCTAssertEqual(cycle.start, date("2026-05-27T10:00:00Z"))
        XCTAssertEqual(cycle.end, date("2026-06-03T10:00:00Z"))
    }

    func testEntryExactlyAtSevenDaysStartsNewCycle() {
        let newStart = date("2026-06-03T10:00:00Z")
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 12.5),
                entry(at: newStart, credits: 4.0)
            ],
            now: date("2026-06-03T10:00:01Z")
        )

        XCTAssertEqual(cycle.used, 4.0)
        XCTAssertEqual(cycle.start, newStart)
        XCTAssertEqual(cycle.end, date("2026-06-10T10:00:00Z"))
    }

    func testExpiredLatestCycleWithNoLaterUsageReturnsInactive() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [entry(at: date("2026-05-01T10:00:00Z"), credits: 12.5)],
            now: date("2026-05-09T10:00:00Z")
        )

        XCTAssertEqual(cycle, .inactive)
        XCTAssertEqual(cycle.inactiveReason, .awaitingNextUse)
    }

    func testWednesdayUsageAfterExpiredCycleStartsNewCycle() {
        let newStart = date("2026-06-03T10:00:00Z")
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 1.0),
                entry(at: date("2026-05-31T18:00:00Z"), credits: 999.0),
                entry(at: newStart, credits: 5.0)
            ],
            now: date("2026-06-03T10:30:00Z")
        )

        XCTAssertEqual(cycle.used, 5.0)
        XCTAssertEqual(cycle.start, newStart)
        XCTAssertEqual(cycle.end, date("2026-06-10T10:00:00Z"))
    }

    func testMissingCreditsStillStartsCycleWithZeroUsage() {
        let start = date("2026-05-27T10:00:00Z")
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [entry(at: start, credits: nil)],
            now: date("2026-05-28T10:00:00Z")
        )

        XCTAssertEqual(cycle.used, 0)
        XCTAssertEqual(cycle.start, start)
        XCTAssertEqual(cycle.end, date("2026-06-03T10:00:00Z"))
    }

    func testManualEndMarkerClosesActiveCycle() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-28T10:00:00Z"), credits: 5)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ],
            now: date("2026-05-29T10:01:00Z")
        )

        XCTAssertEqual(cycle, .inactive(reason: .manuallyEnded))
        XCTAssertEqual(cycle.inactiveReason, .manuallyEnded)
    }

    func testManualEndMarkerIgnoresUnmarkedUsageUntilStartMarker() {
        let newStart = date("2026-05-30T10:00:00Z")
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-29T12:00:00Z"), credits: 999),
                entry(at: newStart, credits: 4, type: UsageEntry.codexCreditCycleStartType),
                entry(at: date("2026-05-31T10:00:00Z"), credits: 6)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ],
            now: date("2026-05-31T10:01:00Z")
        )

        XCTAssertEqual(cycle.used, 10)
        XCTAssertEqual(cycle.start, newStart)
        XCTAssertEqual(cycle.end, date("2026-06-06T10:00:00Z"))
    }

    func testUnmarkedUsageAfterManualEndDoesNotRestartCycle() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-29T12:00:00Z"), credits: 999)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ],
            now: date("2026-05-29T12:01:00Z")
        )

        XCTAssertEqual(cycle, .inactive)
        XCTAssertEqual(cycle.inactiveReason, .awaitingNextUse)
    }

    func testManualEndUndoAllowedOnlyWhenEndMarkerIsLatestCodexEvent() {
        let canUndo = UsageStore.canUndoCodexCreditCycleEnd(
            entries: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-28T10:00:00Z"), credits: 5)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ]
        )

        XCTAssertTrue(canUndo)
    }

    func testManualEndUndoDeniedAfterLaterUsageEntry() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-29T12:00:00Z"), credits: 999)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ],
            now: date("2026-05-29T12:01:00Z")
        )
        let canUndo = UsageStore.canUndoCodexCreditCycleEnd(
            entries: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-29T12:00:00Z"), credits: 999)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ]
        )

        XCTAssertEqual(cycle.inactiveReason, .awaitingNextUse)
        XCTAssertFalse(canUndo)
    }

    func testManualEndUndoDeniedAfterLaterStartMarkerEntry() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-30T10:00:00Z"), credits: 4, type: UsageEntry.codexCreditCycleStartType),
                entry(at: date("2026-05-31T10:00:00Z"), credits: 6)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ],
            now: date("2026-05-31T10:01:00Z")
        )
        let canUndo = UsageStore.canUndoCodexCreditCycleEnd(
            entries: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10),
                entry(at: date("2026-05-30T10:00:00Z"), credits: 4, type: UsageEntry.codexCreditCycleStartType),
                entry(at: date("2026-05-31T10:00:00Z"), credits: 6)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ]
        )

        XCTAssertTrue(cycle.isActive)
        XCTAssertFalse(canUndo)
    }

    func testMultipleEndMarkersOnlyLatestMarkerCanBeUndoneWhenLatestOverall() {
        let cycle = UsageStore.computeCodexCreditCycle(
            from: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-28T10:00:00Z")),
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ],
            now: date("2026-05-29T10:01:00Z")
        )
        let canUndo = UsageStore.canUndoCodexCreditCycleEnd(
            entries: [
                entry(at: date("2026-05-27T10:00:00Z"), credits: 10)
            ],
            endMarkers: [
                endMarker(at: date("2026-05-28T10:00:00Z")),
                endMarker(at: date("2026-05-29T10:00:00Z"))
            ]
        )

        XCTAssertEqual(cycle.inactiveReason, .manuallyEnded)
        XCTAssertTrue(canUndo)
    }

    func testStartMarkerUsageDecodesAsNormalUsageEntry() throws {
        let data = """
        {"ts":"2026-05-30T10:00:00Z","session_id":"s1","model":"gpt-5.5","project":"ai-plugins","tokens":{"input":1,"output":2,"cache_read":3},"credits":4.5,"cost_usd":0.18,"type":"codex_credit_cycle_start"}
        """.data(using: .utf8)!

        let entry = try JSONDecoder.usageDecoder.decode(UsageEntry.self, from: data)

        XCTAssertEqual(entry.type, UsageEntry.codexCreditCycleStartType)
        XCTAssertEqual(entry.credits, 4.5)
    }

    func testStandaloneEndMarkerDoesNotDecodeAsUsageEntry() throws {
        let data = """
        {"ts":"2026-05-29T10:00:00Z","type":"codex_credit_cycle_end","source":"token-usage-app"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder.usageDecoder.decode(UsageEntry.self, from: data))

        let marker = try JSONDecoder.usageDecoder.decode(CodexCreditCycleMarker.self, from: data)
        XCTAssertEqual(marker.type, CodexCreditCycleMarker.endType)
        XCTAssertEqual(marker.source, "token-usage-app")
    }

    private func entry(at ts: Date, credits: Double?, type: String? = nil) -> UsageEntry {
        UsageEntry(
            ts: ts,
            session_id: UUID().uuidString,
            model: "gpt-5.5",
            project: "ai-plugins",
            tokens: TokenBreakdown(input: 0, output: 0, cache_write: nil, cache_read: 0, reasoning: nil),
            credits: credits,
            cost_usd: 0,
            isSubAgent: false,
            type: type,
            source: "codex"
        )
    }

    private func endMarker(at ts: Date) -> CodexCreditCycleMarker {
        CodexCreditCycleMarker(ts: ts, type: CodexCreditCycleMarker.endType, source: "token-usage-app")
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
