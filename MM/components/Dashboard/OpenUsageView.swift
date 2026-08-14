import SwiftUI

struct HomeUsageStrip: View {
    @ObservedObject private var client = OpenUsageClient.shared

    var body: some View {
        ZStack {
            providerMarks(
                client.homeProviders.filter { $0.family == "kimi" }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            providerMarks(
                client.homeProviders.filter { $0.family != "kimi" }
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            if client.homeProviders.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                    Text(client.isLoading ? "正在读取用量" : "暂无用量")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            if client.providers.isEmpty {
                await client.refresh(force: false)
            }
        }
    }

    @ViewBuilder
    private func providerMarks(_ providers: [OpenUsageProvider]) -> some View {
        if !providers.isEmpty {
            HStack(spacing: 18) {
                ForEach(providers) { provider in
                    HomeProviderMark(provider: provider)
                }
            }
        }
    }
}

private struct HomeProviderMark: View {
    let provider: OpenUsageProvider

    private var metrics: [OpenUsageProvider.Metric] {
        Array(
            provider.metrics
                .filter { $0.fractionRemaining != nil }
                .prefix(provider.family == "cursor" ? 2 : 1)
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            ProviderIcon(provider: provider)
                .frame(width: 18, height: 18)

            if metrics.isEmpty {
                Text("—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if metrics.count == 1 {
                Text(percent(metrics[0]))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            } else {
                VStack(alignment: .leading, spacing: -1) {
                    ForEach(metrics) { metric in
                        Text(percent(metric))
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .accessibilityElement(children: .combine)
    }

    private func percent(_ metric: OpenUsageProvider.Metric) -> String {
        guard let remaining = metric.fractionRemaining else {
            return metric.value
        }
        return "\(Int((remaining * 100).rounded()))%"
    }
}

struct OpenUsageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var client = OpenUsageClient.shared
    @State private var showsDetails = false
    @AppStorage(UsagePeriod.storageKey) private var tokenPeriodRawValue =
        UsagePeriod.today.rawValue

    let onPreferredHeightChange: (CGFloat) -> Void

    var body: some View {
        Group {
            if showsDetails {
                detail
                    .transition(.opacity)
            } else {
                overview
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: showsDetails
        )
        .task {
            if client.providers.isEmpty {
                await client.refresh(force: false)
            }
        }
        .onAppear(perform: updatePreferredHeight)
        .onChange(of: maximumVisibleModelCount) { _, _ in
            updatePreferredHeight()
        }
    }

    private var maximumVisibleModelCount: Int {
        UsagePeriod.allCases
            .map { client.models(for: $0).count }
            .max() ?? 0
    }

    private var tokenPeriod: UsagePeriod {
        UsagePeriod(rawValue: tokenPeriodRawValue) ?? .today
    }

    private var preferredWindowHeight: CGFloat {
        let additionalRows = max(0, maximumVisibleModelCount - 2)
        return openNotchSize.height + CGFloat(additionalRows * 34)
    }

    private func updatePreferredHeight() {
        onPreferredHeightChange(preferredWindowHeight)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text("Token")
                    .font(.system(size: 15, weight: .bold))
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showsDetails = true
                } label: {
                    Label("详情", systemImage: "list.bullet")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(UsageToolbarButtonStyle())

                refreshButton
            }
            .frame(height: 28)

            VStack(spacing: 6) {
                UsagePeriodPicker(
                    selection: Binding(
                        get: { tokenPeriod },
                        set: { tokenPeriodRawValue = $0.rawValue }
                    )
                )

                ModelUsageBarChart(
                    models: client.models(for: tokenPeriod),
                    totalTokens: client.totalTokens(for: tokenPeriod)
                )
            }
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(UsageSurface(radius: 14))
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var detail: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    showsDetails = false
                } label: {
                    Label("Usage", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(UsageToolbarButtonStyle())

                Spacer()
                refreshButton
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(client.providers) { provider in
                        ProviderQuotaCard(provider: provider)
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var refreshButton: some View {
        Button {
            Task { await client.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(client.isLoading ? 360 : 0))
                .animation(
                    client.isLoading
                        ? .linear(duration: 0.8).repeatForever(
                            autoreverses: false
                        )
                        : .default,
                    value: client.isLoading
                )
        }
        .buttonStyle(UsageToolbarButtonStyle())
        .disabled(client.isLoading)
        .accessibilityLabel("刷新用量")
    }

}

private struct UsagePeriodPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: UsagePeriod
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsagePeriod.allCases) { period in
                segment(period)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Color.white.opacity(0.055))
        )
    }

    private func segment(_ period: UsagePeriod) -> some View {
        let isSelected = selection == period
        return Button {
            selection = period
        } label: {
            Text(period.title)
                .font(
                    .system(
                        size: 10,
                        weight: isSelected ? .semibold : .medium
                    )
                )
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 25)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .matchedGeometryEffect(
                        id: "usagePeriod",
                        in: selectionNamespace
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: selection
        )
    }
}

private struct ModelUsageBarChart: View {
    let models: [OpenUsageModelMetric]
    let totalTokens: Double

    var body: some View {
        if models.isEmpty {
            HStack {
                Image(systemName: "cpu")
                Text("当前周期暂无模型用量")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(models) { model in
                        ModelUsageBarRow(
                            model: model,
                            totalTokens: max(totalTokens, 1)
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ModelUsageBarRow: View {
    let model: OpenUsageModelMetric
    let totalTokens: Double

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text(model.modelName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                Text(
                    "\(OpenUsageClient.compactNumber(model.tokens)) Token"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

                Text(cost)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(providerColor(model.providerName))
                        .frame(
                            width: geometry.size.width * fraction
                        )
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(model.modelName)，\(OpenUsageClient.compactNumber(model.tokens)) Token，\(cost)"
        )
    }

    private var fraction: Double {
        min(max(model.tokens / totalTokens, 0), 1)
    }

    private var cost: String {
        guard let cost = model.cost else { return "费用不可用" }
        return String(format: "$%.2f", cost)
    }
}

private struct ProviderQuotaCard: View {
    let provider: OpenUsageProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ProviderIcon(provider: provider)
                    .frame(width: 18, height: 18)
                Text(provider.name)
                    .font(.system(size: 14, weight: .bold))
                if let plan = provider.plan {
                    Text(plan)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if provider.isStale {
                    Text("已缓存")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            VStack(spacing: 9) {
                if let error = provider.errorMessage,
                   provider.metrics.isEmpty {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(provider.metrics.prefix(4)) { metric in
                    ProviderQuotaRow(metric: metric)
                }

                if !provider.trend.isEmpty {
                    HStack(alignment: .bottom) {
                        Text("用量趋势")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        UsageSparkline(points: provider.trend)
                            .frame(width: 160, height: 30)
                    }
                }

                ProviderPeriodRows(provider: provider)
            }
            .padding(10)
            .background(UsageSurface(radius: 12))
        }
    }
}

private struct ProviderQuotaRow: View {
    let metric: OpenUsageProvider.Metric

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(metric.label)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(displayValue)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                if let resetsAt = metric.resetsAt {
                    Text("· \(resetLabel(resetsAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.11))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width
                                * (metric.fractionRemaining ?? 0)
                        )
                }
            }
            .frame(height: 4)
        }
    }

    /// Prefer structured remaining fraction over string surgery on the
    /// vendor's English display string ("N% left").
    private var displayValue: String {
        if let remaining = metric.fractionRemaining {
            return "\(Int((remaining * 100).rounded()))% 剩余"
        }
        return metric.value
    }

    private func resetLabel(_ date: Date) -> String {
        let seconds = max(0, date.timeIntervalSinceNow)
        let days = Int(seconds / 86_400)
        let hours = Int(seconds.truncatingRemainder(
            dividingBy: 86_400
        ) / 3_600)
        if days > 0 {
            return "\(days)d \(hours)h 后重置"
        }
        return "\(hours)h 后重置"
    }
}

private struct UsageSparkline: View {
    let points: [OpenUsageProvider.TrendPoint]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(points.map(\.value).max() ?? 1, 1)
            let spacing: CGFloat = 2
            let count = max(points.count, 1)
            let width = max(
                1,
                (geometry.size.width
                    - spacing * CGFloat(count - 1))
                    / CGFloat(count)
            )

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(points.enumerated()), id: \.offset) {
                    _,
                    point in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(
                            width: width,
                            height: max(
                                2,
                                geometry.size.height
                                    * point.value / maximum
                            )
                        )
                }
            }
        }
        .accessibilityLabel("用量趋势")
    }
}

private struct ProviderPeriodRows: View {
    let provider: OpenUsageProvider

    var body: some View {
        VStack(spacing: 4) {
            ForEach(UsagePeriod.allCases) { period in
                if let value = provider.periods[period],
                   value.tokens > 0 || value.cost != nil {
                    HStack {
                        Text(period.title)
                            .font(.system(size: 9, weight: .semibold))
                        Spacer()
                        Text(display(value))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func display(
        _ value: OpenUsageProvider.PeriodValue
    ) -> String {
        let tokenText =
            "\(OpenUsageClient.compactNumber(value.tokens)) Token"
        guard let cost = value.cost else { return tokenText }
        return String(format: "$%.2f · %@", cost, tokenText)
    }
}

private struct ProviderIcon: View {
    let provider: OpenUsageProvider

    var body: some View {
        Group {
            switch provider.family {
            case "claude":
                Image("provider-claude")
                    .resizable()
            case "codex":
                Image("provider-codex")
                    .resizable()
            case "cursor":
                Image("provider-cursor")
                    .resizable()
            case "grok":
                Image("provider-grok")
                    .resizable()
            case "copilot":
                Image("provider-copilot")
                    .resizable()
            case "devin":
                Image("provider-devin")
                    .resizable()
            case "antigravity":
                Image("provider-antigravity")
                    .resizable()
            case "opencode":
                Image("provider-opencode")
                    .resizable()
            case "openrouter":
                Image("provider-openrouter")
                    .resizable()
            case "kimi":
                Image("provider-kimi")
                    .resizable()
            case "pi":
                Image("provider-pi")
                    .resizable()
            case "zai":
                Image("provider-zai")
                    .resizable()
            default:
                Image(systemName: "circle.hexagongrid.fill")
                    .resizable()
            }
        }
        .scaledToFit()
        .foregroundStyle(.white.opacity(0.88))
        .accessibilityHidden(true)
    }
}

private struct UsageSurface: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.white.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.white.opacity(0.045))
            }
    }
}

private struct UsageToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 28)
            .background(
                Capsule().fill(
                    Color.white.opacity(
                        configuration.isPressed ? 0.13 : 0.065
                    )
                )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

private func providerColor(_ id: String) -> Color {
    let family = (
        id.split(separator: ":").first.map(String.init) ?? id
    ).lowercased()
    return switch family {
    case "claude": Color(red: 0.88, green: 0.48, blue: 0.30)
    case "codex": Color(red: 0.08, green: 0.68, blue: 0.55)
    case "cursor": Color.white.opacity(0.72)
    case "grok": Color(red: 0.52, green: 0.56, blue: 0.62)
    case "copilot": Color(red: 0.56, green: 0.48, blue: 0.88)
    case "pi": Color(red: 0.45, green: 0.62, blue: 0.95)
    case "kimi": Color(red: 0.04, green: 0.40, blue: 1.00)
    default: Color.white.opacity(0.44)
    }
}
