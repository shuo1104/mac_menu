import Foundation
import Testing
@testable import OpenUsageKit

@Suite struct ClaudeLogUsageScannerTests {
    @Test func aggregateNormalizesInclusiveDeepSeekInputTokens() throws {
        let timestamp = try #require(OpenUsageISO8601.date(from: "2026-08-12T03:32:04.161Z"))
        let since = try #require(OpenUsageISO8601.date(from: "2026-08-12T00:00:00.000Z"))
        let rates = ModelRates(
            inputPerMillion: 0.14,
            outputPerMillion: 0.28,
            cacheWritePerMillion: 0,
            cacheReadPerMillion: 0.0028
        )
        let pricing = ModelPricing(
            supplement: PricingSupplement(),
            primary: PricingCatalog(entries: ["deepseek-v4-flash": rates]),
            secondary: PricingCatalog()
        )
        let entry = ClaudeLogUsageScanner.Entry(
            timestamp: timestamp,
            tokens: TokenBreakdown(input: 43_170, cacheRead: 42_496, output: 401),
            messageID: "message-1",
            requestID: nil,
            model: "deepseek-v4-flash-0731"
        )

        let scan = ClaudeLogUsageScanner.aggregate(entries: [entry], since: since, pricing: pricing)
        let day = try #require(scan.series.daily.first)

        #expect(day.totalTokens == 43_571)
        #expect(abs((day.costUSD ?? 0) - 0.0003256288) < 0.0000000001)
    }
}
