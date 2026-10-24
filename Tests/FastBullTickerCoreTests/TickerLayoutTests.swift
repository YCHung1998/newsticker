import Testing
import Foundation
@testable import FastBullTickerCore

/// 假 measurer：每個 Character 寬 10；CJK（Unicode 0x2E80...0x9FFF）加倍。
func fakeMeasure(_ s: String) -> Double {
    s.reduce(0.0) { acc, ch in
        let wide = ch.unicodeScalars.first.map { (0x2E80...0x9FFF).contains($0.value) } ?? false
        return acc + (wide ? 20 : 10)
    }
}
/// 每個 Character（grapheme）固定 10。
func flatMeasure(_ s: String) -> Double { Double(s.count) * 10 }

let utc8 = TimeZone(secondsFromGMT: 8 * 3600)!
let utc0 = TimeZone(secondsFromGMT: 0)!

func item(_ text: String, ms: Int64 = 1792832201957) -> Item {
    Item(source: "fastbull", id: "1", publishedAtMs: ms, text: text)
}

@Suite struct TickerLayoutTests {
    // MARK: 時間字串
    @Test func utc8Format() { #expect(TimeFormatter(timeZone: utc8).string(forMs: 1792832201957) == "16:56:41") }
    @Test func utcFormat() { #expect(TimeFormatter(timeZone: utc0).string(forMs: 1792832201957) == "08:56:41") }
    @Test func zeroPaddedAnd24Hour() {
        let f0 = TimeFormatter(timeZone: utc0)
        #expect(f0.string(forMs: 0) == "00:00:00")
        #expect(f0.string(forMs: (5 * 60 + 9) * 1000) == "00:05:09")
        #expect(f0.string(forMs: (12 * 3600 + 5 * 60 + 9) * 1000) == "12:05:09")   // 24 小時制，不是 12 小時
        #expect(f0.string(forMs: (23 * 3600 + 59 * 60 + 59) * 1000 + 999) == "23:59:59")
        // UTC 16:05:09 在 UTC+8 跨午夜 → 當地 00:05:09
        #expect(TimeFormatter(timeZone: utc8).string(forMs: (16 * 3600 + 5 * 60 + 9) * 1000) == "00:05:09")
    }
    @Test func negativeOffsetTimezone() {
        let la = TimeZone(secondsFromGMT: -7 * 3600)!
        #expect(TimeFormatter(timeZone: la).string(forMs: 3 * 3600 * 1000) == "20:00:00")
    }

    // MARK: 寬度與截斷
    @Test func widthComesFromMeasurer() {
        let l = layoutItem(item("hello"), timeZone: utc8, maxWidth: 10_000, measurer: flatMeasure)
        #expect(l.displayString == "16:56:41 hello")
        #expect(l.width == flatMeasure("16:56:41 hello"))
        #expect(!l.truncated && l.text == "hello")
    }

    @Test func noTruncationAtExactlyMaxWidth() {
        let full = flatMeasure("16:56:41 hello")
        let l = layoutItem(item("hello"), timeZone: utc8, maxWidth: full, measurer: flatMeasure)
        #expect(!l.truncated && l.text == "hello" && l.width == full)
    }

    @Test func truncatesWithEllipsisKeepingLongestPrefix() {
        // "16:56:41 " = 9 字 = 90；max=150 → 剩 60 = 6 字，含「…」→ 5 字 + …
        let l = layoutItem(item("abcdefghij"), timeZone: utc8, maxWidth: 150, measurer: flatMeasure)
        #expect(l.truncated)
        #expect(l.text == "abcde…")
        #expect(l.width <= 150)
        #expect(flatMeasure("16:56:41 abcdef…") > 150)   // 再多一個 Character 就超過
    }

    @Test func cjkVersusLatinTruncateDifferently() {
        let a = layoutItem(item(String(repeating: "a", count: 20)), timeZone: utc8, maxWidth: 200, measurer: fakeMeasure)
        let c = layoutItem(item(String(repeating: "中", count: 20)), timeZone: utc8, maxWidth: 200, measurer: fakeMeasure)
        #expect(a.truncated && c.truncated)
        #expect(a.width <= 200 && c.width <= 200)
        #expect(c.text.count < a.text.count)
        #expect(a.text.count != c.text.count)
    }

    @Test func doesNotSplitGraphemeClusters() {
        let family = "👨‍👩‍👧‍👦"           // 1 Character、多個 unicode scalar
        let eAcute = "e\u{301}"          // 組合字元：1 Character
        let text = family + eAcute + family + "xyz"
        // 90 + 30：3 個 Character 位置含「…」→ 2 個 Character + …
        let l = layoutItem(item(text), timeZone: utc8, maxWidth: 120, measurer: flatMeasure)
        #expect(l.truncated)
        #expect(l.text == family + eAcute + "…")
    }

    @Test func ellipsisDoesNotFitStillReturnsTimeAndEllipsis() {
        let l = layoutItem(item("abcdef"), timeZone: utc8, maxWidth: 5, measurer: flatMeasure)
        #expect(l.truncated)
        #expect(l.displayString == "16:56:41 …")
    }

    @Test func timeStringIsNeverTruncated() {
        let l = layoutItem(item("abcdef"), timeZone: utc8, maxWidth: 1, measurer: flatMeasure)
        #expect(l.timeString == "16:56:41")
    }

    @Test func hugeTextTruncatesWithFewMeasurements() {
        nonisolated(unsafe) var calls = 0
        let m: TextMeasurer = { calls += 1; return flatMeasure($0) }
        let l = layoutItem(item(String(repeating: "x", count: 200_000)), timeZone: utc8, maxWidth: 600, measurer: m)
        #expect(l.truncated && l.width <= 600)
        #expect(calls < 100, "應以二分搜尋量測，實際 \(calls) 次")
    }
}

/// 連結欄位（tasks 4.1，ticker-layout「有連結的訊息保留連結欄位寬度」）。
@Suite struct LinkSlotLayoutTests {
    private func withURL(_ text: String) -> Item {
        Item(source: "fastbull", id: "1", publishedAtMs: 1792832201957, text: text, url: "https://example.test/a")
    }

    @Test func widthAddsSlotAndFlagsIt() {
        // 顯示字串 "16:56:41 " + 11 字 = 20 字元 → 200；加欄位 26 = 226
        let l = layoutItem(withURL("hello world"), timeZone: utc8, maxWidth: 10_000, linkSlotWidth: 26, measurer: flatMeasure)
        #expect(l.width == 226 && l.hasLinkSlot && !l.truncated)
        #expect(l.width - 26 == 200, "命中區本地座標為 [200, 226)")
    }

    @Test func truncationBudgetSubtractsSlot() {
        let long = withURL(String(repeating: "x", count: 100))
        let l = layoutItem(long, timeZone: utc8, maxWidth: 300, linkSlotWidth: 26, measurer: flatMeasure)
        #expect(l.truncated && l.hasLinkSlot)
        #expect(flatMeasure(l.displayString) <= 274)
        #expect(l.width <= 300 && l.width == flatMeasure(l.displayString) + 26)
        #expect(l.text.hasSuffix("…"))
    }

    @Test func withoutURLOrWithZeroSlotIsIdenticalToBefore() {
        let plain = item("hello world")
        let a = layoutItem(plain, timeZone: utc8, maxWidth: 10_000, linkSlotWidth: 26, measurer: flatMeasure)
        let b = layoutItem(plain, timeZone: utc8, maxWidth: 10_000, measurer: flatMeasure)
        #expect(a == b && !a.hasLinkSlot && a.width == 200)
        let c = layoutItem(withURL("hello world"), timeZone: utc8, maxWidth: 10_000, linkSlotWidth: 0, measurer: flatMeasure)
        #expect(c.width == 200 && !c.hasLinkSlot)
        let t1 = layoutItem(item(String(repeating: "x", count: 100)), timeZone: utc8, maxWidth: 300, measurer: flatMeasure)
        let t2 = layoutItem(item(String(repeating: "x", count: 100)), timeZone: utc8, maxWidth: 300, linkSlotWidth: 26, measurer: flatMeasure)
        #expect(t1 == t2, "無 url 的截斷不扣欄位")
    }

    // MARK: showTime（ticker-style-settings 2.1）

    @Test func showTimeFalseDisplaysOnlyText() {
        let l = layoutItem(item("T"), timeZone: utc8, maxWidth: 10_000, showTime: false, measurer: flatMeasure)
        #expect(l.timeString.isEmpty && l.text == "T" && l.displayString == "T")
        #expect(l.width == flatMeasure("T") && !l.truncated)
    }

    @Test func showTimeDefaultsToTrueAndIsIdentical() {
        let a = layoutItem(item("hello"), timeZone: utc8, maxWidth: 10_000, measurer: flatMeasure)
        let b = layoutItem(item("hello"), timeZone: utc8, maxWidth: 10_000, showTime: true, measurer: flatMeasure)
        #expect(a == b && a.displayString == "16:56:41 hello")
    }

    @Test func showTimeFalseTruncationHasNoTimePrefix() {
        // 無時間：預算 100 = 10 字，含「…」→ 9 字 + …
        let l = layoutItem(item(String(repeating: "x", count: 50)), timeZone: utc8, maxWidth: 100, showTime: false, measurer: flatMeasure)
        #expect(l.truncated && l.text == String(repeating: "x", count: 9) + "…")
        #expect(l.timeString.isEmpty && l.width <= 100)
        #expect(flatMeasure(String(repeating: "x", count: 10) + "…") > 100, "再多一個 Character 就超過")
    }

    @Test func showTimeFalseWithLinkSlotStillReservesSlot() {
        let l = layoutItem(withURL("hello"), timeZone: utc8, maxWidth: 10_000, linkSlotWidth: 26, showTime: false, measurer: flatMeasure)
        #expect(l.width == 50 + 26 && l.hasLinkSlot && l.displayString == "hello")
    }
}
