import XCTest
@testable import QuotaCore

final class CursorUsageTests: XCTestCase {
    private let page = Data("""
    {"totalUsageEventsCount":2,"usageEventsDisplay":[
      {"timestamp":"1780000000000","model":"grok-4.7-high","kind":"USAGE_EVENT_KIND_INCLUDED_IN_BUSINESS",
       "isHeadless":false,"chargedCents":41.32,
       "tokenUsage":{"inputTokens":1000,"outputTokens":50,"cacheReadTokens":4000,"cacheWriteTokens":20,"totalCents":40}},
      {"timestamp":1780003600000,"model":"composer-2","isHeadless":true,
       "tokenUsage":{"inputTokens":10,"outputTokens":2,"totalCents":5}}
    ]}
    """.utf8)

    func testPageDecodesTokensAndPrefersChargedCents() throws {
        let parsed = try CursorUsage.decodePage(page)
        XCTAssertEqual(parsed.total, 2)
        XCTAssertEqual(parsed.events.count, 2)

        let first = try XCTUnwrap(parsed.events.first)
        XCTAssertEqual(first.model, "grok-4.7-high")
        XCTAssertEqual(first.input, 1000)
        XCTAssertEqual(first.output, 50)
        XCTAssertEqual(first.cacheRead, 4000)
        XCTAssertEqual(first.cacheWrite, 20)
        XCTAssertEqual(first.usd, 0.4132, accuracy: 0.0001)
        XCTAssertFalse(first.headless)
        XCTAssertEqual(first.timestamp, Date(timeIntervalSince1970: 1_780_000_000))

        let second = parsed.events[1]
        XCTAssertEqual(second.usd, 0.05, accuracy: 0.0001, "falls back to totalCents")
        XCTAssertTrue(second.headless)
    }

    func testFetchFollowsPagesUntilTheTotalIsMet() async throws {
        let first = Data("""
        {"totalUsageEventsCount":2,"usageEventsDisplay":[
          {"timestamp":"1780000000000","model":"a","chargedCents":100,
           "tokenUsage":{"inputTokens":1,"outputTokens":1}}
        ]}
        """.utf8)
        let second = Data("""
        {"totalUsageEventsCount":2,"usageEventsDisplay":[
          {"timestamp":"1780003600000","model":"b","chargedCents":200,
           "tokenUsage":{"inputTokens":2,"outputTokens":2}}
        ]}
        """.utf8)
        let send: HTTPSend = { _, _, _, body, _ in
            let text = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let payload = text.contains("\"page\":1") ? first : second
            return HTTPResponse(status: 200, data: payload)
        }
        let since = Date(timeIntervalSince1970: 1_779_000_000)
        let until = Date(timeIntervalSince1970: 1_781_000_000)
        let events = try await CursorUsage.fetch(
            cookieHeader: "WorkosCursorSessionToken=test", since: since, until: until, send: send)
        XCTAssertEqual(events.map(\.model), ["a", "b"])
    }

    func testStoreDedupesOverlappingRefreshes() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cursor-usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let event = CursorUsage.Event(
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            model: "grok-4.7-high", input: 10, output: 2, cacheRead: 0, cacheWrite: 0,
            usd: 0.1, headless: false)
        CursorUsage.store([event, event], at: url)
        CursorUsage.store([event], at: url)
        XCTAssertEqual(CursorUsage.load(from: url).count, 1)
    }

    func testCachedEventsLandInTheUsageLedgerAtTheRecordedCost() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quotabar-cursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cursor-usage.json")
        let when = Date(timeIntervalSince1970: 1_780_000_000)
        CursorUsage.store([
            CursorUsage.Event(
                timestamp: when, model: "grok-4.7-high",
                input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0,
                usd: 1.25, headless: false),
        ], at: file)
        let paths = CostPaths(
            claudeProjects: root.appendingPathComponent("claude"),
            codexSessions: root.appendingPathComponent("codex"),
            cursorUsage: file)
        CostEstimator.resetCache()
        defer { CostEstimator.resetCache() }

        let summary = CostEstimator.summary(paths: paths, now: when)
        XCTAssertEqual(summary.windowUSD, 1.25, accuracy: 0.0001)
        XCTAssertEqual(summary.windowBySource[.cursor], 1.25)
        XCTAssertEqual(summary.windowTokens, 1_000_000)
        let cursor = try XCTUnwrap(summary.periods[.window]?.byModel["grok-4.7-high"])
        XCTAssertEqual(cursor.source, .cursor)
    }

    func testFirstCursorScanReachesPastTheIncrementalLogCutoff() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quotabar-cursor-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cursor-usage.json")
        let old = Date(timeIntervalSince1970: 1_780_000_000)
        let recent = old.addingTimeInterval(10 * 86_400)
        CursorUsage.store([
            CursorUsage.Event(
                timestamp: old, model: "grok-4.7-high",
                input: 100, output: 10, cacheRead: 0, cacheWrite: 0,
                usd: 0.5, headless: false),
            CursorUsage.Event(
                timestamp: recent, model: "grok-4.7-high",
                input: 50, output: 5, cacheRead: 0, cacheWrite: 0,
                usd: 0.2, headless: false),
        ], at: file)
        let paths = CostPaths(
            claudeProjects: root.appendingPathComponent("claude"),
            codexSessions: root.appendingPathComponent("codex"),
            cursorUsage: file)
        let scan = CostEstimator.archiveScan(
            paths: paths, since: recent, now: recent.addingTimeInterval(3600), cursorSince: old)
        let oldKey = UsageArchive.dayKey(old)
        XCTAssertEqual(scan.days[oldKey]?["cursor"]?["grok-4.7-high"]?.input, 100)
        XCTAssertTrue(scan.projects.isEmpty, "events without a directory are not a project")
    }

    func testCursorScanStartBackfillsUntilTheArchiveHasCursor() throws {
        var archive = UsageArchive()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let start = archive.cursorScanStart(now: now, calendar: calendar)
        let year = calendar.component(.year, from: now)
        let floor = try XCTUnwrap(calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)))
        XCTAssertEqual(start, floor)

        let key = UsageArchive.dayKey(now)
        archive.merge(
            [key: ["cursor": ["grok": ArchiveEntry(usd: 1, input: 10, output: 1)]]],
            scannedAt: now, full: true)
        let incremental = archive.cursorScanStart(now: now, calendar: calendar)
        XCTAssertGreaterThan(incremental, floor)
    }
}
