import Foundation

/// One provider history made available to the cross-provider model aggregator.
struct CrossProviderModelUsageSource: Sendable {
    let providerID: String
    let providerTitle: String
    let history: ProviderUsageHistory
}

/// One provider's measured token contribution to a model.
struct ModelUsageProviderContribution: Identifiable, Equatable, Sendable {
    let providerID: String
    let providerTitle: String
    let tokenCount: Int
    let costUSD: Double?

    var id: String { providerID }
}

/// One model's measured tokens across every enabled provider.
struct CrossProviderModelUsageEntry: Identifiable, Equatable, Sendable {
    let model: String
    let totalTokens: Int
    let costUSD: Double?
    let providers: [ModelUsageProviderContribution]

    var id: String { model.lowercased() }
}

/// Cross-provider model totals for one dashboard period.
struct CrossProviderModelUsage: Equatable, Sendable {
    let period: UsagePeriod
    let models: [CrossProviderModelUsageEntry]
    let totalTokens: Int

    var isEmpty: Bool { models.isEmpty }

    /// Keep a compact ranked list on the dashboard. Unattributed usage and every model beyond the
    /// named cap remain accounted for in one final Other row.
    func displayRows(namedModelLimit: Int) -> [CrossProviderModelUsageEntry] {
        let limit = max(namedModelLimit, 0)
        var visible: [CrossProviderModelUsageEntry] = []
        var otherTokens = 0
        var otherKnownCostUSD = 0.0
        var isOtherCostComplete = true
        var otherProviders: [String: ProviderContributionAccumulator] = [:]

        for model in models {
            let foldsUnattributed =
                model.model.caseInsensitiveCompare(ModelUsageEntry.unattributedModelName) == .orderedSame
                || model.model.caseInsensitiveCompare(ModelUsageEntry.otherModelName) == .orderedSame
            if !foldsUnattributed, visible.count < limit {
                visible.append(model)
                continue
            }

            otherTokens += model.totalTokens
            if let costUSD = model.costUSD {
                otherKnownCostUSD += costUSD
            } else {
                isOtherCostComplete = false
            }
            for provider in model.providers {
                var accumulated = otherProviders[provider.providerID, default: ProviderContributionAccumulator(
                    title: provider.providerTitle
                )]
                accumulated.tokens += provider.tokenCount
                if let costUSD = provider.costUSD {
                    accumulated.knownCostUSD += costUSD
                } else {
                    accumulated.isCostComplete = false
                }
                otherProviders[provider.providerID] = accumulated
            }
        }

        if otherTokens > 0 {
            visible.append(CrossProviderModelUsageEntry(
                model: ModelUsageEntry.otherModelName,
                totalTokens: otherTokens,
                costUSD: isOtherCostComplete ? otherKnownCostUSD : nil,
                providers: makeProviderContributions(otherProviders)
            ))
        }
        return visible
    }
}

/// Pure, synchronous aggregation over normalized provider histories. It never fetches or re-scans.
enum CrossProviderModelUsageAggregator {
    static func total(
        for period: UsagePeriod,
        sources: [CrossProviderModelUsageSource],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CrossProviderModelUsage {
        let days = includedDays(for: period, now: now, calendar: calendar)
        var models: [String: ModelAccumulator] = [:]

        for source in sources {
            for day in source.history.modelUsage?.daily ?? [] where days.contains(day.date) {
                for model in day.models where model.totalTokens > 0 {
                    let name = normalizedModelName(model.model)
                    models[name.lowercased(), default: ModelAccumulator()]
                        .add(
                            model: name,
                            tokens: model.totalTokens,
                            costUSD: model.costUSD,
                            providerID: source.providerID,
                            providerTitle: source.providerTitle
                        )
                }
            }
        }

        let entries = models.map { key, value in
            CrossProviderModelUsageEntry(
                model: value.displayName ?? key,
                totalTokens: value.tokens,
                costUSD: value.resolvedCostUSD,
                providers: makeProviderContributions(value.providers)
            )
        }.sorted(by: modelPrecedes)

        return CrossProviderModelUsage(
            period: period,
            models: entries,
            totalTokens: entries.reduce(0) { $0 + $1.totalTokens }
        )
    }

    private static func includedDays(
        for period: UsagePeriod,
        now: Date,
        calendar: Calendar
    ) -> Set<String> {
        switch period {
        case .today:
            return [DailyUsageAccumulator.dayKey(from: now, calendar: calendar)]
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return [] }
            return [DailyUsageAccumulator.dayKey(from: yesterday, calendar: calendar)]
        case .last30:
            return UsageHistoryWindow.dayKeys(through: now, calendar: calendar)
        }
    }

    private static func normalizedModelName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ModelUsageEntry.unattributedModelName : trimmed
    }

    private static func modelPrecedes(
        _ lhs: CrossProviderModelUsageEntry,
        _ rhs: CrossProviderModelUsageEntry
    ) -> Bool {
        if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
        return lhs.model.localizedStandardCompare(rhs.model) == .orderedAscending
    }

    private struct ModelAccumulator {
        var tokens = 0
        var knownCostUSD = 0.0
        var isCostComplete = true
        var tokensBySpelling: [String: Int] = [:]
        var providers: [String: ProviderContributionAccumulator] = [:]

        var resolvedCostUSD: Double? {
            isCostComplete ? knownCostUSD : nil
        }

        var displayName: String? {
            tokensBySpelling.sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                let lhsLowercase = $0.key == $0.key.lowercased()
                let rhsLowercase = $1.key == $1.key.lowercased()
                if lhsLowercase != rhsLowercase { return lhsLowercase }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }.first?.key
        }

        mutating func add(
            model: String,
            tokens: Int,
            costUSD: Double?,
            providerID: String,
            providerTitle: String
        ) {
            self.tokens += tokens
            if let costUSD {
                knownCostUSD += costUSD
            } else {
                isCostComplete = false
            }
            tokensBySpelling[model, default: 0] += tokens
            var provider = providers[providerID, default: ProviderContributionAccumulator(title: providerTitle)]
            provider.tokens += tokens
            if let costUSD {
                provider.knownCostUSD += costUSD
            } else {
                provider.isCostComplete = false
            }
            providers[providerID] = provider
        }
    }
}

private struct ProviderContributionAccumulator {
    var title: String
    var tokens = 0
    var knownCostUSD = 0.0
    var isCostComplete = true

    var resolvedCostUSD: Double? {
        isCostComplete ? knownCostUSD : nil
    }
}

private func makeProviderContributions(
    _ values: [String: ProviderContributionAccumulator]
) -> [ModelUsageProviderContribution] {
    values.map { providerID, value in
        ModelUsageProviderContribution(
            providerID: providerID,
            providerTitle: value.title,
            tokenCount: value.tokens,
            costUSD: value.resolvedCostUSD
        )
    }.sorted {
        if $0.tokenCount != $1.tokenCount { return $0.tokenCount > $1.tokenCount }
        return $0.providerTitle.localizedStandardCompare($1.providerTitle) == .orderedAscending
    }
}
