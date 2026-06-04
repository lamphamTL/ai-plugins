import Foundation

struct TokenBreakdown: Decodable, Hashable {
    let input: Int
    let output: Int
    let cache_write: Int?     // Claude only — legacy entries (pre-TTL-split)
    let cache_write_5m: Int?  // Claude only — 5m-TTL writes
    let cache_write_1h: Int?  // Claude only — 1h-TTL writes
    let cache_read: Int
    let reasoning: Int?       // Codex only

    /// Sum of all cache-write tiers; handles both legacy and new entries.
    var cache_write_total: Int { (cache_write ?? 0) + (cache_write_5m ?? 0) + (cache_write_1h ?? 0) }

    var total: Int { input + output + cache_write_total + cache_read + (reasoning ?? 0) }
}

struct UsageEntry: Decodable, Identifiable {
    static let codexCreditCycleStartType = "codex_credit_cycle_start"

    let ts: Date
    let session_id: String
    let model: String
    let project: String
    let tokens: TokenBreakdown
    let credits: Double?    // Codex only — from credit rate card
    let cost_usd: Double
    let isSubAgent: Bool
    let type: String?        // Optional durable event marker on normal usage entries.
    var source: String = "claude"   // injected by UsageStore after decode

    enum CodingKeys: String, CodingKey {
        case ts, session_id, model, project, tokens, credits, cost_usd, isSubAgent, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ts = try container.decode(Date.self, forKey: .ts)
        session_id = try container.decode(String.self, forKey: .session_id)
        model = try container.decode(String.self, forKey: .model)
        project = try container.decode(String.self, forKey: .project)
        tokens = try container.decode(TokenBreakdown.self, forKey: .tokens)
        credits = try container.decodeIfPresent(Double.self, forKey: .credits)
        cost_usd = try container.decode(Double.self, forKey: .cost_usd)
        isSubAgent = try container.decodeIfPresent(Bool.self, forKey: .isSubAgent) ?? false
        type = try container.decodeIfPresent(String.self, forKey: .type)
    }

    init(
        ts: Date,
        session_id: String,
        model: String,
        project: String,
        tokens: TokenBreakdown,
        credits: Double?,
        cost_usd: Double,
        isSubAgent: Bool,
        type: String? = nil,
        source: String = "claude"
    ) {
        self.ts = ts
        self.session_id = session_id
        self.model = model
        self.project = project
        self.tokens = tokens
        self.credits = credits
        self.cost_usd = cost_usd
        self.isSubAgent = isSubAgent
        self.type = type
        self.source = source
    }

    var id: String { "\(ts.timeIntervalSince1970)-\(session_id)-\(source)" }

    var projectDisplayName: String {
        guard project != "unknown" else { return "Unknown" }
        return URL(fileURLWithPath: project).lastPathComponent
    }
}

struct CodexCreditCycleMarker: Codable, Hashable, Identifiable, Sendable {
    static let endType = "codex_credit_cycle_end"

    let ts: Date
    let type: String
    let source: String?

    var id: String { "\(ts.timeIntervalSince1970)-\(type)-\(source ?? "")" }
}

extension JSONDecoder {
    static let usageDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
