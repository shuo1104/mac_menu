import Foundation

/// Typed failures for the Pi provider, so telemetry groups them by a stable category
/// (see `ErrorCategory.swift`).
enum PiUsageError: Error, LocalizedError, Equatable {
    /// No pi session logs on this machine.
    case notDetected

    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "No pi session logs found. Use pi locally first."
        }
    }
}

/// Tracks everything pi (the BYO-key coding agent) consumed on this machine, straight from pi's own
/// session logs — no API, no credentials. Pi drives arbitrary providers' models (Claude, Codex,
/// moonshot, ...), so this card is the aggregate view for all of it, including providers OpenUsage has
/// no card for. Pi records its own per-message cost, so the dollars are measured, not imputed — the
/// same convention as OpenCode.
@MainActor
final class PiProvider: ProviderRuntime {
    let provider = Provider(
        id: "pi",
        displayName: "Pi",
        icon: .providerMark("pi")
    )

    let usageScanner: PiUsageScanner
    let now: @Sendable () -> Date
    let pricing: @Sendable () async -> ModelPricing

    /// Names the local source on hover. No "(estimated)": pi records its own per-message cost, so the
    /// values are measured, not imputed.
    private let sourceNote = "From your pi session logs"

    init(
        usageScanner: PiUsageScanner = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        pricing: @escaping @Sendable () async -> ModelPricing = { await ModelPricingStore.shared.current() }
    ) {
        self.usageScanner = usageScanner
        self.now = now
        self.pricing = pricing
    }

    var widgetDescriptors: [WidgetDescriptor] {
        // No quota meters — pi has no plan caps to read. Spend tiles + trend only, identical shape to
        // every other spend-tracking provider so the cross-provider Tokens card needs no special case.
        [
            .usageTrend(provider: provider)
                .exportingHistory(
                    scope: .machineLocal,
                    estimatedCost: false,
                    sourceNote: sourceNote
                )
        ] + WidgetDescriptor.spendTiles(provider: provider)
    }

    func hasLocalCredentials() async -> Bool {
        // Same source as `refresh()`: any pi session logs under the sessions directory. Local-only,
        // off the main actor (the scan itself runs on the scanner actor).
        await usageScanner.hasUsageLogs()
    }

    func refresh() async -> ProviderSnapshot {
        let refreshedAt = now()
        let pricing = await pricing()
        // `scan` returns nil both when pi has no logs at all and when the task was cancelled; the
        // refresh loop discards snapshots from cancelled refreshes, so this error is only ever
        // surfaced for a genuinely log-less pi.
        guard let scan = await usageScanner.scan(now: refreshedAt, pricing: pricing) else {
            return ProviderSnapshot.error(provider: provider, error: PiUsageError.notDetected)
        }

        var lines: [MetricLine] = []
        SpendTileMapper.appendTokenUsage(
            scan.series, to: &lines, now: refreshedAt,
            estimated: false,
            unknownModelsByDay: scan.unknownModelsByDay,
            modelUsage: scan.modelUsage,
            modelSourceNote: sourceNote
        )
        SpendTileMapper.appendUsageTrend(scan.series, to: &lines, now: refreshedAt, note: sourceNote)
        MetricLine.appendNoDataIfNeeded(&lines)

        return ProviderSnapshot.make(
            provider: provider,
            plan: nil,
            lines: lines,
            refreshedAt: refreshedAt,
            usageHistory: ProviderUsageHistory(
                series: scan.series,
                modelUsage: scan.modelUsage,
                unknownModelsByDay: scan.unknownModelsByDay
            )
        )
    }
}
