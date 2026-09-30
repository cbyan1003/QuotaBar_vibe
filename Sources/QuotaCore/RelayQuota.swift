import Foundation

/// Remaining balance on a relay (中转站) that fronts Codex and Claude.
///
/// The station's API key is sent to `{base}/v1/usage`. Stations in this
/// shape answer with a dollar quota: limit, used and remaining. The base
/// the owner pastes is the same URL the CLI uses (`…/api/common`), with or
/// without a trailing `/v1`.
public enum RelayQuota {
    public static func isConfigured(_ config: ConfigStore, provider: ProviderID) -> Bool {
        config.relayBase(for: provider) != nil && config.relayKey(for: provider) != nil
    }

    public static func window(
        config: ConfigStore,
        provider: ProviderID,
        send: HTTPSend = HTTP.live) async throws -> UsageWindow
    {
        guard let base = config.relayBase(for: provider),
              let key = config.relayKey(for: provider),
              let url = usageURL(base)
        else {
            throw ProviderError.notConfigured(hint: ProviderID.codex.setupHint)
        }
        let response = try await send("GET", url, [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json",
            // A bare client is refused by the station's edge with a browser
            // check, before the API ever sees the key.
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        ], nil, 20).requireOK()
        return try parse(response.data)
    }

    /// `{base}/v1/usage`, whatever suffix the pasted URL already has.
    static func usageURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/v1/usage") { return URL(string: text) }
        if text.hasSuffix("/v1") { return URL(string: text + "/usage") }
        return URL(string: text + "/v1/usage")
    }

    public static func parse(_ data: Data) throws -> UsageWindow {
        let body: Body
        do { body = try JSONDecoder().decode(Body.self, from: data) }
        catch { throw ProviderError.badResponse }
        let quota = body.quota
        let limit = quota?.limit
        let remaining = quota?.remaining ?? body.remaining
        let used = quota?.used ?? limit.flatMap { cap in remaining.map { cap - $0 } }
        guard let limit, limit > 0, let used else { throw ProviderError.badResponse }
        let percent = used / limit * 100
        let left = remaining ?? max(0, limit - used)
        let unit = (quota?.unit ?? body.unit)?.uppercased()
        let detail = unit == "USD" || unit == nil
            ? "\(QuotaFormat.usd(left)) / \(QuotaFormat.usd(limit))"
            : "\(left.formatted()) / \(limit.formatted()) \(unit ?? "")"
        return UsageWindow(
            title: L10n.t("Relay balance", "中转站余额"),
            usedPercent: percent,
            detail: detail,
            resetsAt: Dates.parseISO(body.expiresAt),
            isActive: true,
            note: L10n.t("Remaining balance on the relay, from the key in Settings.",
                         "设置里填写的中转站密钥所剩余额。"))
    }

    private struct Body: Decodable {
        var expiresAt: String?
        var remaining: Double?
        var unit: String?
        var quota: Quota?

        struct Quota: Decodable {
            var limit: Double?
            var remaining: Double?
            var used: Double?
            var unit: String?
        }

        enum CodingKeys: String, CodingKey {
            case expiresAt = "expires_at"
            case remaining, unit, quota
        }
    }
}
