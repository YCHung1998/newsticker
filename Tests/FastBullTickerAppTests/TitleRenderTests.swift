import Testing
import Foundation
import CoreText
import CoreGraphics
import ImageIO
import FastBullTickerCore
@testable import FastBullTickerApp

/// 標題粗體與重要訊息配色（change jin10-source）。
@MainActor
@Suite struct TitleRenderTests {
    let r = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384)
    private func psName(_ s: NSAttributedString, at i: Int) -> String {
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        return CTFontCopyPostScriptName(s.attribute(key, at: i, effectiveRange: nil) as! CTFont) as String
    }
    private func placed(title: String, important: Bool) -> PlacedItem {
        PlacedItem(source: "jin10", id: "1", style: .replay, timeString: "12:34:56", text: "本文內容", truncated: false,
                   tapeX: 0, width: 300, seq: 1, listID: 1, listIndex: 1, title: title, important: important)
    }

    @Test func displayPartsPutsTitleBetweenTimeAndTextAndBoldsBoth() {
        let p = ItemBitmapRenderer.displayParts(of: placed(title: "標題", important: false))
        #expect(p.text == "12:34:56 標題 本文內容")
        #expect(p.boldLength == "12:34:56 標題".utf16.count)
    }

    @Test func noTitleIsUnchanged() {
        let p = ItemBitmapRenderer.displayParts(of: placed(title: "", important: false))
        #expect(p.text == "12:34:56 本文內容")
        #expect(p.boldLength == 8)
    }

    @Test func titleRunIsBoldAndBodyRegular() {
        let s = r.attributedString("12:34:56 標題 本文內容", boldLength: "12:34:56 標題".utf16.count)
        for i in 0..<"12:34:56 標題".utf16.count { #expect(psName(s, at: i) == ItemBitmapRenderer.boldFontName, "index \(i)") }
        for i in "12:34:56 標題".utf16.count..<s.length { #expect(psName(s, at: i) == ItemBitmapRenderer.fontName, "index \(i)") }
    }

    @Test func boldMeasurerMatchesDrawingAttributedString() {
        let s = "12:34:56 標題 本文內容", n = "12:34:56 標題".utf16.count
        let direct = Double(CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(r.attributedString(s, boldLength: n)), nil, nil, nil)).rounded(.up) + 28)
        #expect(r.boldMeasurer(s, n) == direct)
    }

    @Test func importantTitleRangeIsOnlyTheTitle() {
        let r1 = ItemBitmapRenderer.titleRange(of: placed(title: "標題", important: true))
        #expect(r1 == NSRange(location: 9, length: 2))
        #expect(ItemBitmapRenderer.titleRange(of: placed(title: "標題", important: false)) == nil)
        #expect(ItemBitmapRenderer.titleRange(of: placed(title: "", important: true)) == nil)
    }

    @Test func importantTitleIsDrawnInTheAccentColor() {
        // 重播＝黑底白字；重要標題為紅色，非重要時同一區域不含紅色像素。
        func redPixels(_ p: PlacedItem) -> Int {
            let img = r.render(p, scale: 2).first!
            let data = img.dataProvider!.data! as Data
            var n = 0
            let bpr = img.bytesPerRow
            for y in 0..<img.height { for x in 0..<img.width {
                let o = y * bpr + x * 4
                if data[o] > 150 && data[o + 1] < 90 && data[o + 2] < 90 { n += 1 }
            } }
            return n
        }
        #expect(redPixels(placed(title: "標題", important: true)) > 20)
        #expect(redPixels(placed(title: "標題", important: false)) == 0)
    }

    @Test func importantBodyAfterTheTitleIsNotRed() {
        // 回歸：標題之後的本文必須維持一般前景色（曾經因 CoreText 改掉 context 填色而整串變紅）。
        let p = placed(title: "標題", important: true)
        let img = r.render(PlacedItem(source: "j", id: "1", style: .replay, timeString: "12:34:56", text: String(repeating: "本文", count: 20),
                                      truncated: false, tapeX: 0, width: 600, seq: 1, listID: 1, listIndex: 1, title: "標題", important: true), scale: 2).first!
        _ = p
        let data = img.dataProvider!.data! as Data
        let bpr = img.bytesPerRow
        let startX = Int(r.boldMeasurer("12:34:56 標題", "12:34:56 標題".utf16.count) * 2) + 4   // 標題結束之後
        var red = 0, white = 0
        for y in 0..<img.height { for x in startX..<img.width {
            let o = y * bpr + x * 4
            if data[o] > 150 && data[o + 1] < 90 && data[o + 2] < 90 { red += 1 }
            if data[o] > 200 && data[o + 1] > 200 && data[o + 2] > 200 { white += 1 }
        } }
        #expect(red == 0, "標題之後出現紅色像素 \(red)")
        #expect(white > 50)
    }

    /// 離屏渲染（不是實機畫面）：`JIN10_SNAPSHOT_DIR=<目錄> swift test --filter TitleRenderTests` 輸出 PNG 供人目視。
    @Test func writeOffscreenSnapshotWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["JIN10_SNAPSHOT_DIR"] else { return }
        let rows: [(String, String, String, Bool, FastBullTickerCore.TickerStyle)] = [
            ("21:09:49", "卡塔尔斡旋人员赴德黑兰，协调推动地区局势降温", "金十数据10月25日讯，据一位了解相关情况的官员透露，卡塔尔调停人员周日抵达德黑兰", true, .replay),
            ("21:20:28", "", "利比亚锡尔特石油公司表示，布雷加天然气装置重启后，将向天然气系统输送6000万百万立方英尺天然气", false, .replay),
            ("21:44:43", "招商策略：A股多项指标已接近历史底部区间", "金十数据10月25日讯，招商策略研报认为，近期市场", false, .live),
            ("21:09:49", "卡塔尔斡旋人员赴德黑兰，协调推动地区局势降温", "金十数据10月25日讯，据一位了解相关情况的官员透露", true, .live),
        ]
        let scale: CGFloat = 2
        var imgs: [CGImage] = []
        for (i, row) in rows.enumerated() {
            let head = [row.0, row.1].filter { !$0.isEmpty }.joined(separator: " ")
            let w = r.boldMeasurer(head + " " + row.2, head.utf16.count)
            let p = PlacedItem(source: "jin10", id: "\(i)", style: row.4, timeString: row.0, text: row.2, truncated: false,
                               tapeX: 0, width: w, seq: i, listID: 1, listIndex: i + 1, title: row.1, important: row.3)
            imgs += r.render(p, scale: scale)
        }
        let W = imgs.map(\.width).max()!, H = imgs.map(\.height).reduce(0, +)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = H
        for im in imgs { y -= im.height; ctx.draw(im, in: CGRect(x: 0, y: y, width: im.width, height: im.height)) }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("jin10-title-offscreen.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}
