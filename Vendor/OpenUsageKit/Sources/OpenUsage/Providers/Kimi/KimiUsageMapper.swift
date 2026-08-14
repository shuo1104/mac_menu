import Foundation

/// Builds metric lines from the Kimi For Coding `GET /coding/v1/usages` payload:
/// - the `limits[]` entry whose window is 300 minutes — the rolling 5-hour session window,
/// - `usage{limit,remaining,resetTime}` — the weekly quota.
///
/// Both meters are rendered as percentages so the unit Kimi meters in (requests vs tokens) doesn't
/// leak into the UI. `resetTime` arrives as an ISO-8601 string or a seconds/milliseconds epoch
/// (≤0 means "no active window"). The endpoint is undocumented; the shape matches what Kimi's own
/// subscription UI consumes. The mapper is pure (no I/O) so it tests cleanly against sample payloads.
enum KimiUsageMapper {
    static let sessionPeriodMs = MetricPeriod.sessionMs
    static let weeklyPeriodMs = MetricPeriod.weekMs

    /// Session + weekly meters from the usages payload. A payload with neither window is a valid
    /// no-data state (key OK, no active subscription windows); a window object whose `limit` /
    /// `remaining` are present but unreadable is an invalid response rather than zero usage.
    static func map(_ body: Data) throws -> [MetricLine] {
        guard let root = ProviderParse.jsonObject(body) else {
            throw KimiUsageError.invalidResponse
        }

        var lines: [MetricLine] = []

        if let rawLimits = root["limits"] {
            guard let limits = rawLimits as? [[String: Any]] else {
                throw KimiUsageError.invalidResponse
            }
            if let entry = limits.first(where: isFiveHourWindow),
               let detail = entry["detail"] as? [String: Any],
               let line = try percentLine(detail, label: "Session", periodMs: sessionPeriodMs) {
                lines.append(line)
            }
        }

        if let rawUsage = root["usage"] {
            guard let usage = rawUsage as? [String: Any] else {
                throw KimiUsageError.invalidResponse
            }
            if let line = try percentLine(usage, label: "Weekly", periodMs: weeklyPeriodMs) {
                lines.append(line)
            }
        }

        return lines.isEmpty ? [.noUsageData] : lines
    }

    // MARK: - Private

    /// Current responses encode 5h as 300 minutes. Keep the earlier string spelling readable so a
    /// compatible proxy returning `"5h"` does not lose the session meter.
    private static func isFiveHourWindow(_ entry: [String: Any]) -> Bool {
        if let window = entry["window"] as? String {
            return window.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "5h"
        }
        guard let window = entry["window"] as? [String: Any],
              ProviderParse.number(window["duration"]) == 300,
              let unit = window["timeUnit"] as? String
        else {
            return false
        }
        return unit.uppercased() == "TIME_UNIT_MINUTE"
    }

    /// A percentage meter from a `{limit, remaining, resetTime}` window object. `nil` when the window
    /// carries no quota (`limit` ≤ 0 or absent entirely); a half-present window throws.
    private static func percentLine(
        _ object: [String: Any],
        label: String,
        periodMs: Int
    ) throws -> MetricLine? {
        let limit = ProviderParse.number(object["limit"])
        let remaining = ProviderParse.number(object["remaining"])
        if limit == nil && remaining == nil {
            // Absent window is fine; a present-but-unreadable one is not.
            if object["limit"] != nil || object["remaining"] != nil {
                throw KimiUsageError.invalidResponse
            }
            return nil
        }
        guard let limit, let remaining, limit > 0, remaining >= 0 else {
            if let limit, limit <= 0 { return nil } // explicit "no active window"
            throw KimiUsageError.invalidResponse
        }

        let used = max(0, limit - remaining)
        let percentage = ProviderParse.clampPercent(used / limit * 100)
        return .progress(
            label: label,
            used: percentage,
            limit: 100,
            format: .percent,
            resetsAt: resetTime(object["resetTime"]),
            periodDurationMs: periodMs
        )
    }

    /// `resetTime` as ISO-8601 string or seconds/milliseconds epoch; ≤0 means no active window.
    private static func resetTime(_ value: Any?) -> Date? {
        if let text = (value as? String)?.nilIfEmpty {
            return OpenUsageISO8601.date(from: text)
        }
        guard let raw = ProviderParse.number(value), raw > 0 else { return nil }
        // Millisecond epochs are ≥ 1e12 for any plausible reset date; anything smaller is seconds.
        let seconds = raw >= 1_000_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}
