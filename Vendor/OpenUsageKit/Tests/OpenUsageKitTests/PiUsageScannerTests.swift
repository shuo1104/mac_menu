import Foundation
import Testing
@testable import OpenUsageKit

/// A real-shaped pi session line: assistant message with nested usage + carried cost.
let sampleAnthropicLine = """
{"id":"msg_01","type":"message","timestamp":"2025-04-10T09:33:40.000Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-4-5","usage":{"input":100,"output":50,"cacheWrite":20,"cacheWrite1h":10,"cacheRead":30,"totalTokens":180,"cost":{"total":0.0123}}}}
"""

/// An unmapped provider line — OpenUsage has no card for moonshot, so the Pi card must keep it.
let sampleMoonshotLine = """
{"id":"msg_02","type":"message","timestamp":"2025-04-10T09:40:00.000Z","message":{"role":"assistant","provider":"moonshot","model":"kimi-k3","usage":{"input":1000,"output":200,"totalTokens":1200,"cost":{"total":0.05}}}}
"""

/// Non-assistant lines (and lines without usage) must be skipped.
let sampleUserLine = """
{"id":"msg_03","type":"message","timestamp":"2025-04-10T09:41:00.000Z","message":{"role":"user","provider":"anthropic","content":"hi"}}
"""

private struct NullEnvironment: EnvironmentReading {
    func value(for name: String) -> String? { nil }
}

private func makeEntry(
    id: String? = nil,
    timestamp: Date,
    provider: String = "anthropic",
    model: String = "claude-sonnet-4-5",
    carriedCost: Double? = nil,
    tokens: Int
) -> PiUsageScanner.Entry {
    PiUsageScanner.Entry(
        id: id,
        timestamp: timestamp,
        provider: provider,
        model: model,
        carriedCost: carriedCost,
        tokens: TokenBreakdown(input: tokens, output: 0),
        reportedTotalTokens: tokens
    )
}

@Suite struct PiUsageScannerTests {
    @Test func parsesMappedProviderLine() throws {
        let entry = try #require(PiUsageScanner.parseLine(Data(sampleAnthropicLine.utf8)))
        #expect(entry.provider == "anthropic")
        #expect(entry.model == "claude-sonnet-4-5")
        #expect(entry.carriedCost == 0.0123)
        #expect(entry.reportedTotalTokens == 180)
        #expect(entry.tokens.input == 100)
        #expect(entry.tokens.output == 50)
        #expect(entry.tokens.cacheRead == 30)
        #expect(entry.tokens.cacheWrite1h == 10)
        #expect(entry.tokens.cacheWrite5m == 10)
    }

    @Test func parsesUnmappedProviderLine() throws {
        let entry = try #require(PiUsageScanner.parseLine(Data(sampleMoonshotLine.utf8)))
        #expect(entry.provider == "moonshot")
        #expect(entry.model == "kimi-k3")
        #expect(entry.carriedCost == 0.05)
        #expect(entry.reportedTotalTokens == 1200)
    }

    @Test func skipsNonAssistantAndNoUsageLines() {
        #expect(PiUsageScanner.parseLine(Data(sampleUserLine.utf8)) == nil)
        #expect(PiUsageScanner.parseLine(Data("{}".utf8)) == nil)
        #expect(PiUsageScanner.parseLine(Data("not json".utf8)) == nil)
    }

    @Test func dedupKeepsFirstOccurrence() throws {
        let date = try #require(OpenUsageISO8601.date(from: "2025-04-10T09:33:40.000Z"))
        let first = makeEntry(id: "msg_01", timestamp: date, tokens: 100)
        let unnamed = makeEntry(timestamp: date, tokens: 1)
        let deduped = PiUsageScanner.dedup([first, first, unnamed])
        #expect(deduped.count == 2)
        #expect(deduped[0].id == "msg_01")
    }

    @Test func aggregateUsesCarriedCostWhenPresent() async throws {
        let pricing = await ModelPricingStore.shared.current()
        let day1 = try #require(OpenUsageISO8601.date(from: "2025-04-10T09:33:40.000Z"))
        let day2 = try #require(OpenUsageISO8601.date(from: "2025-04-11T09:33:40.000Z"))
        let since = try #require(OpenUsageISO8601.date(from: "2025-04-01T00:00:00.000Z"))

        let scan = PiUsageScanner.aggregate(
            entries: [
                makeEntry(id: "a", timestamp: day1, carriedCost: 1.5, tokens: 100),
                makeEntry(id: "b", timestamp: day2, provider: "moonshot", model: "kimi-k3", carriedCost: 0.25, tokens: 50)
            ],
            since: since,
            pricing: pricing
        )

        // Newest-first series.
        #expect(scan.series.daily.count == 2)
        #expect(scan.series.daily[0].date == "2025-04-11")
        #expect(scan.series.daily[0].totalTokens == 50)
        #expect(abs((scan.series.daily[0].costUSD ?? 0) - 0.25) < 0.0001)
        #expect(scan.series.daily[1].date == "2025-04-10")
        #expect(scan.series.daily[1].totalTokens == 100)
        #expect(abs((scan.series.daily[1].costUSD ?? 0) - 1.5) < 0.0001)

        // Model breakdown keeps the unmapped provider's model for the Pi card.
        let models = scan.modelUsage?.daily.flatMap { $0.models }.map(\.model)
        #expect(models?.contains("kimi-k3") == true)
    }

    @Test func scanReadsSessionFilesUnderTempHome() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-scanner-test-\(UUID().uuidString)", isDirectory: true)
        let sessions = temp.appendingPathComponent(".pi/agent/sessions/project", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let file = sessions.appendingPathComponent("session-1.jsonl")
        try Data((sampleAnthropicLine + "\n" + sampleMoonshotLine + "\n").utf8).write(to: file)

        let scanner = PiUsageScanner(environment: NullEnvironment(), homeDirectory: { temp })
        let pricing = await ModelPricingStore.shared.current()
        let now = try #require(OpenUsageISO8601.date(from: "2025-04-11T12:00:00.000Z"))

        let scan = try #require(await scanner.scan(daysBack: 30, now: now, pricing: pricing))
        #expect(scan.series.daily.count == 1)
        #expect(scan.series.daily[0].totalTokens == 180 + 1200)
        #expect(abs((scan.series.daily[0].costUSD ?? 0) - (0.0123 + 0.05)) < 0.0001)
    }

    @Test func hasUsageLogsDetectsFiles() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-scanner-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let scanner = PiUsageScanner(environment: NullEnvironment(), homeDirectory: { temp })
        #expect(await scanner.hasUsageLogs() == false)

        let sessions = temp.appendingPathComponent(".pi/agent/sessions/project", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data((sampleAnthropicLine + "\n").utf8)
            .write(to: sessions.appendingPathComponent("session-1.jsonl"))
        #expect(await scanner.hasUsageLogs() == true)
    }
}
