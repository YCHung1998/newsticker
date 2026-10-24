import Testing
import Foundation
@testable import FastBullTickerApp

/// ticker-style-settings 1.1：`StyleParser.parse`（整份失敗 vs 欄位層級）。純函式、固定輸入與固定種子。
@Suite struct StyleParserTests {
    private func parse(_ json: String) -> Result<StyleParseResult, StyleLoadError> { StyleParser.parse(Data(json.utf8)) }
    private func ok(_ json: String, sourceLocation: SourceLocation = #_sourceLocation) -> StyleParseResult? {
        switch parse(json) {
        case .success(let r): return r
        case .failure(let e): Issue.record("應可解析，卻失敗：\(e)", sourceLocation: sourceLocation); return nil
        }
    }
    private func failure(_ json: String) -> StyleLoadError? { if case .failure(let e) = parse(json) { return e } else { return nil } }
    private func kinds(_ r: StyleParseResult) -> [StyleWarning.Kind] { r.warnings.map(\.kind) }

    // MARK: 缺鍵、未知鍵、基本

    @Test func emptyObjectGivesDefaultsWithoutWarnings() {
        let r = ok("{}")
        #expect(r?.style == .default && r?.warnings.isEmpty == true)
    }

    @Test func missingAndUnknownKeys() {
        guard let r = ok(##"{"fontSize": 20, "colour": "#FF0000"}"##) else { return }
        var expected = TickerStyle.default; expected.fontSize = 20
        #expect(r.style == expected)
        #expect(r.warnings.count == 1 && r.warnings[0].kind == .unknownKey && r.warnings[0].key == "colour")
        #expect(r.unknownKeys == ["colour"])
    }

    @Test func versionMissingMeansOne() { #expect(ok(##"{"fontSize": 12}"##)?.style.version == 1) }

    @Test func versionAcceptsOneAndOnePointZero() {
        #expect(ok(##"{"version": 1}"##) != nil)
        #expect(ok(##"{"version": 1.0}"##) != nil)
    }

    // MARK: 夾制

    @Test func outOfRangeNumbersAreClampedWithOneWarningEach() {
        guard let r = ok(##"{"fontSize": 5, "scrollSpeed": 999, "cornerRadius": -3, "replayCount": 100}"##) else { return }
        #expect(r.style.fontSize == 10 && r.style.scrollSpeed == 300 && r.style.cornerRadius == 0 && r.style.replayCount == 30)
        #expect(kinds(r) == [.clamped, .clamped, .clamped, .clamped])
        #expect(Set(r.warnings.map(\.key)) == ["fontSize", "scrollSpeed", "cornerRadius", "replayCount"])
        #expect(r.warnings.first { $0.key == "fontSize" }?.message.contains("5") == true, "警告含原值")
    }

    @Test func boundariesThemselvesAreAcceptedWithoutWarning() {
        for (k, lo, hi) in [("cornerRadius", "0", "21"), ("fontSize", "10", "26"), ("scrollSpeed", "20", "300"), ("replayCount", "3", "30")] {
            #expect(ok("{\"\(k)\": \(lo)}")?.warnings.isEmpty == true, "\(k) 下限")
            #expect(ok("{\"\(k)\": \(hi)}")?.warnings.isEmpty == true, "\(k) 上限")
        }
        #expect(ok(##"{"cornerRadius": 100}"##)?.style.cornerRadius == 21)
        #expect(ok(##"{"cornerRadius": 21.5}"##)?.style.cornerRadius == 21)
    }

    @Test func extremeNumbersClampWithoutTrapping() {
        #expect(ok(##"{"replayCount": 1e30}"##)?.style.replayCount == 30)
        #expect(ok(##"{"replayCount": -1e30}"##)?.style.replayCount == 3)
        #expect(ok(##"{"fontSize": 1e300}"##)?.style.fontSize == 26)
    }

    // MARK: 型別錯誤

    @Test func wrongTypesFallBackToFieldDefaultsOnly() {
        guard let r = ok(##"{"fontSize": "16", "showTime": 1, "showLabel": "true", "scrollSpeed": null, "cornerRadius": [1], "liveText": 5, "fontSize2": 1, "replayCount": true}"##) else { return }
        #expect(r.style.fontSize == 16 && r.style.showTime == true && r.style.showLabel == true && r.style.scrollSpeed == 90)
        #expect(r.style.cornerRadius == 0 && r.style.liveText.hex == "#000000" && r.style.replayCount == 10)
        #expect(kinds(r).filter { $0 == .invalidType }.count == 7)
        #expect(kinds(r).contains(.unknownKey))
    }

    @Test func wrongTypeDoesNotAffectOtherFields() {
        guard let r = ok(##"{"fontSize": "16", "scrollSpeed": 150, "showTime": 1, "liveBackground": "#FFE45C"}"##) else { return }
        #expect(r.style.scrollSpeed == 150 && r.style.liveBackground.hex == "#FFE45C")
        #expect(r.warnings.count == 2)
    }

    @Test func replayCountMustBeInteger() {
        #expect(ok(##"{"replayCount": 10.0}"##)?.style.replayCount == 10)
        #expect(ok(##"{"replayCount": 10.0}"##)?.warnings.isEmpty == true)
        guard let r = ok(##"{"replayCount": 10.5}"##) else { return }
        #expect(r.style.replayCount == 10 && kinds(r) == [.invalidType])
        guard let r2 = ok(##"{"replayCount": 7.5}"##) else { return }
        #expect(r2.style.replayCount == 10, "非整數視為非法 → 預設值，而非取整")
    }

    // MARK: 色碼

    @Test func validColorsAreNormalized() {
        guard let r = ok(##"{"liveBackground": "#ffe45c"}"##) else { return }
        #expect(r.style.liveBackground.hex == "#FFE45C" && r.warnings.isEmpty)
    }

    @Test func invalidColorsFallBackToFieldDefault() {
        for bad in ["red", "#FFF", "#FFE45C80", "FFE45C", "#GGGGGG"] {
            guard let r = ok("{\"liveBackground\": \"\(bad)\", \"liveText\": \"#102030\"}") else { return }
            #expect(r.style.liveBackground.hex == "#FFFFFF", "\(bad) → 預設")
            #expect(r.style.liveText.hex == "#102030", "其他欄位不受影響")
            let w = r.warnings.first { $0.kind == .invalidColor }
            #expect(w?.key == "liveBackground" && w?.message.contains(bad) == true, "警告含鍵名與原字串")
        }
    }

    // MARK: labelText

    @Test func labelTextRules() {
        let long = String(repeating: "字", count: 20)
        guard let r = ok("{\"labelText\": \"\(long)\"}") else { return }
        #expect(r.style.labelText == String(repeating: "字", count: 16) && kinds(r) == [.labelTruncated])
        guard let r2 = ok(##"{"labelText": "   "}"##) else { return }
        #expect(r2.style.labelText == "即時財經快訊" && kinds(r2) == [.invalidLabel])
        #expect(ok(##"{"labelText": ""}"##)?.style.labelText == "即時財經快訊")
        #expect(ok(##"{"labelText": "  快訊  "}"##)?.style.labelText == "快訊", "前後空白修剪")
        #expect(ok(##"{"labelText": 5}"##).map { kinds($0) } == [.invalidType])
    }

    @Test func labelLengthCountsCharactersNotUTF16Units() {
        let family = "👨‍👩‍👧‍👦"          // 1 個 Character（grapheme cluster），多個 unicode scalar
        let sixteen = String(repeating: family, count: 16)
        #expect(ok("{\"labelText\": \"\(sixteen)\"}")?.warnings.isEmpty == true)
        #expect(ok("{\"labelText\": \"\(sixteen)\(family)\"}")?.style.labelText == sixteen)
    }

    // MARK: 對比度

    @Test func lowContrastWarnsButKeepsValues() {
        guard let r = ok(##"{"liveBackground": "#FFFF00", "liveText": "#FFFFFF"}"##) else { return }
        #expect(r.style.liveBackground.hex == "#FFFF00" && r.style.liveText.hex == "#FFFFFF", "照用，不夾制")
        let w = r.warnings.filter { $0.kind == .lowContrast }
        #expect(w.count == 1 && w[0].key == "live" && w[0].message.contains("1.07"))
    }

    @Test func threeGroupsAreCheckedIndependently() {
        guard let r = ok(##"{"replayBackground": "#808080", "replayText": "#888888", "labelColor": "#D91A21"}"##) else { return }
        #expect(Set(r.warnings.filter { $0.kind == .lowContrast }.map(\.key)) == ["replay", "label"])
    }

    @Test func presetsProduceNoWarning() {
        for p in LiveColorPreset.all {
            let json = "{\"liveBackground\": \"\(p.background.hex)\", \"liveText\": \"\(p.text.hex)\"}"
            #expect(ok(json)?.warnings.isEmpty == true, "\(p.name)")
        }
    }

    // MARK: 整份失敗

    @Test func wholeFileFailures() {
        #expect(failure("{ \"fontSize\": ") != nil)
        if case .notJSON = failure("{ \"fontSize\": ") {} else { Issue.record("語法錯誤應為 notJSON") }
        #expect(failure("[]") == .notObject)
        #expect(failure("42") == .notObject)
        #expect(failure("\"x\"") == .notObject)
        #expect(failure("null") == .notObject)
        if case .notJSON = failure("") {} else { Issue.record("空檔應為 notJSON") }
        #expect(StyleParser.parse(Data([0xFF, 0xFE, 0x7B, 0x7D])) == .failure(.notUTF8))
        for v in ["2", "0", "\"1\"", "1.5", "true", "null", "[1]"] {
            if case .unsupportedVersion = failure("{\"version\": \(v)}") {} else { Issue.record("version \(v) 應整份失敗") }
        }
    }

    @Test func sizeLimit64KB() {
        let pad = String(repeating: " ", count: StyleRanges.maxFileBytes - 2)
        if case .success = StyleParser.parse(Data(("{" + pad + "}").utf8)) {} else { Issue.record("剛好 64KB 應可解析") }
        let over = Data(("{" + pad + " }").utf8)
        #expect(over.count == StyleRanges.maxFileBytes + 1)
        #expect(StyleParser.parse(over) == .failure(.tooLarge(bytes: StyleRanges.maxFileBytes + 1)))
    }

    @Test func utf8BOMIsTolerated() {
        var d = Data([0xEF, 0xBB, 0xBF]); d.append(Data(##"{"fontSize": 12}"##.utf8))
        if case .success(let r) = StyleParser.parse(d) { #expect(r.style.fontSize == 12) } else { Issue.record("BOM 應被容忍") }
    }

    @Test func duplicateKeysDoNotCrashAndStayValid() {
        // 重複鍵取哪一個由 JSONDecoder 決定（規格未定義）；只要求不崩潰、結果合法。
        let f = ok(##"{"fontSize": 12, "fontSize": 14}"##)?.style.fontSize
        #expect(f == 12 || f == 14)
    }

    @Test func parseIsPureAndRepeatable() {
        let j = ##"{"fontSize": 99, "x": 1, "liveText": "red"}"##
        #expect(parse(j) == parse(j))
    }

    @Test func writtenNormalizedFormReparsesToSameStyleWithoutWarnings() {
        var s = TickerStyle.default
        s.cornerRadius = 12.5; s.fontSize = 22; s.scrollSpeed = 133; s.replayCount = 20; s.showTime = false
        s.liveBackground = LiveColorPreset.all[2].background; s.liveText = LiveColorPreset.all[2].text
        guard case .success(let r) = StyleParser.parse(s.normalizedJSON()) else { Issue.record("正規化輸出應可解析"); return }
        #expect(r.style == s && r.warnings.isEmpty)
    }

    // MARK: 隨機輸入永遠得到合法樣式

    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    }

    @Test func randomInputsAlwaysYieldValidStyle() throws {
        var rng = Rng(state: 20261024)
        let knownKeys = TickerStyle.keys + ["unknown", "colour", ""]
        let numbers: [Any] = [0, 1, 3, 10, 16, 21, 22, 26, 27, 30, 31, 90, 300, 301, -1, -1e9, 1e30, 0.5, 7.5, 10.0, 1e-9]
        let strings: [Any] = ["", " ", "red", "#FFF", "#FFE45C", "#ffe45c", "#GGGGGG", "#FFE45C80", "即時財經快訊", String(repeating: "字", count: 40), "  x  ", "👨‍👩‍👧‍👦"]
        let others: [Any] = [true, false, NSNull(), [1, 2], ["a": 1]]
        var successes = 0, failures = 0, warningsSeen = 0
        for _ in 0..<3000 {
            var obj: [String: Any] = [:]
            for _ in 0..<rng.int(12) {
                let key = rng.pick(knownKeys)
                if key == "version" && rng.int(10) != 0 { obj[key] = 1; continue }      // 多數情況讓 version 合法，才會走到欄位層級
                switch rng.int(3) {
                case 0: obj[key] = rng.pick(numbers)
                case 1: obj[key] = rng.pick(strings)
                default: obj[key] = rng.pick(others)
                }
            }
            let data = try JSONSerialization.data(withJSONObject: obj)
            switch StyleParser.parse(data) {
            case .success(let r):
                successes += 1; warningsSeen += r.warnings.count
                #expect(r.style.isValid, "非法輸出：\(String(decoding: data, as: UTF8.self)) → \(r.style)")
                #expect(r.style.version == 1)
            case .failure:
                failures += 1
                #expect(obj["version"] != nil, "只有帶 version 的輸入才可能整份失敗：\(String(decoding: data, as: UTF8.self))")
            }
        }
        #expect(successes > 2000 && failures > 10 && warningsSeen > 1000, "場景有涵蓋各路徑：\(successes) \(failures) \(warningsSeen)")
    }

    @Test func randomGarbageBytesNeverCrash() {
        var rng = Rng(state: 7)
        for _ in 0..<2000 {
            let n = rng.int(80)
            let d = Data((0..<n).map { _ in UInt8(truncatingIfNeeded: rng.next()) })
            if case .success(let r) = StyleParser.parse(d) { #expect(r.style.isValid) }
        }
    }
}
