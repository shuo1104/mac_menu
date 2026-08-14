import SwiftUI

/// A persistent cross-provider ranking of measured model tokens and estimated cost for the
/// dashboard's selected period.
struct ModelUsageCard: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(WidgetDataStore.self) private var dataStore
    @Environment(AppContainer.self) private var container

    @AppStorage(UsagePeriod.storageKey) private var periodRawValue = UsagePeriod.today.rawValue
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    private static let namedModelLimit = 6

    private var period: UsagePeriod {
        UsagePeriod(rawValue: periodRawValue) ?? .today
    }

    private var sources: [CrossProviderModelUsageSource] {
        var providers = layout.spendCapableProviders
        var snapshots = dataStore.snapshots
        for entry in dataStore.remoteOnlySpend {
            providers.append(entry.provider)
            snapshots[entry.provider.id] = entry.snapshot
        }
        return providers.compactMap { provider in
            guard let history = snapshots[provider.id]?.usageHistory else { return nil }
            return CrossProviderModelUsageSource(
                providerID: provider.id,
                providerTitle: container.displayName(for: provider),
                history: history
            )
        }
    }

    private var total: CrossProviderModelUsage {
        CrossProviderModelUsageAggregator.total(for: period, sources: sources)
    }

    private var rows: [CrossProviderModelUsageEntry] {
        total.displayRows(namedModelLimit: Self.namedModelLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            header
            card
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("Model Usage")
                .font(.system(size: density.headerPointSize, weight: .semibold))
                .foregroundStyle(.primary)
            Image(systemName: "info.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .hoverTooltip("Ranks measured model tokens and estimated cost across enabled providers.")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var card: some View {
        VStack(spacing: 10) {
            UsagePeriodPicker(selection: Binding(
                get: { period },
                set: { periodRawValue = $0.rawValue }
            ))
            if total.isEmpty {
                emptyState
            } else {
                summary
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        modelRow(row)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .animation(Motion.spring, value: periodRawValue)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(total.models.count) \(L10n.string("models"))")
            Spacer(minLength: 8)
            Text(tokenString(total.totalTokens))
                .monospacedDigit()
        }
        .font(.system(size: density.supportingPointSize, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func modelRow(_ row: CrossProviderModelUsageEntry) -> some View {
        let share = total.totalTokens > 0
            ? Double(row.totalTokens) / Double(total.totalTokens)
            : 0
        let percent = Int((share * 100).rounded())
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.model)
                    .font(.system(size: density.supportingPointSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(costString(row.costUSD))
                    .font(.system(size: density.supportingPointSize, weight: .medium))
                    .foregroundStyle(row.costUSD == nil ? Color.secondary : Color.primary)
                    .monospacedDigit()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(providerSummary(row.providers))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text("\(tokenString(row.totalTokens)) · \(percent)%")
                    .monospacedDigit()
            }
            .font(.system(size: density.supportingPointSize))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.meterFill(.normal))
                            .frame(width: proxy.size.width * share)
                    }
            }
            .frame(height: density.meterHeight)
            .padding(.top, 2)
        }
        .padding(.vertical, density.textRowPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.model), \(costString(row.costUSD)), \(tokenString(row.totalTokens)), "
                + "\(percent) percent, \(providerSummary(row.providers))"
        )
    }

    private var emptyState: some View {
        Text("No model data for this period")
            .font(.system(size: density.supportingPointSize))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }

    private func providerSummary(_ providers: [ModelUsageProviderContribution]) -> String {
        let leading = providers.prefix(2).map(\.providerTitle).formatted(.list(type: .and))
        let remaining = providers.count - min(providers.count, 2)
        return remaining > 0 ? "\(leading) +\(remaining)" : leading
    }

    private func tokenString(_ tokens: Int) -> String {
        MetricFormatter.string(
            for: MetricValue(number: Double(tokens), kind: .count, label: "tokens"),
            style: .row
        )
    }

    private func costString(_ costUSD: Double?) -> String {
        guard let costUSD else { return L10n.string("Cost unavailable") }
        return MetricFormatter.string(
            for: MetricValue(number: costUSD, kind: .dollars, estimated: true),
            style: .row
        )
    }
}
