import Foundation

/// The calendar period shared by the dashboard's cross-provider usage cards.
///
/// Raw values continue to match the per-provider spend-row labels, preserving the Total Spend lookup
/// contract and its persisted selection while letting Model Usage use the same period switch.
enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    /// Kept at the original Total Spend key so existing period selections migrate without work.
    static let storageKey = "openusage.totalSpend.period"

    case today = "Today"
    case yesterday = "Yesterday"
    case last30 = "Last 30 Days"

    var id: String { rawValue }
    var lineLabel: String { rawValue }

    var shortLabel: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .last30: "30 Days"
        }
    }
}

/// Kept as a source-compatible name for the existing Total Spend API and persisted settings.
typealias TotalSpendPeriod = UsagePeriod
