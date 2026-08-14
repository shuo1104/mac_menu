import Foundation
import Testing
@testable import OpenUsageKit

/// Real-shaped Kimi For Coding `/coding/v1/usages` payloads: `limits[].detail` is the rolling
/// 5-hour session window, `usage` the weekly quota; `resetTime` shows up as an ISO string or a
/// seconds/milliseconds epoch depending on the window.
let sampleKimiUsages = """
{
  "limits": [
    {
      "window": { "duration": 60, "timeUnit": "TIME_UNIT_MINUTE" },
      "detail": { "limit": "20", "remaining": "18", "resetTime": "2026-04-10T12:00:00Z" }
    },
    {
      "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
      "detail": { "limit": "100", "remaining": "40", "resetTime": "2026-04-10T15:00:00Z" }
    }
  ],
  "usage": { "limit": "1000", "remaining": "250", "resetTime": 1776009600000 }
}
"""

@Suite struct KimiUsageMapperTests {
    @Test func mapsFiveHourAndWeeklyWindows() throws {
        let lines = try KimiUsageMapper.map(Data(sampleKimiUsages.utf8))
        #expect(lines.count == 2)

        guard case .progress(let sessionLabel, let sessionUsed, let sessionLimit, _, let sessionResets, let sessionPeriod, _) = lines[0] else {
            Issue.record("expected session progress line, got \(lines[0])")
            return
        }
        #expect(sessionLabel == "Session")
        #expect(sessionLimit == 100)
        #expect(sessionUsed == 60) // (100 - 40) / 100
        #expect(sessionPeriod == MetricPeriod.sessionMs)
        #expect(sessionResets == Date(timeIntervalSince1970: 1775833200))

        guard case .progress(let weeklyLabel, let weeklyUsed, let weeklyLimit, _, let weeklyResets, let weeklyPeriod, _) = lines[1] else {
            Issue.record("expected weekly progress line, got \(lines[1])")
            return
        }
        #expect(weeklyLabel == "Weekly")
        #expect(weeklyLimit == 100)
        #expect(weeklyUsed == 75) // (1000 - 250) / 1000
        #expect(weeklyPeriod == MetricPeriod.weekMs)
        #expect(weeklyResets == Date(timeIntervalSince1970: 1776009600))
    }

    @Test func acceptsSecondsEpochResetTime() throws {
        let body = #"{"usage": {"limit": 10, "remaining": 10, "resetTime": 1776009600}}"#
        let lines = try KimiUsageMapper.map(Data(body.utf8))
        guard case .progress(_, let used, _, _, let resets, _, _) = lines.first else {
            Issue.record("expected progress line")
            return
        }
        #expect(used == 0)
        #expect(resets == Date(timeIntervalSince1970: 1776009600))
    }

    @Test func nonPositiveResetTimeMeansNoActiveWindow() throws {
        let body = #"{"usage": {"limit": 10, "remaining": 3, "resetTime": 0}}"#
        let lines = try KimiUsageMapper.map(Data(body.utf8))
        guard case .progress(_, _, _, _, let resets, _, _) = lines.first else {
            Issue.record("expected progress line")
            return
        }
        #expect(resets == nil)
    }

    @Test func missingWindowsAreNoDataNotAnError() throws {
        #expect(try KimiUsageMapper.map(Data(#"{}"#.utf8)) == [.noUsageData])
        // A window with a non-positive limit is an explicit "no active window", not bad data.
        let zeroLimit = #"{"limits": [{"detail": {"limit": 0, "remaining": 0}}]}"#
        #expect(try KimiUsageMapper.map(Data(zeroLimit.utf8)) == [.noUsageData])
    }

    @Test func malformedPayloadThrows() {
        #expect(throws: KimiUsageError.invalidResponse) {
            try KimiUsageMapper.map(Data("not json".utf8))
        }
        // Present-but-unreadable window values are invalid, not zero usage.
        let badWindow = #"{"usage": {"limit": "lots", "remaining": 3}}"#
        #expect(throws: KimiUsageError.invalidResponse) {
            try KimiUsageMapper.map(Data(badWindow.utf8))
        }
    }
}
