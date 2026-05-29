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

    private func entry(at ts: Date, credits: Double?) -> UsageEntry {
        UsageEntry(
            ts: ts,
            session_id: UUID().uuidString,
            model: "gpt-5.5",
            project: "ai-plugins",
            tokens: TokenBreakdown(input: 0, output: 0, cache_write: nil, cache_read: 0, reasoning: nil),
            credits: credits,
            cost_usd: 0,
            source: "codex"
        )
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
