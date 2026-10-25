import Testing
import Foundation
@testable import FastBullTickerCore

/// `title`／`important` 欄位規則（change jin10-source），與 protocol/schema/item.schema.json 逐條對應。
@Suite struct ItemTitleImportantTests {
    func itemWith(_ extra: String) -> String {
        #"{"v":1,"type":"items","items":[{"source":"jin10","id":"1","published_at_ms":1,"text":"本文"\#(extra)}]}"#
    }
    func items(_ extra: String) -> [Item]? {
        if case .success(.items(let i)) = decode(itemWith(extra)) { return i } else { return nil }
    }

    @Test func missingBothAreNil() {
        let i = items("")?[0]
        #expect(i?.title == nil)
        #expect(i?.important == nil)
    }

    @Test func titleAndImportantAreDecoded() {
        let i = items(#","title":"標題","important":true"#)?[0]
        #expect(i?.title == "標題")
        #expect(i?.important == true)
        #expect(items(#","important":false"#)?[0].important == false)
    }

    @Test func emptyOrNullTitleIsRejected() {
        #expect(reason(decode(itemWith(#","title":"""#))) == .schema)
        #expect(reason(decode(itemWith(#","title":null"#))) == .schema)
        #expect(reason(decode(itemWith(#","title":1"#))) == .schema)
    }

    @Test func nonBooleanImportantIsRejected() {
        for bad in ["null", "1", #""true""#, "[]"] {
            #expect(reason(decode(itemWith(#","important":\#(bad)"#))) == .schema, "\(bad)")
        }
    }

    @Test func unknownKeyStillRejected() {
        #expect(reason(decode(itemWith(#","priority":true"#))) == .schema)
    }

    // 版面：標題在時間與本文之間；有標題才多一段；截斷只動本文。
    let tz = TimeZone(secondsFromGMT: 8 * 3600)!
    let count: TextMeasurer = { Double($0.count) }

    @Test func layoutPlacesTitleBetweenTimeAndText() {
        let it = Item(source: "jin10", id: "1", publishedAtMs: 0, text: "本文", title: "標題", important: true)
        let l = layoutItem(it, timeZone: tz, maxWidth: 1000, measurer: count)
        #expect(l.title == "標題")
        #expect(l.important)
        #expect(l.displayString == "08:00:00 標題 本文")
        #expect(l.width == Double("08:00:00 標題 本文".count))
    }

    @Test func layoutWithoutTitleIsUnchanged() {
        let it = Item(source: "fastbull", id: "1", publishedAtMs: 0, text: "本文")
        let l = layoutItem(it, timeZone: tz, maxWidth: 1000, measurer: count)
        #expect(l.title == "")
        #expect(!l.important)
        #expect(l.displayString == "08:00:00 本文")
    }

    @Test func truncationKeepsTitleAndEllipsizesText() {
        let it = Item(source: "jin10", id: "1", publishedAtMs: 0, text: String(repeating: "字", count: 50), title: "標題")
        let l = layoutItem(it, timeZone: tz, maxWidth: 25, measurer: count)
        #expect(l.truncated)
        #expect(l.title == "標題")
        #expect(l.text.hasSuffix("…"))
        #expect(l.width <= 25)
    }

    @Test func boldMeasurerReceivesTimeAndTitleAsBoldPrefix() {
        var seen: [(String, Int)] = []
        let bm: BoldAwareMeasurer = { s, n in seen.append((s, n)); return Double(s.count) }
        let it = Item(source: "jin10", id: "1", publishedAtMs: 0, text: "本文", title: "標題")
        _ = layoutItem(it, timeZone: tz, maxWidth: 1000, measurer: { _ in -1 }, boldMeasurer: bm)
        #expect(seen.first?.0 == "08:00:00 標題 本文")
        #expect(seen.first?.1 == "08:00:00 標題".utf16.count)
    }

    @Test func placedItemCarriesTitleAndImportant() {
        var cfg = SchedulerConfig()
        cfg.timeZone = tz
        var s = TickerScheduler(config: cfg, clock: { 0 }, measurer: count)
        _ = s.receive(.snapshot([Item(source: "jin10", id: "1", publishedAtMs: 0, text: "本文", title: "標題", important: true)]))
        let placed = s.tick()
        #expect(placed.first?.title == "標題")
        #expect(placed.first?.important == true)
    }
}
