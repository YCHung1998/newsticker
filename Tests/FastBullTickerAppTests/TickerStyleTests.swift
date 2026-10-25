import Testing
import Foundation
@testable import FastBullTickerApp

/// ticker-style-settings 1.1：`TickerStyle` 欄位、預設值與原型一致、色碼、對比度。
/// 注意：此檔刻意不 import FastBullTickerCore（Core 另有同名列舉 `TickerStyle`，見 TickerStyle.swift 檔頭註解）。
@Suite struct TickerStyleTests {
    // MARK: 欄位

    @Test func encodedKeysMatchSpecTableExactly() throws {
        let obj = try JSONSerialization.jsonObject(with: TickerStyle.default.normalizedJSON()) as! [String: Any]
        #expect(Set(obj.keys) == Set(["version", "cornerRadius", "fontSize", "scrollSpeed", "replayCount", "showTime", "showLabel", "labelText",
                                      "labelBackground", "labelColor", "tapeBackground", "liveBackground", "liveText", "replayBackground", "replayText",
                                      "seekHoldSeconds", "pollIntervalSeconds"]))        // settings-gear 增加最後兩個鍵（原 15 個鍵逐字不變）
        #expect(obj.count == 17 && TickerStyle.keys.count == 17)
        #expect(Set(TickerStyle.keys) == Set(obj.keys))
    }

    @Test func roundTripThroughCodable() throws {
        var s = TickerStyle.default
        s.cornerRadius = 7.5; s.fontSize = 20; s.scrollSpeed = 150; s.replayCount = 5; s.showTime = false; s.showLabel = false
        s.labelText = "快訊"; s.liveBackground = RGBColor(hex: "#FFE45C")!; s.replayText = RGBColor(hex: "#abcdef")!
        let back = try JSONDecoder().decode(TickerStyle.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(try JSONDecoder().decode(TickerStyle.self, from: TickerStyle.default.normalizedJSON()) == .default)
    }

    @Test func normalizedJSONIsSortedIndentedUppercaseWithTrailingNewline() throws {
        var s = TickerStyle.default
        s.liveBackground = RGBColor(hex: "#ffe45c")!
        let text = String(decoding: s.normalizedJSON(), as: UTF8.self)
        #expect(text.hasSuffix("}\n") && text.contains("\n  \"cornerRadius\""))
        #expect(text.contains("\"liveBackground\" : \"#FFE45C\""))
        #expect(!text.contains("#ffe45c") && text.contains("即時財經快訊"), "中文不被轉義")
        let keysInOrder = text.split(separator: "\n").compactMap { line -> String? in
            guard let r = line.range(of: "\"[A-Za-z]+\" :", options: .regularExpression) else { return nil }
            return String(line[r].dropFirst().prefix { $0 != "\"" })
        }
        #expect(keysInOrder == keysInOrder.sorted() && keysInOrder.count == 17)
        #expect(s.normalizedJSON() == s.normalizedJSON(), "同一份樣式輸出位元組穩定")
    }

    @Test func sourceFileImportsOnlyFoundation() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FastBullTickerApp/TickerStyle.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        let imports = src.split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
        #expect(imports == ["import Foundation"])
    }

    // MARK: 預設值逐項

    @Test func defaultsAreExactlyThePrototypeValues() {
        let d = TickerStyle.default
        #expect(d.version == 1 && d.cornerRadius == 0 && d.fontSize == 16 && d.scrollSpeed == 90 && d.replayCount == 10)
        #expect(d.showTime && d.showLabel && d.labelText == "即時財經快訊")
        #expect(d.liveBackground.hex == "#FFFFFF" && d.liveText.hex == "#000000")
        #expect(d.replayBackground.hex == "#000000" && d.replayText.hex == "#FFFFFF")
        #expect(d.labelBackground.hex == "#D91A21" && d.labelColor.hex == "#FFFFFF" && d.tapeBackground.hex == "#17171A")
        #expect(d.isValid)
    }

    /// 原型常數（取自 app-shell 的 `ShellConfig.provisional` 與 `TickerView` 內的色彩字面值）。
    /// 任一端被改而另一端沒改，下面兩個測試就會紅。
    private static let prototypeTape = (r: 0.09, g: 0.09, b: 0.10)
    private static let prototypeLabelRed = (r: 0.85, g: 0.10, b: 0.13)
    private func within1of255(_ c: RGBColor, _ p: (r: Double, g: Double, b: Double)) -> Bool {
        abs(c.r - p.r) <= 1.0 / 255 && abs(c.g - p.g) <= 1.0 / 255 && abs(c.b - p.b) <= 1.0 / 255
    }

    @Test func defaultColorsMatchPrototypeWithinOneOver255() {
        #expect(within1of255(TickerStyle.default.tapeBackground, Self.prototypeTape))
        #expect(within1of255(TickerStyle.default.labelBackground, Self.prototypeLabelRed))
        #expect(!within1of255(RGBColor(hex: "#27272A")!, Self.prototypeTape), "容忍度檢查本身會咬合")
    }

    @Test func defaultsAgreeWithShellConfigPrototypeConstants() {
        let p = ShellConfig.provisional, d = TickerStyle.default
        // 仍留在 ShellConfig 的值（不屬於 TickerStyle，值不得變動）
        // settings-gear：面板寬由 28 + 150 + 100 + 370 推導為 648（原 620 − 150 − 100 = 370 的可視寬度不變）；高度仍 42。
        #expect(p.panelSize.width == 648 && p.panelSize.height == 42)
        #expect(Double(p.panelSize.width) == p.gearSlotWidth + Double(p.labelWidth) + p.strip.controlStripWidth + ShellConfig.designTapeViewport)
        #expect(p.labelWidth == 150 && p.itemPadding == 10 && p.defaultAlpha == 0.9)
        #expect(p.alphaRange.lowerBound == 0.3 && p.alphaRange.upperBound == 1.0)
        // fontSize／scrollSpeed／labelText 已從 ShellConfig 移除（4.1）；原本比對 ShellConfig 的這一行改為渲染斷言，
        // 見 StyleApplyTests.swift 的 DefaultStyleRendersLikePrototypeTests（字級、速度、標籤文字、顏色、像素）。
        // 圓角範圍上限 = 面板高的一半
        #expect(StyleRanges.cornerRadius.upperBound == Double(p.panelSize.height) / 2)
    }

    // 原本的 `prototypeColorLiteralsStillInTickerViewSource`（grep TickerView.swift 的色彩字面值）已在 4.1 改為
    // StyleApplyTests.swift 的渲染斷言（實際圖層顏色與原型常數比較），因為字面值已不在 TickerView.swift。

    // MARK: 文件（7.1）：README 的欄位表與 TickerStyle.keys 一致

    /// 讀取 README.md 第 5.5 節 `style.json` 欄位表（表頭 `| 鍵 |` 之後、空行之前）每列第一欄的鍵名。
    static func readmeFieldTableKeys(readme: String) -> [String] {
        var keys: [String] = [], inTable = false
        for line in readme.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("| 鍵 |") { inTable = true; continue }
            guard inTable else { continue }
            if !line.hasPrefix("|") { break }
            if line.hasPrefix("|---") { continue }
            let first = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            keys.append(first.trimmingCharacters(in: CharacterSet(charactersIn: "`")))
        }
        return keys
    }

    @Test func readmeFieldTableListsExactlyTheStyleKeys() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("README.md")
        let readme = try String(contentsOf: url, encoding: .utf8)
        let keys = Self.readmeFieldTableKeys(readme: readme)
        #expect(Set(keys) == Set(TickerStyle.keys) && keys.count == TickerStyle.keys.count, "README 欄位表：\(keys)")
        #expect(readme.contains("style.json"))
    }

    @Test func readmeTableParserDetectsMissingAndExtraKeys() {
        let doc = "| 鍵 | 型別 |\n|---|---|\n| `a` | x |\n| `b` | y |\n\n| 其他 | z |\n"
        #expect(Self.readmeFieldTableKeys(readme: doc) == ["a", "b"])
        #expect(Self.readmeFieldTableKeys(readme: "no table") == [])
    }

    // MARK: 範圍

    @Test func rangesAreTheSpecifiedOnes() {
        #expect(StyleRanges.cornerRadius == 0...21 && StyleRanges.fontSize == 10...26 && StyleRanges.scrollSpeed == 20...300)
        #expect(StyleRanges.replayCount == 3...30 && StyleRanges.labelTextLength == 1...16)
        #expect(StyleRanges.maxFileBytes == 65_536)
    }

    @Test func isValidRejectsOutOfRangeFields() {
        var s = TickerStyle.default
        s.fontSize = 9; #expect(!s.isValid)
        s = .default; s.replayCount = 31; #expect(!s.isValid)
        s = .default; s.labelText = ""; #expect(!s.isValid)
        s = .default; s.labelText = String(repeating: "字", count: 17); #expect(!s.isValid)
        s = .default; s.cornerRadius = 21; #expect(s.isValid)
    }

    // MARK: 色碼

    @Test func hexParsingAndNormalization() {
        let c = RGBColor(hex: "#ffe45c")
        #expect(c?.bytes.r == 255 && c?.bytes.g == 228 && c?.bytes.b == 92)
        #expect(c?.hex == "#FFE45C")
        #expect(RGBColor(hex: "#FFE45C") == c)
        for hex in ["#000000", "#FFFFFF", "#17171A", "#D91A21", "#010203"] { #expect(RGBColor(hex: hex)?.hex == hex) }
    }

    @Test func invalidHexForms() {
        for bad in ["red", "#FFF", "#FFE45C80", "FFE45C", "#GGGGGG", "", "#", "# FFE45C", "#FFE45", "#FFE45C ", "rgb(1,2,3)", "＃FFE45C", "#FFE45Ｃ"] {
            #expect(RGBColor(hex: bad) == nil, "\(bad) 應為非法")
        }
    }

    // MARK: 對比度

    @Test func contrastRatioMatchesWCAGReferenceValues() {
        let black = RGBColor(hex: "#000000")!, white = RGBColor(hex: "#FFFFFF")!
        #expect(abs(ContrastRatio.ratio(black, white) - 21) < 1e-9)
        #expect(abs(ContrastRatio.ratio(white, black) - 21) < 1e-9, "與順序無關")
        #expect(abs(ContrastRatio.ratio(white, white) - 1) < 1e-9)
        // #777777 對白色是 WCAG 常見參考值 4.48
        #expect(abs(ContrastRatio.ratio(RGBColor(hex: "#777777")!, white) - 4.48) < 0.01)
        #expect(abs(ContrastRatio.ratio(RGBColor(hex: "#FFFF00")!, white) - 1.07) < 0.01)
    }

    @Test func threeLivePresetsAllMeetAA() {
        #expect(LiveColorPreset.all.map(\.name) == ["白底黑字", "黃底黑字", "綠底白字"])
        let ratios = LiveColorPreset.all.map { ContrastRatio.ratio($0.text, $0.background) }
        #expect(abs(ratios[0] - 21) < 0.01 && abs(ratios[1] - 16.5) < 0.2 && abs(ratios[2] - 5.3) < 0.2, "\(ratios)")
        #expect(ratios.allSatisfy { $0 >= ContrastRatio.threshold })
        #expect(LiveColorPreset.all.map { $0.background.hex } == ["#FFFFFF", "#FFE45C", "#1E7B3C"])
    }

    @Test func defaultStyleHasNoContrastWarning() {
        guard case .success(let r) = StyleParser.parse(TickerStyle.default.normalizedJSON()) else { Issue.record("預設樣式應可解析"); return }
        #expect(r.warnings.isEmpty && r.style == .default)
    }
}
