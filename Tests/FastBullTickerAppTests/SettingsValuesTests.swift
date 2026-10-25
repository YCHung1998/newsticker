import Testing
import Foundation
@testable import FastBullTickerApp

// settings-gear task 3：`seekHoldSeconds`／`pollIntervalSeconds` 的欄位、預設、解析與夾制、動作與經 store 寫回。
// 執行：swift test --filter SettingsValues。此檔刻意不 import FastBullTickerCore（避免 `TickerStyle` 同名歧義）。
// 全部純函式或暫存目錄（StyleEnv），不碰使用者真實的 style.json。
@Suite struct SettingsValuesTests {
    private func parse(_ json: String) -> StyleParseResult {
        switch StyleParser.parse(Data(json.utf8)) {
        case .success(let r): return r
        case .failure(let e): Issue.record("解析失敗：\(e)"); return StyleParseResult(style: .default, warnings: [])
        }
    }
    private func warnings(_ r: StyleParseResult, _ key: String) -> [StyleWarning.Kind] { r.warnings.filter { $0.key == key }.map(\.kind) }

    // MARK: 欄位與預設

    @Test func defaultsKeepTodaysBehaviour() {
        let d = TickerStyle.default
        #expect(d.seekHoldSeconds == 1 && d.pollIntervalSeconds == 10)
        #expect(StyleRanges.seekHoldSeconds == 0.5...10 && StyleRanges.pollIntervalSteps == [10, 30, 60])
        #expect(d.isValid)
    }

    @Test func keysIncludeTheTwoNewOnesAndNothingAboutLaunchAtLogin() {
        #expect(TickerStyle.keys.suffix(2) == ["seekHoldSeconds", "pollIntervalSeconds"])
        #expect(TickerStyle.keys.count == 17)
        #expect(!TickerStyle.keys.contains { $0.lowercased().contains("login") || $0.lowercased().contains("launch") })
    }

    @Test func encodedJSONHasBothKeysAndRoundTrips() throws {
        var s = TickerStyle.default
        s.seekHoldSeconds = 2.5; s.pollIntervalSeconds = 30
        let obj = try JSONSerialization.jsonObject(with: s.normalizedJSON()) as! [String: Any]
        #expect(obj["seekHoldSeconds"] as? Double == 2.5 && obj["pollIntervalSeconds"] as? Int == 30)
        #expect(try JSONDecoder().decode(TickerStyle.self, from: s.normalizedJSON()) == s)
    }

    @Test func oldFilesWithoutTheNewKeysStillLoadWithDefaultsAndNoWarnings() {
        let r = parse(##"{"fontSize": 20, "scrollSpeed": 150}"##)
        #expect(r.style.seekHoldSeconds == 1 && r.style.pollIntervalSeconds == 10)
        #expect(warnings(r, "seekHoldSeconds").isEmpty && warnings(r, "pollIntervalSeconds").isEmpty)
        #expect(r.style.fontSize == 20, "既有欄位不受影響")
    }

    // MARK: seekHoldSeconds

    @Test func seekHoldInRangeIsKept() {
        for v in ["0.5", "1", "2.5", "10"] {
            let r = parse("{\"seekHoldSeconds\": \(v)}")
            #expect(r.style.seekHoldSeconds == Double(v) && warnings(r, "seekHoldSeconds").isEmpty, "\(v)")
        }
    }

    @Test func seekHoldOutOfRangeIsClampedWithWarning() {
        for (v, want) in [("0", 0.5), ("-3", 0.5), ("0.49", 0.5), ("10.5", 10.0), ("99", 10.0)] {
            let r = parse("{\"seekHoldSeconds\": \(v)}")
            #expect(r.style.seekHoldSeconds == want, "\(v)")
            #expect(warnings(r, "seekHoldSeconds") == [.clamped], "\(v)")
        }
    }

    @Test func seekHoldWrongTypeFallsBackToDefault() {
        for v in ["\"2\"", "true", "null", "[1]"] {
            let r = parse("{\"seekHoldSeconds\": \(v)}")
            #expect(r.style.seekHoldSeconds == 1 && warnings(r, "seekHoldSeconds") == [.invalidType], "\(v)")
        }
    }

    // MARK: pollIntervalSeconds

    @Test func pollIntervalSteps() {
        for v in [10, 30, 60] {
            let r = parse("{\"pollIntervalSeconds\": \(v)}")
            #expect(r.style.pollIntervalSeconds == v && warnings(r, "pollIntervalSeconds").isEmpty)
        }
    }

    @Test func pollIntervalNonStepClampsToNearestStepTiesGoToTheLarger() {
        for (v, want) in [("5", 10), ("0", 10), ("-1", 10), ("11", 10), ("19", 10), ("20", 30), ("29", 30), ("45", 60), ("61", 60), ("1000", 60)] {
            let r = parse("{\"pollIntervalSeconds\": \(v)}")
            #expect(r.style.pollIntervalSeconds == want, "\(v) → \(r.style.pollIntervalSeconds)")
            #expect(warnings(r, "pollIntervalSeconds") == [.clamped], "\(v)")
        }
    }

    @Test func pollIntervalWrongTypeOrFractionFallsBackToDefault() {
        for v in ["30.5", "\"30\"", "true", "null"] {
            let r = parse("{\"pollIntervalSeconds\": \(v)}")
            #expect(r.style.pollIntervalSeconds == 10 && warnings(r, "pollIntervalSeconds") == [.invalidType], "\(v)")
        }
    }

    @Test func clampedAppliesTheSameRules() {
        var s = TickerStyle.default
        s.seekHoldSeconds = 0; s.pollIntervalSeconds = 45
        #expect(!s.isValid)
        let c = s.clamped()
        #expect(c.seekHoldSeconds == 0.5 && c.pollIntervalSeconds == 60 && c.isValid)
        s.seekHoldSeconds = 99; s.pollIntervalSeconds = 5
        #expect(s.clamped().seekHoldSeconds == 10 && s.clamped().pollIntervalSeconds == 10)
        #expect(TickerStyle.nearestPollStep(20) == 30 && TickerStyle.nearestPollStep(19) == 10 && TickerStyle.nearestPollStep(45) == 60)
    }

    // MARK: 動作

    @Test func actionsSetOnlyTheirOwnField() {
        var s = TickerStyle.default
        #expect(StyleMenuModel.apply(.setSeekHoldSeconds(3), to: &s))
        #expect(StyleMenuModel.apply(.setPollIntervalSeconds(30), to: &s))
        var expected = TickerStyle.default
        expected.seekHoldSeconds = 3; expected.pollIntervalSeconds = 30
        #expect(s == expected)
    }

    @Test func styleMenuEntriesAreUnchangedByTheNewActions() {
        let ids = StyleMenuModel.entries(for: .default).map(\.id)
        #expect(ids == ["fontSize", "scrollSpeed", "replayCount", "cornerRadius", "liveColors", "separator1", "showTime", "showLabel", "separator2", "openFile", "reset"])
    }

    @Test func storeClampsAndWritesBack() {
        let e = StyleEnv()
        e.store.start()
        e.store.update { StyleMenuModel.apply(.setSeekHoldSeconds(99), to: &$0); StyleMenuModel.apply(.setPollIntervalSeconds(45), to: &$0) }
        #expect(e.store.style.seekHoldSeconds == 10 && e.store.style.pollIntervalSeconds == 60)
        e.settleWrite()
        let text = String(decoding: e.bytes ?? Data(), as: UTF8.self)
        #expect(text.contains("\"seekHoldSeconds\" : 10") && text.contains("\"pollIntervalSeconds\" : 60"), "寫回的是夾制後的值：\(text)")
    }

    @Test func hotReloadOfTheNewKeysIsApplied() {
        let e = StyleEnv()
        e.store.start()
        e.put(##"{"seekHoldSeconds": 4, "pollIntervalSeconds": 30}"##)
        e.fireAndSettle()
        #expect(e.store.style.seekHoldSeconds == 4 && e.store.style.pollIntervalSeconds == 30)
    }
}
