import Foundation

// MARK: - Cursor account usage (dashboard events, cached locally)

/// Per-request usage from the signed-in Cursor account.
///
/// Claude Code and Codex write token counts into session logs. Cursor does
/// not: its on-disk transcripts and composer bubbles carry the conversation,
/// and the `tokenCount` field on those bubbles stays at zero. The dashboard
/// endpoint behind the usage page does record each request, and that is what
/// gets cached here — counts, model, and the cost Cursor itself recorded.
/// No conversation text and no account id.
public enum CursorUsage {
    public struct Event: Codable, Equatable, Sendable {
        public var timestamp: Date
        public var model: String
        public var input: Int
        public var output: Int
        public var cacheRead: Int
        public var cacheWrite: Int
        /// Dollars, from `chargedCents` (model cost plus Cursor's token fee).
        public var usd: Double
        public var headless: Bool

        /// Stable identity of one request. The dashboard can return the same
        /// event on overlapping refreshes; the timestamp alone is not unique.
        public var dedupeKey: String {
            let millis = Int(timestamp.timeIntervalSince1970 * 1000)
            return "cursor|\(millis)|\(model)|\(input)|\(output)|\(cacheRead)|\(cacheWrite)|\(usd)"
        }
    }

    private struct CacheFile: Codable {
        var version: Int = 1
        var events: [Event]
    }

    /// One page of `get-filtered-usage-events`, newest first.
    struct Page {
        var total: Int?
        var events: [Event]
    }

    /// Every event at or after `since`. Pages until the dashboard reports no
    /// more, or 200 pages, whichever comes first.
    public static func fetch(
        cookieHeader: String,
        since: Date,
        until: Date = Date(),
        send: HTTPSend = HTTP.live) async throws -> [Event]
    {
        let url = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!
        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Origin": "https://cursor.com",
            "Cookie": cookieHeader,
        ]
        let startMs = Int(since.timeIntervalSince1970 * 1000)
        let endMs = Int(until.timeIntervalSince1970 * 1000)
        let pageSize = 500
        var page = 1
        var all: [Event] = []
        var total: Int?
        while page <= 200 {
            let body = """
            {"teamId":0,"startDate":\(startMs),"endDate":\(endMs),"page":\(page),"pageSize":\(pageSize)}
            """
            let response = try await send("POST", url, headers, Data(body.utf8), 30).requireOK()
            let parsed = try decodePage(response.data)
            if total == nil { total = parsed.total }
            if parsed.events.isEmpty { break }
            all.append(contentsOf: parsed.events)
            if let total, all.count >= total { break }
            if parsed.events.count < pageSize { break }
            page += 1
        }
        let horizon = until.addingTimeInterval(5 * 60)
        return all.filter { $0.timestamp >= since && $0.timestamp <= horizon }
    }

    /// Folds `fresh` into the cache. A later refresh only asks for the last
    /// couple of days; replacing the file with that slice would drop the rest
    /// of the year from the next full scan.
    public static func store(_ fresh: [Event], at url: URL) {
        var kept = load(from: url)
        var seen = Set(kept.map(\.dedupeKey))
        for event in fresh where seen.insert(event.dedupeKey).inserted {
            kept.append(event)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(CacheFile(events: kept)) else { return }
        AppSupport.write(data, to: url)
    }

    public static func load(from url: URL) -> [Event] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(CacheFile.self, from: data)
        else { return [] }
        return file.events
    }

    static func decodePage(_ data: Data) throws -> Page {
        let raw: RawPage
        do {
            raw = try JSONDecoder().decode(RawPage.self, from: data)
        } catch {
            throw ProviderError.badResponse
        }
        let events = (raw.usageEventsDisplay ?? []).compactMap(Event.init(raw:))
        return Page(total: raw.totalUsageEventsCount, events: events)
    }
}

// MARK: - Response shape

private struct RawPage: Decodable {
    let totalUsageEventsCount: Int?
    let usageEventsDisplay: [RawEvent]?
}

private struct RawEvent: Decodable {
    let timestamp: JSONScalar?
    let model: String?
    let isHeadless: Bool?
    let chargedCents: Double?
    let tokenUsage: RawTokens?
}

private struct RawTokens: Decodable {
    let inputTokens: JSONScalar?
    let outputTokens: JSONScalar?
    let cacheWriteTokens: JSONScalar?
    let cacheReadTokens: JSONScalar?
    let totalCents: Double?
}

/// A JSON number or a numeric string. The dashboard sends timestamps as
/// strings of milliseconds and token counts as numbers.
private struct JSONScalar: Decodable {
    let double: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            double = value
            return
        }
        if let text = try? container.decode(String.self), let value = Double(text) {
            double = value
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "expected a number")
    }

    var int: Int { Int(double.rounded()) }
}

extension CursorUsage.Event {
    fileprivate init?(raw: RawEvent) {
        guard let millis = raw.timestamp?.double else { return nil }
        let tokens = raw.tokenUsage
        let cents = raw.chargedCents ?? tokens?.totalCents ?? 0
        timestamp = Date(timeIntervalSince1970: millis / 1000)
        let name = raw.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        model = name.isEmpty ? "cursor" : name
        input = tokens?.inputTokens?.int ?? 0
        output = tokens?.outputTokens?.int ?? 0
        cacheRead = tokens?.cacheReadTokens?.int ?? 0
        cacheWrite = tokens?.cacheWriteTokens?.int ?? 0
        usd = cents / 100
        headless = raw.isHeadless ?? false
    }
}
