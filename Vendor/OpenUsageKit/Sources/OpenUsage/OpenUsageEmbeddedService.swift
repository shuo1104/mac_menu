import Foundation

public enum EmbeddedUsagePeriod: String, CaseIterable, Sendable {
    case today
    case yesterday
    case last30Days
}

public struct EmbeddedUsagePeriodValue: Equatable, Sendable {
    public let tokens: Double
    public let costUSD: Double?
}

public struct EmbeddedUsageMetric: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let fractionUsed: Double?
    public let resetsAt: Date?
    public let periodDurationMilliseconds: Int?
}

public struct EmbeddedUsageTrendPoint: Equatable, Sendable {
    public let label: String
    public let value: Double
}

public struct EmbeddedUsageProvider: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let plan: String?
    public let isEnabled: Bool
    public let isStale: Bool
    public let metrics: [EmbeddedUsageMetric]
    public let trend: [EmbeddedUsageTrendPoint]
    public let periods: [EmbeddedUsagePeriod: EmbeddedUsagePeriodValue]
    public let errorMessage: String?
}

public struct EmbeddedModelUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let modelName: String
    public let providerName: String
    public let tokens: Double
    public let costUSD: Double?
}

public struct EmbeddedUsageSnapshot: Equatable, Sendable {
    public let providers: [EmbeddedUsageProvider]
    public let models: [EmbeddedUsagePeriod: [EmbeddedModelUsage]]
    public let refreshedAt: Date?
}

public struct EmbeddedProviderSetting: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
}

/// Where a provider's API key currently comes from — the public mirror of the internal
/// `APIKeyStatus` used by the vendor dashboard's key editor.
public enum EmbeddedAPIKeyStatus: Equatable, Sendable {
    case notSet
    case fromEnvironment
    case saved
    case overrideActive

    init(_ status: APIKeyStatus) {
        switch status {
        case .notSet: self = .notSet
        case .fromEnvironment: self = .fromEnvironment
        case .saved: self = .saved
        case .overrideActive: self = .overrideActive
        }
    }
}

public struct EmbeddedAPIKeyProvider: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: EmbeddedAPIKeyStatus
}

@MainActor
public final class EmbeddedOpenUsageService {
    private let providers: [ProviderRuntime]
    private let registry: WidgetRegistry
    private let enablement: ProviderEnablementStore
    private let dataStore: WidgetDataStore
    private let accounts: ProviderAccountsStore
    private var initialProviderDetectionTask: Task<Void, Never>?

    public init() {
        LoginShellEnvironment.shared.prewarm()

        let accounts = ProviderAccountsStore()
        let assembly = ProviderAccountAssembly.make(
            accountsStore: accounts,
            waitsForLoginShell: true
        )
        let providers = ProviderCatalog.make(
            claudeCards: assembly.claudeCards,
            defaultClaudeExtraLogRoots: assembly.defaultClaudeExtraLogRoots
        )
        let registry = WidgetRegistry.from(providers)
        let enablement = ProviderEnablementStore()
        let dataStore = WidgetDataStore(
            registry: registry,
            providers: providers,
            isProviderEnabled: { [enablement] in
                enablement.isEnabled($0)
            },
            postNotification: { _, _, _, _ in false },
            providerIdentityKeys: assembly.identityKeysByCard,
            resolveDisplayName: { [accounts] in
                accounts.resolvedDisplayName(cardID: $0)
            }
        )

        enablement.onProviderEnabled = { [weak dataStore] id in
            dataStore?.clearFailureBackoff(for: id)
        }
        enablement.onChange = { [weak dataStore] in
            dataStore?.providerEnablementDidChange()
        }

        self.accounts = accounts
        self.providers = providers
        self.registry = registry
        self.enablement = enablement
        self.dataStore = dataStore
        if let firstRunTask = Self.seedEmbeddedProvidersIfNeeded(
            providers: providers,
            enablement: enablement
        ) {
            initialProviderDetectionTask = firstRunTask
        } else {
            // Established install: probe providers added by an app update (e.g. Kimi) once and
            // auto-enable the ones with credentials.
            initialProviderDetectionTask = Self.enableNewProvidersWithCredentials(
                providers: providers,
                enablement: enablement
            )
        }
    }

    /// Established-install counterpart of the first-run seed: providers added by an app update
    /// (e.g. Kimi) are probed once for local credentials and auto-enabled on a hit. New providers
    /// without credentials stay off and are marked known so they aren't probed every launch;
    /// providers the install already knows are never touched, so a user's off-toggle is safe.
    private static func enableNewProvidersWithCredentials(
        providers: [ProviderRuntime],
        enablement: ProviderEnablementStore
    ) -> Task<Void, Never>? {
        // Legacy disabled-list mode defaults new providers to on already — nothing to detect.
        guard enablement.enabledIDs != nil else { return nil }
        let currentIDs = Set(providers.map(\.provider.id))
        // An enabled-list store with no known set can't tell "new" from "user turned it off" —
        // baseline without probing rather than risk overriding a real choice.
        guard !enablement.knownIDs.isEmpty else {
            enablement.registerKnownProviders(currentIDs)
            return nil
        }
        let newIDs = enablement.registerKnownProviders(currentIDs)
        guard !newIDs.isEmpty else { return nil }

        return Task {
            let probes = providers
                .filter { newIDs.contains($0.provider.id) }
                .map { runtime in
                    (runtime.provider.id, Task { await runtime.hasLocalCredentials() })
                }
            for (id, probe) in probes where await probe.value {
                // The probe takes a moment; if the user already turned the provider on themselves,
                // leave their toggle alone (setEnabled would be a no-op anyway).
                guard !enablement.isEnabled(id) else { continue }
                enablement.setEnabled(true, for: id)
            }
        }
    }

    public var providerSettings: [EmbeddedProviderSetting] {
        registry.providers.map {
            EmbeddedProviderSetting(
                id: $0.id,
                name: displayName(for: $0),
                isEnabled: enablement.isEnabled($0.id)
            )
        }
    }

    public func setProviderEnabled(_ enabled: Bool, id: String) {
        enablement.setEnabled(enabled, for: id)
    }

    // MARK: - API keys

    /// The providers that take a user-entered API key (Kimi, Z.ai, OpenRouter), with their current
    /// key status, so a host app's settings UI can offer add/replace/clear without knowing the
    /// vendor's internal key-store types.
    public var apiKeyProviders: [EmbeddedAPIKeyProvider] {
        providers.compactMap { runtime in
            guard let managing = runtime as? any APIKeyManaging else { return nil }
            return EmbeddedAPIKeyProvider(
                id: managing.provider.id,
                name: displayName(for: managing.provider),
                status: EmbeddedAPIKeyStatus(managing.apiKeyStatus)
            )
        }
    }

    /// The raw key for reveal-in-settings; `nil` when none is set.
    public func currentAPIKey(providerID: String) -> String? {
        apiKeyManager(for: providerID)?.currentAPIKey()
    }

    /// Save (or replace) the provider's key, then refresh that provider so the dashboard shows the
    /// new key's data immediately.
    public func saveAPIKey(_ key: String, providerID: String) throws {
        guard let manager = apiKeyManager(for: providerID) else { return }
        try manager.saveAPIKey(key)
        refreshAfterKeyChange(providerID)
    }

    /// Clear the saved key (falling back to an environment key when present), then refresh.
    public func deleteAPIKey(providerID: String) throws {
        guard let manager = apiKeyManager(for: providerID) else { return }
        try manager.deleteAPIKey()
        refreshAfterKeyChange(providerID)
    }

    private func apiKeyManager(for providerID: String) -> (any APIKeyManaging)? {
        providers.first {
            $0.provider.id == providerID
        } as? any APIKeyManaging
    }

    private func refreshAfterKeyChange(_ providerID: String) {
        dataStore.clearFailureBackoff(for: providerID)
        Task { await dataStore.refresh(providerID: providerID, force: true) }
    }

    public func refresh(force: Bool = false) async -> EmbeddedUsageSnapshot {
        if let initialProviderDetectionTask {
            await initialProviderDetectionTask.value
            self.initialProviderDetectionTask = nil
        }
        await dataStore.refreshAll(force: force)
        return snapshot()
    }

    private static func seedEmbeddedProvidersIfNeeded(
        providers: [ProviderRuntime],
        enablement: ProviderEnablementStore
    ) -> Task<Void, Never>? {
        guard enablement.enabledIDs == nil else { return nil }

        let providerIDs = Set(providers.map(\.provider.id))
        let fallback = Set(["claude", "codex", "cursor"])
            .intersection(providerIDs)
        enablement.registerKnownProviders(providerIDs)
        enablement.seedEnabledProviders(fallback)

        return Task {
            let probes = providers.map { provider in
                (
                    provider.provider.id,
                    Task { await provider.hasLocalCredentials() }
                )
            }
            var detected = Set<String>()
            for (id, probe) in probes where await probe.value {
                detected.insert(id)
            }
            guard enablement.enabledIDs == fallback,
                  !detected.isEmpty
            else {
                return
            }
            enablement.seedEnabledProviders(detected)
        }
    }

    public func snapshot() -> EmbeddedUsageSnapshot {
        let providerRows = registry.providers.map { provider in
            makeProvider(
                provider,
                snapshot: dataStore.snapshots[provider.id]
            )
        }
        .filter { $0.isEnabled || $0.errorMessage != nil }

        return EmbeddedUsageSnapshot(
            providers: providerRows,
            models: Dictionary(
                uniqueKeysWithValues: EmbeddedUsagePeriod.allCases.map {
                    ($0, makeModels(for: $0))
                }
            ),
            refreshedAt: dataStore.lastRefreshAt
        )
    }

    private func makeProvider(
        _ provider: Provider,
        snapshot: ProviderSnapshot?
    ) -> EmbeddedUsageProvider {
        var metrics: [EmbeddedUsageMetric] = []
        var trend: [EmbeddedUsageTrendPoint] = []
        var periods: [EmbeddedUsagePeriod: EmbeddedUsagePeriodValue] = [:]

        for (index, line) in (snapshot?.lines ?? []).enumerated() {
            switch line {
            case .progress(
                let label,
                let used,
                let limit,
                _,
                let resetsAt,
                let periodDurationMilliseconds,
                _
            ):
                let fraction = limit > 0
                    ? min(max(used / limit, 0), 1)
                    : nil
                let remaining = fraction.map {
                    "\(Int(((1 - $0) * 100).rounded()))% left"
                } ?? "No data"
                metrics.append(
                    EmbeddedUsageMetric(
                        id: "\(provider.id).\(index).\(label)",
                        label: label,
                        value: remaining,
                        fractionUsed: fraction,
                        resetsAt: resetsAt,
                        periodDurationMilliseconds:
                            periodDurationMilliseconds
                    )
                )
            case .values(
                let label,
                let values,
                _,
                _,
                _,
                _
            ):
                if let period = embeddedPeriod(for: label) {
                    periods[period] = periodValue(values)
                } else {
                    metrics.append(
                        EmbeddedUsageMetric(
                            id: "\(provider.id).\(index).\(label)",
                            label: label,
                            value: display(values),
                            fractionUsed: fractionUsed(values),
                            resetsAt: nil,
                            periodDurationMilliseconds: nil
                        )
                    )
                }
            case .chart(_, let points, _):
                trend = points.map {
                    EmbeddedUsageTrendPoint(
                        label: $0.label,
                        value: $0.value
                    )
                }
            case .text(let label, let value, _, _),
                 .badge(let label, let value, _, _):
                metrics.append(
                    EmbeddedUsageMetric(
                        id: "\(provider.id).\(index).\(label)",
                        label: label,
                        value: value,
                        fractionUsed: nil,
                        resetsAt: nil,
                        periodDurationMilliseconds: nil
                    )
                )
            }
        }

        return EmbeddedUsageProvider(
            id: provider.id,
            name: displayName(for: provider),
            plan: snapshot?.plan,
            isEnabled: enablement.isEnabled(provider.id),
            isStale: snapshot.map {
                Date().timeIntervalSince($0.refreshedAt) > 600
            } ?? true,
            metrics: metrics,
            trend: trend,
            periods: periods,
            errorMessage: dataStore.providerErrors[provider.id]
        )
    }

    private func makeModels(
        for period: EmbeddedUsagePeriod
    ) -> [EmbeddedModelUsage] {
        let sources: [CrossProviderModelUsageSource] =
            registry.providers.compactMap { provider in
            guard enablement.isEnabled(provider.id),
                  let history = dataStore.snapshots[provider.id]?.usageHistory
            else {
                return nil
            }
            return CrossProviderModelUsageSource(
                providerID: provider.id,
                providerTitle: displayName(for: provider),
                history: history
            )
        }
        let total = CrossProviderModelUsageAggregator.total(
            for: nativePeriod(period),
            sources: sources
        )

        return total.displayRows(namedModelLimit: 8).map { model in
            let provider = model.providers.max {
                $0.tokenCount < $1.tokenCount
            }
            return EmbeddedModelUsage(
                id: "\(period.rawValue).\(model.id)",
                modelName: model.model,
                providerName: provider?.providerTitle ?? "Multiple",
                tokens: Double(model.totalTokens),
                costUSD: model.costUSD
            )
        }
    }

    private func displayName(for provider: Provider) -> String {
        accounts.resolvedDisplayName(cardID: provider.id)
            ?? provider.displayName
    }

    private func embeddedPeriod(
        for label: String
    ) -> EmbeddedUsagePeriod? {
        switch label {
        case UsagePeriod.today.lineLabel:
            return .today
        case UsagePeriod.yesterday.lineLabel:
            return .yesterday
        case UsagePeriod.last30.lineLabel:
            return .last30Days
        default:
            return nil
        }
    }

    private func nativePeriod(
        _ period: EmbeddedUsagePeriod
    ) -> UsagePeriod {
        switch period {
        case .today: .today
        case .yesterday: .yesterday
        case .last30Days: .last30
        }
    }

    private func periodValue(
        _ values: [MetricValue]
    ) -> EmbeddedUsagePeriodValue {
        EmbeddedUsagePeriodValue(
            tokens: values
                .filter { $0.kind == .count && $0.label == "tokens" }
                .reduce(0) { $0 + $1.number },
            costUSD: optionalSum(
                values
                    .filter { $0.kind == .dollars }
                    .map(\.number)
            )
        )
    }

    private func display(_ values: [MetricValue]) -> String {
        values.map { value in
            switch value.kind {
            case .dollars:
                return String(format: "$%.2f", value.number)
            case .percent:
                return "\(Int(value.number.rounded()))%"
            case .count:
                let suffix = value.label.map { " \($0)" } ?? ""
                return "\(compactNumber(value.number))\(suffix)"
            }
        }
        .joined(separator: " · ")
    }

    private func fractionUsed(_ values: [MetricValue]) -> Double? {
        guard let percent = values.first(where: {
            $0.kind == .percent
        }) else {
            return nil
        }
        return min(max(percent.number / 100, 0), 1)
    }

    private func optionalSum(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +)
    }

    private func compactNumber(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000...:
            return String(
                format: "%.1fM",
                value / 1_000_000
            )
            .replacingOccurrences(of: ".0M", with: "M")
        case 1_000...:
            return String(
                format: "%.1fK",
                value / 1_000
            )
            .replacingOccurrences(of: ".0K", with: "K")
        default:
            return String(format: "%.0f", value)
        }
    }
}
