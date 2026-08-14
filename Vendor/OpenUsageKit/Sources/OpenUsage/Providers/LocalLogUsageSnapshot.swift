import Foundation

/// Builds a successful provider snapshot from local coding-agent logs alone.
///
/// This is the fallback for API-key and custom-gateway setups that can run inference but cannot call
/// the vendor's subscription-usage endpoint. It deliberately uses the same spend rows, trend, model
/// breakdown, and history shape as the normal provider path so the cross-provider Tokens card needs no
/// special cases.
enum LocalLogUsageSnapshot {
    static func make(
        provider: Provider,
        scan: LogUsageScan?,
        now: Date,
        sourceNote: String
    ) -> ProviderSnapshot? {
        guard let scan else { return nil }

        var lines: [MetricLine] = []
        SpendTileMapper.appendTokenUsage(
            scan.series,
            to: &lines,
            now: now,
            unknownModelsByDay: scan.unknownModelsByDay,
            modelUsage: scan.modelUsage,
            modelSourceNote: sourceNote
        )
        SpendTileMapper.appendUsageTrend(scan.series, to: &lines, now: now, note: sourceNote)
        MetricLine.appendNoDataIfNeeded(&lines)

        return ProviderSnapshot.make(
            provider: provider,
            plan: nil,
            lines: lines,
            refreshedAt: now,
            usageHistory: ProviderUsageHistory(
                series: scan.series,
                modelUsage: scan.modelUsage,
                unknownModelsByDay: scan.unknownModelsByDay
            )
        )
    }
}
