import Testing
import AppKit
import CoreText
import QuartzCore
@testable import FastBullTickerApp
import FastBullTickerCore

// ticker-style-settings 4.1：外觀套用。執行：
//   swift test --filter StyleApplyTests       （本檔全部 suite 名稱都以 StyleApply 或 DefaultStyle 開頭）
// 全程離屏：TickerView 不放進視窗、不開 NSPanel；沒有檔案、沒有網路。

// 測試目標同時 import App 與 Core，兩邊都有 `TickerStyle`；本檔的 `TickerStyle` 指 App 的樣式結構。
fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// MARK: 工具

func rgbBytes(_ img: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    guard let data = img.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return (-1, -1, -1) }
    let bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
    let o = y * bpr + x * bpp
    return (Int(ptr[o]), Int(ptr[o + 1]), Int(ptr[o + 2]))
}

func imageBytes(_ img: CGImage?) -> Data? {
    guard let img, let d = img.dataProvider?.data else { return nil }
    return d as Data
}

/// 統計 bitmap 中接近某色（每通道差 ≤ tol）的像素數。
func countPixels(_ img: CGImage, near c: (Int, Int, Int), tol: Int = 24) -> Int {
    guard let data = img.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return -1 }
    let bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
    var n = 0
    for y in 0..<img.height { for x in 0..<img.width {
        let o = y * bpr + x * bpp
        if abs(Int(ptr[o]) - c.0) <= tol, abs(Int(ptr[o + 1]) - c.1) <= tol, abs(Int(ptr[o + 2]) - c.2) <= tol { n += 1 }
    } }
    return n
}

func rgbComponents(_ c: CGColor?) -> [Double] { (c?.components ?? []).map(Double.init) }

@MainActor
final class StyleRig {
    let cfg = ShellConfig.provisional
    let clock: ManualClock
    let view: TickerView
    let driver: TickerDriver
    let applier: StyleApplier
    let log = AppLog(fileURL: nil, toStderr: false)
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let base: Int64 = 1_761_292_800_000

    init(style: FastBullTickerApp.TickerStyle = .default) {
        let clock = ManualClock()
        self.clock = clock
        view = TickerView(config: cfg)
        let sched = TickerScheduler(config: cfg.schedulerConfig(timeZone: Self.utc), clock: { clock.t }, measurer: view.itemMeasurer)
        driver = TickerDriver(scheduler: sched, renderer: view)
        applier = StyleApplier(config: cfg, view: view, driver: driver, log: log, timeZone: Self.utc)
        if style != .default { applier.apply(style, source: "test") }
    }

    func snapshot(_ n: Int = 12) {
        driver.receive(.snapshot((0..<n).map { i in
            Item(source: "t", id: "\(n - i)", publishedAtMs: Self.base - Int64(i) * 60_000, text: "快訊內容第 \(n - i) 則：美股盤前走勢")
        }))
    }
    func live(_ id: String, text: String = "即時：油價大漲") {
        driver.receive(.items([Item(source: "t", id: id, publishedAtMs: Self.base + 10_000, text: text)]))
    }
    func run(seconds: Double, step: Double = 0.25) {
        var t = 0.0
        while t < seconds { clock.t += step; driver.step(); t += step }
    }
    /// 跑到條件成立（最多 `max` 秒）；回傳是否成立。
    @discardableResult
    func run(until cond: () -> Bool, max: Double = 300, step: Double = 0.25) -> Bool {
        var t = 0.0
        while t < max, !cond() { clock.t += step; driver.step(); t += step }
        return cond()
    }
    /// 目前同時在畫面圖層上的即時樣式與重播樣式訊息 seq。
    var visibleLive: [Int] { placed.filter { $0.style == .live && view.layerSeqs.contains($0.seq) }.map(\.seq) }
    var visibleReplay: [Int] { placed.filter { $0.style == .replay && view.layerSeqs.contains($0.seq) }.map(\.seq) }
    var placed: [PlacedItem] { driver.scheduler.placed }
}

// MARK: 預設樣式 = 原型（取代原本讀 ShellConfig／grep TickerView.swift 的過渡性斷言）

@MainActor
@Suite struct DefaultStyleRendersLikePrototypeTests {
    // 原型常數（app-shell 的 ShellConfig.provisional／TickerView／ItemBitmapRenderer 的字面值）。
    static let prototypeFontSize: CGFloat = 16
    static let prototypeSpeed = 90.0
    static let prototypeLabel = "即時財經快訊"
    static let prototypeTape = [0.09, 0.09, 0.10]
    static let prototypeLabelRed = [0.85, 0.10, 0.13]

    private func close(_ a: [Double], _ b: [Double]) -> Bool {
        a.count >= 3 && zip(a.prefix(3), b).allSatisfy { abs($0 - $1) <= 1.0 / 255 + 1e-9 }
    }

    @Test func fontSizeIsPrototype16WithBoldTime() {
        let r = ItemBitmapRenderer(style: .default, config: .provisional)
        #expect(r.fontSize == Self.prototypeFontSize)
        let s = r.attributedString("12:34:56 美股盤前")
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let f0 = s.attribute(key, at: 0, effectiveRange: nil) as! CTFont, f9 = s.attribute(key, at: 9, effectiveRange: nil) as! CTFont
        #expect(CTFontGetSize(f0) == 16 && CTFontGetSize(f9) == 16)
        #expect(CTFontCopyPostScriptName(f0) as String == ItemBitmapRenderer.boldFontName)
        #expect(CTFontCopyPostScriptName(f9) as String == ItemBitmapRenderer.fontName)
    }

    @Test func measuredWidthEqualsThePrototypeFormula() {
        // 原型公式：CTLine 的排版寬度向上取整 + 2×留白；前 8 字元（開頭的 HH:mm:ss）用 Semibold，其餘 Regular。
        let cfg = ShellConfig.provisional
        let reg = CTFontCreateWithName("PingFangTC-Regular" as CFString, 16, nil), bold = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 16, nil)
        func proto(_ s: String) -> Double {
            let a = NSMutableAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): reg])
            if s.utf8.count >= 8, ItemText.boldPrefixLength(of: s) == 8 { a.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: bold, range: NSRange(location: 0, length: 8)) }
            return Double(CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(a), nil, nil, nil)).rounded(.up) + 2 * cfg.itemPadding)
        }
        let m = ItemBitmapRenderer(style: .default, config: cfg).measurer
        for s in ["12:34:56 美股盤前", "08:00:01 Fed 官員表示仍需觀察通膨數據", "23:59:59 …"] { #expect(m(s) == proto(s), "\(s)") }
    }

    @Test func schedulerSpeedIsPrototype90AndActuallyScrolls90PerSecond() {
        #expect(ShellConfig.provisional.schedulerConfig(style: .default).speed == Self.prototypeSpeed)
        let rig = StyleRig()
        rig.snapshot(); rig.driver.step()
        let a = rig.driver.scheduler.scrollOffset
        rig.clock.t += 2; rig.driver.step()
        #expect(abs(rig.driver.scheduler.scrollOffset - a - 180) < 1e-9)
        #expect(rig.driver.scheduler.config.replayCount == 10 && rig.driver.scheduler.config.showTime)
    }

    @Test func viewLayersMatchPrototypeConstants() {
        let l = TickerView(config: .provisional).layoutSnapshot
        #expect(l.labelString == Self.prototypeLabel && !l.labelHidden)
        #expect(close(rgbComponents(l.tapeColor), Self.prototypeTape), "空隙底色 \(rgbComponents(l.tapeColor))")
        #expect(close(rgbComponents(l.labelFill), Self.prototypeLabelRed), "標籤紅 \(rgbComponents(l.labelFill))")
        #expect(rgbComponents(l.labelTextColor).prefix(3).allSatisfy { $0 == 1 })
        #expect(l.cornerRadius == 0)
        #expect(Double(l.clipFrame.maxX) == 620 && Double(l.clipFrame.minX) == 150 + 100, "帶子可視區在標籤與控制列之後（nav-layout-tweaks）")
        #expect(l.scrollOriginX == 0)
        // 色彩空間也與原型相同（Generic RGB），否則顯示出來的紅色不一樣
        let space = TickerView(config: .provisional).layoutSnapshot.labelFill?.colorSpace?.name as String?
        #expect(space == CGColor(red: 0, green: 0, blue: 0, alpha: 1).colorSpace?.name as String?)
    }

    @Test func liveIsWhiteOnBlackTextAndReplayIsBlackOnWhiteTextPixels() throws {
        let rig = StyleRig()
        rig.snapshot(); rig.driver.step(); rig.live("900")
        #expect(rig.run(until: { !rig.visibleLive.isEmpty }), "跑到有即時訊息")
        let replayItem = try #require(rig.placed.first { $0.style == .replay })
        let liveItem = try #require(rig.placed.first { $0.style == .live })
        let r = ItemBitmapRenderer(style: .default, config: rig.cfg)
        let rep = try #require(r.render(replayItem, scale: 2).first), liv = try #require(r.render(liveItem, scale: 2).first)
        #expect(rgbBytes(rep, x: 1, y: 1) == (0, 0, 0) && rgbBytes(liv, x: 1, y: 1) == (255, 255, 255), "背景：重播黑、即時白")
        #expect(countPixels(rep, near: (255, 255, 255), tol: 10) > 50, "重播：白色文字像素")
        #expect(countPixels(liv, near: (0, 0, 0), tol: 10) > 50, "即時：黑色文字像素")
        #expect(rig.view.layerCount > 0)
    }
}

// MARK: 時間粗體：明確資訊，不偵測

@MainActor
@Suite struct StyleApplyBoldTimeTests {
    private func fontNames(_ s: NSAttributedString) -> [String] {
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        return (0..<s.length).map { CTFontCopyPostScriptName(s.attribute(key, at: $0, effectiveRange: nil) as! CTFont) as String }
    }
    private func item(time: String, text: String) -> PlacedItem {
        PlacedItem(source: "t", id: "1", style: .replay, timeString: time, text: text, truncated: false, tapeX: 0, width: 300, seq: 1, listID: 1, listIndex: 1)
    }

    @Test func showTimeFalseBodyThatLooksLikeATimeIsNeverBold() {
        let off = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384, showTime: false)
        let body = "12:34:56 開盤前瞻"
        // 量測端：showTime=false 時不偵測
        #expect(Set(fontNames(off.attributedString(body))) == [ItemBitmapRenderer.fontName])
        // 繪製端：timeString 為空 → 顯示字串就是 text、粗體長度 0
        let parts = ItemBitmapRenderer.displayParts(of: item(time: "", text: body))
        #expect(parts.text == body && parts.boldLength == 0)
        #expect(Set(fontNames(off.attributedString(parts.text, boldLength: parts.boldLength))) == [ItemBitmapRenderer.fontName])
        // 對照：showTime=true 的同一字串開頭 8 字元是粗體
        let on = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384, showTime: true)
        #expect(Array(fontNames(on.attributedString(body)).prefix(8)) == Array(repeating: ItemBitmapRenderer.boldFontName, count: 8))
    }

    @Test func showTimeTrueUsesTimeStringLengthAndJoinsWithOneSpace() {
        let parts = ItemBitmapRenderer.displayParts(of: item(time: "09:05:03", text: "12:34:56 內文也像時間"))
        #expect(parts.text == "09:05:03 12:34:56 內文也像時間" && parts.boldLength == 8, "只有真正的時間欄位粗體，內文的 12:34:56 不粗體")
    }

    @Test func endToEndSchedulerWithShowTimeFalseDrawsNoLeadingSpaceAndNoBold() throws {
        let rig = StyleRig()
        var s = TickerStyle.default; s.showTime = false
        rig.applier.apply(s, source: "test")
        rig.driver.receive(.snapshot([Item(source: "t", id: "1", publishedAtMs: StyleRig.base, text: "12:34:56 開盤前瞻")]))
        rig.driver.step()
        let p = try #require(rig.placed.first)
        #expect(p.timeString.isEmpty && p.text == "12:34:56 開盤前瞻")
        let m = ItemBitmapRenderer(style: s, config: rig.cfg).measurer
        #expect(p.width == m("12:34:56 開盤前瞻"), "寬度以不含時間的顯示字串量測")
        #expect(rig.view.layerCount == 1)
    }
}

// MARK: 套用語意

@MainActor
@Suite struct StyleApplyViewTests {
    @Test func colorChangeKeepsPositionsAndRedrawsBitmapsInPlace() throws {
        let rig = StyleRig()
        rig.snapshot(); rig.driver.step(); rig.live("900")
        #expect(rig.run(until: { !rig.visibleLive.isEmpty && !rig.visibleReplay.isEmpty }), "畫面上同時有即時與重播訊息")
        let seqs = rig.view.layerSeqs
        let liveSeq = try #require(rig.visibleLive.first), repSeq = try #require(rig.visibleReplay.first)
        let xsBefore = seqs.map { rig.view.layerTapeX(seq: $0) }
        let liveBefore = try #require(rig.view.firstTile(seq: liveSeq)), repBefore = try #require(rig.view.firstTile(seq: repSeq))
        #expect(rgbBytes(liveBefore, x: 1, y: 1) == (255, 255, 255))
        let wBefore = rig.placed.map(\.width)

        var s = TickerStyle.default
        s.liveBackground = RGBColor(hex: "#FFE45C")!
        #expect(rig.applier.apply(s, source: "test"))

        #expect(seqs.map { rig.view.layerTapeX(seq: $0) } == xsBefore, "位置不變")
        #expect(rig.placed.map(\.width) == wBefore, "寬度不變")
        let liveAfter = try #require(rig.view.firstTile(seq: liveSeq)), repAfter = try #require(rig.view.firstTile(seq: repSeq))
        // 色碼以 Generic RGB 解讀（與原型一致）；bitmap 是 sRGB context，所以位元組是轉換後的值，顯示出來與同色碼的標籤一致。
        let expected = RGBColor(hex: "#FFE45C")!.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!
        let e = (expected.components ?? []).prefix(3).map { Int(($0 * 255).rounded()) }
        let got = rgbBytes(liveAfter, x: 1, y: 1)
        #expect([got.r, got.g, got.b] == e && e != [0xFF, 0xE4, 0x5C], "即時訊息背景重繪為新色（\(e)）")
        #expect(liveAfter.width == liveBefore.width && liveAfter.height == liveBefore.height)
        #expect(imageBytes(repAfter) == imageBytes(repBefore), "重播樣式的 bitmap 內容不變")
        #expect(rig.applier.lastReport?.redrawnItems == seqs.count && rig.view.redrawCount == seqs.count)
        #expect(rig.log.recorded.contains { $0.contains("redrew=\(seqs.count)") && $0.contains("changed=[liveBackground]") })
        #expect(rig.view.containerCount == rig.view.layerCount, "沒有孤兒圖層")
    }

    @Test func nonColorChangeDoesNotRedrawAnything() {
        let rig = StyleRig()
        rig.snapshot(); rig.run(seconds: 3)
        var s = TickerStyle.default; s.scrollSpeed = 150; s.cornerRadius = 8; s.labelText = "快訊"
        rig.applier.apply(s, source: "test")
        #expect(rig.view.redrawCount == 0 && rig.applier.lastReport?.redrawnItems == 0)
    }

    @Test func fontSizeOnlyAffectsItemsPlacedAfterTheChange() throws {
        let rig = StyleRig()
        rig.snapshot(); rig.run(seconds: 2)
        let old = rig.placed
        let oldSeqs = Set(rig.view.layerSeqs)
        let oldTiles = Dictionary(uniqueKeysWithValues: oldSeqs.compactMap { s in imageBytes(rig.view.firstTile(seq: s)).map { (s, $0) } })
        var s = TickerStyle.default; s.fontSize = 20
        rig.applier.apply(s, source: "test")
        #expect(rig.placed == old, "已排入訊息（含寬度）完全不變")
        for q in oldSeqs { #expect(imageBytes(rig.view.firstTile(seq: q)) == oldTiles[q], "舊訊息沿用舊字級的 bitmap") }

        rig.run(seconds: 6)
        let fresh = rig.placed.filter { p in !old.contains { $0.seq == p.seq } }
        let p = try #require(fresh.first)
        let m20 = ItemBitmapRenderer(fontSize: 20, padding: rig.cfg.itemPadding, heightPt: 42, textureLimitPx: 16_384).measurer
        #expect(p.width == m20(p.timeString + " " + p.text), "之後排入的訊息以 20pt 量測")
        // 與前一則的間距仍為 gap
        let prev = try #require(rig.placed.last { $0.seq == p.seq - 1 })
        #expect(abs(p.tapeX - (prev.tapeX + prev.width) - rig.driver.scheduler.config.gap) < 1e-9)
    }

    @Test func colorChangeAfterFontChangeStillUsesTheOldFontForOldItems() throws {
        let rig = StyleRig()
        rig.snapshot(); rig.run(seconds: 2)
        let oldSeq = try #require(rig.view.layerSeqs.first)
        let oldItem = try #require(rig.placed.first { $0.seq == oldSeq })
        var s = TickerStyle.default; s.fontSize = 24
        rig.applier.apply(s, source: "test")
        s.replayBackground = RGBColor(hex: "#102030")!
        rig.applier.apply(s, source: "test")
        var colors16 = ItemColors(style: s)
        colors16.liveBackground = s.liveBackground
        let expected = ItemBitmapRenderer(fontSize: 16, padding: rig.cfg.itemPadding, heightPt: 42, textureLimitPx: rig.cfg.textureLimitPx,
                                          linkSlotWidth: CGFloat(rig.cfg.linkSlotWidth), colors: colors16).render(oldItem, scale: rig.view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        #expect(imageBytes(rig.view.firstTile(seq: oldSeq)) == imageBytes(expected.first), "舊訊息重繪時仍用 16pt（寬度是以 16pt 量測的）")
    }

    @Test func prunedItemReaddedAfterFontChangeIsRebuiltWithItsOriginalFont() throws {
        let v = TickerView(config: .provisional)
        let item = PlacedItem(source: "t", id: "1", style: .replay, timeString: "12:34:56", text: "舊訊息", truncated: false,
                              tapeX: 400, width: 200, seq: 1, listID: 1, listIndex: 1)
        v.add(item)
        let first = imageBytes(v.firstTile(seq: 1))
        v.setScrollOffset(10_000)                       // 捲出左緣 → 被清除
        #expect(v.layerCount == 0)
        var s = TickerStyle.default; s.fontSize = 24
        v.apply(style: s)
        v.setScrollOffset(0)
        v.add(item)                                      // 向後 seek 重建
        #expect(imageBytes(v.firstTile(seq: 1)) == first, "重建的圖層與原本（16pt）相同，不是 24pt")
    }

    @Test func cornerRadiusIsClampedToHalfPanelHeightAndMasksAllLayers() {
        let v = TickerView(config: .provisional)
        var s = TickerStyle.default; s.cornerRadius = 10
        v.apply(style: s)
        #expect(v.layoutSnapshot.cornerRadius == 10 && v.layoutSnapshot.masksToBounds)
        s.cornerRadius = 100                              // 未經 clamp 的樣式也不得超過 21
        v.apply(style: s)
        #expect(v.layoutSnapshot.cornerRadius == 21)
        s.cornerRadius = 0
        v.apply(style: s)
        #expect(v.layoutSnapshot.cornerRadius == 0)
    }

    @Test func cornerRadiusDoesNotChangeHitAreaOrPanelFrame() {
        let v = TickerView(config: .provisional)
        let g = v.router.geometry
        var s = TickerStyle.default; s.cornerRadius = 21
        v.apply(style: s)
        #expect(v.router.geometry == g && v.frame.size == ShellConfig.provisional.panelSize)
    }

    @Test func hidingTheLabelWidensViewportAndKeepsTapePositions() throws {
        let rig = StyleRig()
        rig.snapshot(); rig.run(seconds: 3)
        let seqs = rig.view.layerSeqs
        let xs = seqs.map { rig.view.layerTapeX(seq: $0) }
        #expect(rig.driver.scheduler.config.viewportWidth == 370)
        var s = TickerStyle.default; s.showLabel = false
        rig.applier.apply(s, source: "test")
        let l = rig.view.layoutSnapshot
        #expect(l.labelHidden)
        #expect(Double(l.clipFrame.minX) == 100 && Double(l.clipFrame.maxX) == 620, "標籤隱藏：控制列貼面板左緣，帶子從控制列右緣（x=100）顯示到面板右緣")
        #expect(l.scrollOriginX + rig.driver.scheduler.scrollOffset == 0, "捲動圖層原點在可視區左緣（位置＝原點 − 位移）")
        #expect(rig.driver.scheduler.config.viewportWidth == 520, "可視寬度增加標籤寬 150")
        #expect(rig.view.router.geometry.labelWidth == 0)
        #expect(seqs.map { rig.view.layerTapeX(seq: $0) } == xs, "已排入訊息的 tapeX 不變")
        #expect(Double(l.stripFrame.minX) == 0 && Double(l.stripFrame.maxX) == 100, "控制列貼面板左緣")
        #expect(Double(l.previousFrame.minX) == 0 && Double(l.nextFrame.maxX) == 100)
        s.showLabel = true
        rig.applier.apply(s, source: "test")
        #expect(!rig.view.layoutSnapshot.labelHidden && rig.driver.scheduler.config.viewportWidth == 370 && rig.view.router.geometry.labelWidth == 150)
        #expect(Double(rig.view.layoutSnapshot.previousFrame.minX) == 150 && Double(rig.view.layoutSnapshot.clipFrame.minX) == 250, "標籤回來：控制列回到標籤右側")
    }

    @Test func labelTextAndColorsApplyImmediately() {
        let v = TickerView(config: .provisional)
        var s = TickerStyle.default
        s.labelText = "快訊"; s.labelBackground = RGBColor(hex: "#112233")!; s.labelColor = RGBColor(hex: "#FFE45C")!; s.tapeBackground = RGBColor(hex: "#445566")!
        v.apply(style: s)
        let l = v.layoutSnapshot
        #expect(l.labelString == "快訊")
        #expect(rgbComponents(l.labelFill).prefix(3).map { Int(($0 * 255).rounded()) } == [0x11, 0x22, 0x33])
        #expect(rgbComponents(l.labelTextColor).prefix(3).map { Int(($0 * 255).rounded()) } == [0xFF, 0xE4, 0x5C])
        #expect(rgbComponents(l.tapeColor).prefix(3).map { Int(($0 * 255).rounded()) } == [0x44, 0x55, 0x66])
        #expect(v.redrawCount == 0, "標籤與空隙色不需要重繪訊息")
    }

    @Test func applyingTheSameStyleTwiceIsANoOp() {
        let rig = StyleRig()
        var s = TickerStyle.default; s.scrollSpeed = 120
        #expect(rig.applier.apply(s, source: "a") && rig.applier.applyCount == 1)
        #expect(!rig.applier.apply(s, source: "b") && rig.applier.applyCount == 1)
        #expect(rig.log.recorded.filter { $0.hasPrefix("style: applied") }.count == 1)
    }
}

// MARK: 套用到排程器（Core reconfigure）

@MainActor
@Suite struct StyleApplySchedulerTests {
    @Test func speedChangeKeepsVisualPositionsThenAdvancesAtNewSpeed() {
        let rig = StyleRig()
        rig.snapshot(); rig.run(seconds: 3)
        let off = rig.driver.scheduler.scrollOffset
        let visual = rig.placed.map { $0.tapeX - off }
        var s = TickerStyle.default; s.scrollSpeed = 150
        rig.applier.apply(s, source: "test")
        #expect(abs(rig.driver.scheduler.scrollOffset - off) < 1e-9)
        #expect(zip(rig.placed, visual).allSatisfy { abs(($0.tapeX - rig.driver.scheduler.scrollOffset) - $1) < 1e-9 })
        rig.clock.t += 1; rig.driver.step()
        #expect(abs(rig.driver.scheduler.scrollOffset - off - 150) < 1e-9)
    }

    @Test func replayCountAndShowTimeReachTheScheduler() throws {
        let rig = StyleRig()
        rig.snapshot(); rig.driver.step()
        var s = TickerStyle.default; s.replayCount = 5; s.showTime = false
        rig.applier.apply(s, source: "test")
        #expect(rig.driver.scheduler.config.replayCount == 5 && !rig.driver.scheduler.config.showTime)
        #expect(rig.driver.scheduler.latestItems.count == 5)
        rig.run(seconds: 60)
        let last = try #require(rig.placed.last)
        #expect(last.timeString.isEmpty, "showTime 改為 false 之後排入的訊息不含時間")
    }

    @Test func shellConfigBuildsTheSchedulerConfigFromTheStyle() {
        var s = TickerStyle.default
        s.scrollSpeed = 150; s.replayCount = 5; s.showTime = false; s.showLabel = false
        let c = ShellConfig.provisional.schedulerConfig(style: s, timeZone: StyleRig.utc)
        #expect(c.speed == 150 && c.replayCount == 5 && !c.showTime && c.viewportWidth == 520 && c.maxItemWidth == 600)
        let d = ShellConfig.provisional.schedulerConfig(style: .default, timeZone: StyleRig.utc)
        #expect(d.speed == 90 && d.replayCount == 10 && d.showTime && d.viewportWidth == 370)
    }

    @Test func nothingIsRebuiltOnApply() {
        let rig = StyleRig()
        rig.snapshot(); rig.run(seconds: 3)
        let before = rig.placed
        var s = TickerStyle.default; s.fontSize = 22; s.cornerRadius = 5; s.liveText = RGBColor(hex: "#111111")!
        rig.applier.apply(s, source: "test")
        #expect(rig.placed == before && rig.driver.scheduler.mode == .replay)
    }
}
