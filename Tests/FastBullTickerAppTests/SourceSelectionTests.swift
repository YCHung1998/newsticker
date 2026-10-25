import Testing
import Foundation
@testable import FastBullTickerApp

// pluggable-sources：`NEWSTICKER_SOURCE` -> helper 的 `--source`。純邏輯，不啟動 helper、不連網。
// 執行：swift test --filter SourceSelection
@Suite struct SourceSelectionTests {
    @Test func environmentVariableName() {
        #expect(FeedClientConfig.sourceEnvironmentVariable == "NEWSTICKER_SOURCE")
    }
    @Test func unsetOrBlankIsNil() {
        #expect(FeedClientConfig.sourceID(environment: [:]) == nil)
        #expect(FeedClientConfig.sourceID(environment: ["NEWSTICKER_SOURCE": ""]) == nil)
        #expect(FeedClientConfig.sourceID(environment: ["NEWSTICKER_SOURCE": "  \n"]) == nil)
    }
    @Test func valueIsTrimmed() {
        #expect(FeedClientConfig.sourceID(environment: ["NEWSTICKER_SOURCE": " jin10 "]) == "jin10")
    }
    @Test func noSourceKeepsExistingArguments() {
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 10) == [])
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 10, source: nil) == [])
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 30, source: nil) == ["--interval-ms", "30000"])
    }
    @Test func sourceComesFirstThenInterval() {
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 10, source: "jin10") == ["--source", "jin10"])
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 60, source: "jin10") == ["--source", "jin10", "--interval-ms", "60000"])
    }
}
