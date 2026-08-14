import Foundation
import OpenUsageKit

enum UsagePeriod: String, CaseIterable, Identifiable {
    /// App-local key — deliberately not the vendor's
    /// `openusage.totalSpend.period`, so the notch UI and the vendor
    /// package cannot clobber each other's period preference.
    static let storageKey = "MM.openusage.tokenPeriod"

    case today = "Today"
    case yesterday = "Yesterday"
    case month = "Last 30 Days"

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今天"
        case .yesterday: "昨天"
        case .month: "30 天"
        }
    }
}

struct OpenUsageProvider: Identifiable, Equatable {
    struct Metric: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
        let fractionUsed: Double?
        let resetsAt: Date?
        let periodDurationMilliseconds: Int?

        var fractionRemaining: Double? {
            fractionUsed.map { max(0, 1 - $0) }
        }
    }

    struct TrendPoint: Equatable {
        let label: String
        let value: Double
    }

    struct PeriodValue: Equatable {
        let tokens: Double
        let cost: Double?
    }

    let id: String
    let name: String
    let plan: String?
    let metrics: [Metric]
    let isStale: Bool
    let trend: [TrendPoint]
    let periods: [UsagePeriod: PeriodValue]
    let errorMessage: String?

    var family: String {
        id.split(separator: ":").first.map(String.init) ?? id
    }

    var compactMetric: Metric? {
        metrics.first(where: { $0.fractionRemaining != nil })
            ?? metrics.first
    }

    func tokens(for period: UsagePeriod) -> Double {
        periods[period]?.tokens ?? 0
    }
}

struct OpenUsageModelMetric: Identifiable, Equatable {
    let id: String
    let providerName: String
    let modelName: String
    let tokens: Double
    let cost: Double?
}

struct OpenUsageProviderSetting: Identifiable, Equatable {
    let id: String
    let name: String
    var isEnabled: Bool
}

struct OpenUsageAPIKeyProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let status: EmbeddedAPIKeyStatus
}

@MainActor
final class OpenUsageClient: ObservableObject {
    static let shared = OpenUsageClient()

    @Published private(set) var providers: [OpenUsageProvider] = []
    @Published private(set) var modelsByPeriod:
        [UsagePeriod: [OpenUsageModelMetric]] = [:]
    @Published private(set) var providerSettings:
        [OpenUsageProviderSetting] = []
    @Published private(set) var apiKeyProviders:
        [OpenUsageAPIKeyProvider] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    /// Refresh cadence in seconds (minimum 30). Replaces the legacy minutes key, which is
    /// migrated on first read below.
    @Published var refreshIntervalSeconds: Int {
        didSet {
            defaults.set(
                max(30, refreshIntervalSeconds),
                forKey: Keys.refreshIntervalSeconds
            )
            scheduleRefreshLoop()
        }
    }

    @Published var backgroundRefreshEnabled: Bool {
        didSet {
            defaults.set(
                backgroundRefreshEnabled,
                forKey: Keys.backgroundRefreshEnabled
            )
            scheduleRefreshLoop()
        }
    }

    private enum Keys {
        static let refreshIntervalSeconds =
            "MM.openusage.refreshIntervalSeconds"
        /// Superseded by `refreshIntervalSeconds`; read once for migration.
        static let legacyRefreshIntervalMinutes =
            "MM.openusage.refreshIntervalMinutes"
        static let backgroundRefreshEnabled =
            "MM.openusage.backgroundRefreshEnabled"
    }

    private let service = EmbeddedOpenUsageService()
    private let defaults = UserDefaults.standard
    private var refreshLoop: Task<Void, Never>?

    private init() {
        if let savedSeconds = defaults.object(
            forKey: Keys.refreshIntervalSeconds
        ) as? Int {
            refreshIntervalSeconds = max(30, savedSeconds)
        } else {
            let savedMinutes = defaults.integer(
                forKey: Keys.legacyRefreshIntervalMinutes
            )
            refreshIntervalSeconds = savedMinutes > 0
                ? max(30, savedMinutes * 60)
                : 300
        }
        backgroundRefreshEnabled = defaults.object(
            forKey: Keys.backgroundRefreshEnabled
        ) as? Bool ?? true
        providerSettings = service.providerSettings.map {
            OpenUsageProviderSetting(
                id: $0.id,
                name: $0.name,
                isEnabled: $0.isEnabled
            )
        }
        reloadAPIKeyProviders()

        Task { [weak self] in
            guard let self else { return }
            apply(service.snapshot())
            await refresh(force: false)
            scheduleRefreshLoop()
        }
    }

    deinit {
        refreshLoop?.cancel()
    }

    var totalTokens: Double {
        totalTokens(for: .today)
    }

    var tokenSummary: String {
        Self.compactNumber(totalTokens)
    }

    var homeProviders: [OpenUsageProvider] {
        ["kimi", "codex", "cursor"].compactMap { family in
            providers.first { $0.family == family }
        }
    }

    func totalTokens(for period: UsagePeriod) -> Double {
        providers.reduce(0) {
            $0 + $1.tokens(for: period)
        }
    }

    func models(for period: UsagePeriod) -> [OpenUsageModelMetric] {
        modelsByPeriod[period] ?? []
    }

    func refresh(force: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let snapshot = await service.refresh(force: force)
        apply(snapshot)
        providerSettings = service.providerSettings.map {
            OpenUsageProviderSetting(
                id: $0.id,
                name: $0.name,
                isEnabled: $0.isEnabled
            )
        }
        reloadAPIKeyProviders()
    }

    func setProviderEnabled(_ enabled: Bool, id: String) {
        service.setProviderEnabled(enabled, id: id)
        if let index = providerSettings.firstIndex(where: {
            $0.id == id
        }) {
            providerSettings[index].isEnabled = enabled
        }
        Task { await refresh(force: enabled) }
    }

    // MARK: - API keys

    func saveAPIKey(_ key: String, providerID: String) throws {
        try service.saveAPIKey(key, providerID: providerID)
        reloadAPIKeyProviders()
        Task { await refresh(force: false) }
    }

    func deleteAPIKey(providerID: String) throws {
        try service.deleteAPIKey(providerID: providerID)
        reloadAPIKeyProviders()
        Task { await refresh(force: false) }
    }

    func currentAPIKey(providerID: String) -> String? {
        service.currentAPIKey(providerID: providerID)
    }

    private func reloadAPIKeyProviders() {
        apiKeyProviders = service.apiKeyProviders.map {
            OpenUsageAPIKeyProvider(
                id: $0.id,
                name: $0.name,
                status: $0.status
            )
        }
    }

    private func apply(_ snapshot: EmbeddedUsageSnapshot) {
        providers = snapshot.providers
            .filter(\.isEnabled)
            .map { provider in
                OpenUsageProvider(
                    id: provider.id,
                    name: provider.name,
                    plan: provider.plan,
                    metrics: provider.metrics.map {
                        OpenUsageProvider.Metric(
                            id: $0.id,
                            label: $0.label,
                            value: $0.value,
                            fractionUsed: $0.fractionUsed,
                            resetsAt: $0.resetsAt,
                            periodDurationMilliseconds:
                                $0.periodDurationMilliseconds
                        )
                    },
                    isStale: provider.isStale,
                    trend: provider.trend.map {
                        OpenUsageProvider.TrendPoint(
                            label: $0.label,
                            value: $0.value
                        )
                    },
                    periods: Dictionary(
                        uniqueKeysWithValues: provider.periods.compactMap {
                            embeddedPeriod, value in
                            guard let period = UsagePeriod(
                                embeddedPeriod
                            ) else {
                                return nil
                            }
                            return (
                                period,
                                OpenUsageProvider.PeriodValue(
                                    tokens: value.tokens,
                                    cost: value.costUSD
                                )
                            )
                        }
                    ),
                    errorMessage: provider.errorMessage
                )
            }

        modelsByPeriod = Dictionary(
            uniqueKeysWithValues: snapshot.models.compactMap {
                embeddedPeriod, models in
                guard let period = UsagePeriod(embeddedPeriod) else {
                    return nil
                }
                return (
                    period,
                    models.map {
                        OpenUsageModelMetric(
                            id: $0.id,
                            providerName: $0.providerName,
                            modelName: $0.modelName,
                            tokens: $0.tokens,
                            cost: $0.costUSD
                        )
                    }
                )
            }
        )
        lastUpdated = snapshot.refreshedAt

        let usable = providers.contains {
            !$0.metrics.isEmpty || !$0.periods.isEmpty
        }
        let providerErrors = providers.compactMap(\.errorMessage)
        if usable {
            errorMessage = nil
        } else if let first = providerErrors.first {
            errorMessage = first
        } else {
            errorMessage =
                "未发现可用凭证，请先登录 Codex、Cursor 或其他服务。"
        }
    }

    private func scheduleRefreshLoop() {
        refreshLoop?.cancel()
        guard backgroundRefreshEnabled else { return }

        let seconds = max(30, refreshIntervalSeconds)
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                await self.refresh(force: false)
            }
        }
    }

    static func compactNumber(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
                .replacingOccurrences(of: ".0M", with: "M")
        case 1_000...:
            return String(format: "%.1fK", value / 1_000)
                .replacingOccurrences(of: ".0K", with: "K")
        default:
            return String(format: "%.0f", value)
        }
    }
}

private extension UsagePeriod {
    init?(_ period: EmbeddedUsagePeriod) {
        switch period {
        case .today:
            self = .today
        case .yesterday:
            self = .yesterday
        case .last30Days:
            self = .month
        }
    }
}
