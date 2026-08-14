import Foundation

/// Builds a per-day token/cost series from pi's session logs for the Pi card, so everything pi (the
/// BYO-key coding agent) consumed on this machine shows as one spend/token/trend view — across every
/// provider pi drove, including providers OpenUsage has no card for (e.g. moonshot, nvidia-nim).
///
/// Pi records an authoritative per-message `usage.cost.total` (like OpenCode), so that carried cost is
/// used when present; when pi logs a `$0` cost (subscription usage it doesn't impute), the tokens are
/// priced through the shared engine instead — the same `carried cost, else price` rule the Claude and
/// Codex log scanners use. Pi's usage shape differs from Claude Code's (`usage.input`/`output`,
/// nested `usage.cost.total`), so it has its own parser rather than routing through those scanners.
///
/// An actor holding the versioned incremental parse cache (keyed path + size + mtime) in memory and
/// Application Support, so refreshes and relaunches parse only changed session files. A single shared
/// instance is used by every consuming provider, so pi's logs are parsed once rather than once per card.
actor PiUsageScanner {
    static let shared = PiUsageScanner()

    private let environment: EnvironmentReading
    private let homeDirectory: @Sendable () -> URL
    private let scanner: IncrementalJSONLScanner<Entry>

    private static let sharedScanner = IncrementalJSONLScanner<Entry>(
        logTag: LogTag.plugin("pi"),
        persistence: JSONLScanCachePersistence(namespace: "pi", schemaVersion: 2)
    )

    static func flushPersistentCacheWrites() async {
        await sharedScanner.flushPendingWrites()
    }

    init(
        environment: EnvironmentReading = ProcessEnvironmentReader(),
        homeDirectory: @escaping @Sendable () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        incrementalScanner: IncrementalJSONLScanner<Entry>? = nil
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.scanner = incrementalScanner ?? Self.sharedScanner
    }

    /// One parsed assistant-message usage line. Raw timestamp is kept so a cached parse stays valid as
    /// the window slides; `provider` is pi's raw provider id, kept so the Pi card can show everything
    /// pi drove rather than only providers OpenUsage has a card for.
    struct Entry: Codable, Sendable, Equatable {
        var id: String?
        var timestamp: Date
        var provider: String
        var model: String
        /// pi's own `usage.cost.total`, used directly when > 0; nil/0 falls through to engine pricing.
        var carriedCost: Double?
        /// The token buckets, for pricing the fall-through case.
        var tokens: TokenBreakdown
        /// pi's reported `usage.totalTokens`, shown as the row's token count (matches pi's own footer).
        var reportedTotalTokens: Int
    }

    /// Scan the last `daysBack` days of pi logs for the Pi card. Returns nil when pi's sessions
    /// directory has no log files at all.
    func scan(daysBack: Int = 30, now: Date = Date(), pricing: ModelPricing) async -> LogUsageScan? {
        let directory = PiPaths.sessionsDirectory(environment: environment, homeDirectory: homeDirectory())
        let since = JSONLScanning.sinceDate(daysBack: daysBack, now: now)
        let cacheIdentity = directory.resolvingSymlinksInPath().path
        let files = JSONLScanning.jsonlFiles(under: directory)
        guard !files.isEmpty else {
            _ = await scanner.items(
                from: [], since: since, cacheIdentity: cacheIdentity, parse: Self.parseFile
            )
            return nil
        }

        guard let entries = await scanner.items(
            from: files,
            since: since,
            cacheIdentity: cacheIdentity,
            parse: Self.parseFile
        ), !Task.isCancelled else { return nil }
        return Self.aggregate(entries: Self.dedup(entries), since: since, pricing: pricing)
    }

    /// Whether pi has any session logs on this machine — the cheap local-footprint probe used to seed
    /// the Pi card on first run and when the provider arrives with an update.
    func hasUsageLogs() async -> Bool {
        let directory = PiPaths.sessionsDirectory(environment: environment, homeDirectory: homeDirectory())
        return !JSONLScanning.jsonlFiles(under: directory).isEmpty
    }

    // MARK: - Parsing

    /// Parse every assistant usage line of one session file, regardless of the provider pi drove, so
    /// the Pi card sees the full footprint.
    static func parseFile(_ data: Data) -> [Entry] {
        let marker = Data(#""usage":{"#.utf8)
        var entries: [Entry] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.range(of: marker) != nil, let entry = parseLine(Data(line)) else { continue }
            entries.append(entry)
        }
        return entries
    }

    static func parseLine(_ data: Data) -> Entry? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["type"] as? String == "message",
              let timestampRaw = object["timestamp"] as? String,
              let timestamp = OpenUsageISO8601.date(from: timestampRaw),
              let message = object["message"] as? [String: Any],
              message["role"] as? String == "assistant",
              let provider = (message["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        let cacheWrite = Int(ProviderParse.number(usage["cacheWrite"]) ?? 0)
        let cacheWrite1h = Int(ProviderParse.number(usage["cacheWrite1h"]) ?? 0)
        let tokens = TokenBreakdown(
            input: Int(ProviderParse.number(usage["input"]) ?? 0),
            cacheWrite5m: max(cacheWrite - cacheWrite1h, 0),
            cacheWrite1h: cacheWrite1h,
            cacheRead: Int(ProviderParse.number(usage["cacheRead"]) ?? 0),
            output: Int(ProviderParse.number(usage["output"]) ?? 0)
        )

        let carriedCost = (usage["cost"] as? [String: Any]).flatMap { ProviderParse.number($0["total"]) }
        return Entry(
            id: object["id"] as? String,
            timestamp: timestamp,
            provider: provider,
            model: (message["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            carriedCost: carriedCost,
            tokens: tokens,
            reportedTotalTokens: Int(ProviderParse.number(usage["totalTokens"]) ?? 0)
        )
    }

    // MARK: - Dedup and aggregation

    /// Drop replayed lines that a forked/cloned session can duplicate under the same message id, keeping
    /// the first occurrence. Lines without an id are always kept.
    static func dedup(_ entries: [Entry]) -> [Entry] {
        var seen: Set<String> = []
        var out: [Entry] = []
        out.reserveCapacity(entries.count)
        for entry in entries {
            if let id = entry.id, !seen.insert(id).inserted { continue }
            out.append(entry)
        }
        return out
    }

    /// Bucket the entries into local calendar days. Cost is pi's carried total when it recorded one,
    /// else the tokens priced through `pricing`; a model that can't be priced and carries no cost
    /// remains in token totals with a nil cost and is surfaced as the tile's unknown-model warning,
    /// matching the log scanners.
    static func aggregate(entries: [Entry], since: Date, pricing: ModelPricing) -> LogUsageScan {
        var accumulator = DailyUsageAccumulator()
        for entry in entries where entry.timestamp >= since {
            let day = DailyUsageAccumulator.dayKey(from: entry.timestamp)
            let trimmedModel = entry.model.nilIfEmpty
            let modelName = trimmedModel ?? ModelUsageEntry.unattributedModelName

            let cost: Double?
            if let carried = entry.carriedCost, carried > 0 {
                cost = carried
            } else if let model = trimmedModel, let estimated = pricing.estimatedCostDollars(model: model, tokens: entry.tokens) {
                cost = estimated
            } else {
                cost = nil
                if let model = trimmedModel, entry.reportedTotalTokens > 0 {
                    accumulator.addUnknownModel(day: day, model: model)
                }
            }
            accumulator.add(day: day, tokens: entry.reportedTotalTokens, cost: cost, model: modelName)
        }
        return accumulator.build()
    }
}
