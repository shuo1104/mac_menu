import Foundation

/// Accumulates per-day usage — tokens, optional cost, and the per-model breakdown — then assembles a
/// `LogUsageScan`. Shared by the log scanners (Claude, Codex, Grok) so the "accumulate then assemble"
/// tail lives in one place instead of a byte-identical copy per provider; each scanner keeps only its
/// format-specific parse/pricing loop.
///
/// Days are keyed by the shared local-calendar `dayKey`, matching `SpendTileMapper`'s Today / Yesterday
/// lookup — the day-key contract is one function, not five copies (drift here is the class of bug behind
/// the ccusage false-zero fix). Tokens are the primary measured value and are retained even when pricing
/// is unavailable. A day containing any unpriced usage has a nil total cost rather than a misleading
/// partial dollar figure; unpriceable models are also tracked for the tile's warning triangle.
struct DailyUsageAccumulator {
    private var tokensByDay: [String: Int] = [:]
    private var costByDay: [String: Double] = [:]
    private var unpricedDays: Set<String> = []
    private var unknownModelsByDay: [String: Set<String>] = [:]
    private var modelsByDay: [String: [String: ModelAccumulator]] = [:]

    /// Local calendar day as `yyyy-MM-dd`. The single day-key contract shared by the accumulator,
    /// `SpendTileMapper`, and the Cursor CSV aggregation. `calendar` is injectable for tests; production
    /// uses `.current`.
    static func dayKey(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Add a row's measured tokens and optional cost, attributed to `model` on `day`.
    mutating func add(day: String, tokens: Int, cost: Double?, model: String) {
        tokensByDay[day, default: 0] += tokens
        if let cost {
            costByDay[day, default: 0] += cost
        } else if tokens > 0 {
            unpricedDays.insert(day)
        }
        modelsByDay[day, default: [:]][model, default: ModelAccumulator()].add(tokens: tokens, costUSD: cost)
    }

    /// Note a model that couldn't be priced but still carried tokens — surfaced as the tile's warning
    /// triangle alongside its token-only model entry.
    mutating func addUnknownModel(day: String, model: String) {
        unknownModelsByDay[day, default: []].insert(model)
    }

    /// Assemble the scan: per-day tokens/optional cost (days sorted newest-first), the per-day model
    /// breakdown, and the unknown-model set.
    func build() -> LogUsageScan {
        let days = tokensByDay.keys.sorted(by: >).map { day in
            DailyUsageEntry(
                date: day,
                totalTokens: tokensByDay[day] ?? 0,
                costUSD: unpricedDays.contains(day) ? nil : costByDay[day]
            )
        }
        let modelUsage = ModelUsageSeries(daily: modelsByDay.keys.sorted(by: >).map { day in
            DailyModelUsageEntry(
                date: day,
                models: modelsByDay[day, default: [:]].map { model, accumulator in accumulator.entry(model: model) }
            )
        })
        return LogUsageScan(
            series: DailyUsageSeries(daily: days),
            modelUsage: modelUsage,
            unknownModelsByDay: unknownModelsByDay
        )
    }

    private struct ModelAccumulator {
        var tokens = 0
        var costUSD: Double?
        var sawUnpriced = false

        mutating func add(tokens: Int, costUSD: Double?) {
            self.tokens += tokens
            if let costUSD {
                self.costUSD = (self.costUSD ?? 0) + costUSD
            } else if tokens > 0 {
                self.sawUnpriced = true
            }
        }

        func entry(model: String) -> ModelUsageEntry {
            ModelUsageEntry(model: model, totalTokens: tokens, costUSD: sawUnpriced ? nil : costUSD)
        }
    }
}
