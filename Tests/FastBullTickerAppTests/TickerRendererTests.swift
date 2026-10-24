import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import FastBullTickerApp
import FastBullTickerCore

// task 4.1：TickerRenderer／TickerDriver。執行：swift test --filter TickerRenderer

final class ManualClock { var t: Double = 100 }

/// 測試替身：記錄呼叫序列，並用 TrackModel 維護座標（與真 renderer 同一套邏輯）。
@MainActor
final class RecordingRenderer: TickerRenderer {
    enum Call: Equatable { case add(String), offset(Double), rebase(Double), paused(Bool) }
    var calls: [Call] = []
    var controlStates: [ControlStripState] = []
    var duplicateAdds = 0
    var track = TrackModel()
    var offset = 0.0
    var paused = false
    func add(_ item: PlacedItem) {
        // 與 TickerView 同一套冪等邏輯：同一 seq 已在帶子上就略過。
        if track.add(seq: item.seq, tapeX: item.tapeX, width: item.width) { calls.append(.add(item.id)) } else { duplicateAdds += 1 }
    }
    func setControlStrip(_ state: ControlStripState) { controlStates.append(state) }
    func setScrollOffset(_ o: Double) { calls.append(.offset(o)); offset = o; _ = track.prune(offset: o) }
    func applyRebase(delta: Double) { calls.append(.rebase(delta)); track.rebase(delta: delta) }
    func setPaused(_ p: Bool) { calls.append(.paused(p)); paused = p }
    var visuals: [Double] { track.entries.map { $0.tapeX - offset } }
}

@MainActor
func makeDriver(clock: ManualClock, rebaseThreshold: Double = 500_000) -> (TickerDriver, RecordingRenderer) {
    var cfg = SchedulerConfig()
    cfg.speed = 60; cfg.gap = 48; cfg.viewportWidth = 470; cfg.maxItemWidth = 600
    cfg.timeZone = TimeZone(secondsFromGMT: 0)!
    cfg.rebaseThreshold = rebaseThreshold
    let sched = TickerScheduler(config: cfg, clock: { clock.t }, measurer: { Double($0.count) * 10 })
    let r = RecordingRenderer()
    return (TickerDriver(scheduler: sched, renderer: r), r)
}

func sampleItems(_ n: Int, base: Int64 = 1_761_292_800_000) -> [Item] {
    (0..<n).map { Item(source: "t", id: "\(n - $0)", publishedAtMs: base + Int64(n - $0) * 1000, text: "訊息\(n - $0)") }
}

@Suite struct TilingTests {
    @Test func tileWidthsSumToTotalAndNeverExceedLimit() {
        for total in [1, 16_383, 16_384, 16_385, 50_000, 100_001] {
            let w = Tiling.tileWidths(totalPx: total, limit: 16_384)
            #expect(w.reduce(0, +) == total)
            #expect(w.allSatisfy { $0 <= 16_384 && $0 > 0 })
        }
        #expect(Tiling.tileWidths(totalPx: 0, limit: 10).isEmpty)
    }

    @Test func bitmapRendererProducesTilesWhoseWidthsEqualPlan() throws {
        // 以很小的紋理上限強迫切塊，驗證實際 CGImage 寬度總和＝ceil(width×scale)。
        let r = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 300)
        let long = String(repeating: "財經快訊", count: 40)
        let measurer = r.measurer
        var cfg = SchedulerConfig(); cfg.maxItemWidth = 5000; cfg.viewportWidth = 470; cfg.timeZone = TimeZone(secondsFromGMT: 0)!
        var sched = TickerScheduler(config: cfg, clock: { 0 }, measurer: measurer)
        _ = sched.receive(.snapshot([Item(source: "t", id: "1", publishedAtMs: 0, text: long)]))
        let placed = try #require(sched.tick().first)
        let layout = (width: placed.width, _: 0)
        let tiles = r.render(placed, scale: 2)
        #expect(tiles.count > 1)
        #expect(tiles.map(\.width).reduce(0, +) == Int((layout.width * 2).rounded(.up)))
        #expect(tiles.allSatisfy { $0.width <= 300 })
        #expect(tiles.map(\.width) == r.tilePlan(width: layout.width, scale: 2))
    }
}

@Suite struct TrackModelTests {
    @Test func rebasePreservesVisualPositionsAndPrunesScrolledOut() {
        var m = TrackModel()
        let a = 1, b = 2
        let addedA = m.add(seq: a, tapeX: 1_000_000, width: 300), addedB = m.add(seq: b, tapeX: 1_000_348, width: 300)
        #expect(addedA && addedB)
        let offset = 1_000_100.0
        let before = (m.visualX(seq: a, offset: offset)!, m.visualX(seq: b, offset: offset)!)
        m.rebase(delta: offset)
        let after = (m.visualX(seq: a, offset: 0)!, m.visualX(seq: b, offset: 0)!)
        #expect(abs(before.0 - after.0) < 0.5 && abs(before.1 - after.1) < 0.5)
        #expect(m.prune(offset: 250, margin: 0) == [a])           // rebase 後 a 右緣 = −100+300 = 200 < 250；b 右緣 548
        #expect(m.entries.map(\.seq) == [b])
    }
}

@MainActor
@Suite struct TickerDriverTests {
    @Test func stepFeedsRendererInOrderAndSetsOffset() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(3)))
        d.step()
        #expect(r.calls.first == .add("3"))                    // 重播從最新一則開始
        #expect(r.calls.last == .offset(0))
        clock.t += 2
        d.step()
        #expect(r.calls.last == .offset(120))                  // 60px/s × 2s
        #expect(d.itemsPlaced >= 1)
    }

    @Test func hiddenFreezesAndResumesWithoutJump() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(5)))
        d.step()
        clock.t += 3; d.step()
        let before = r.offset, visualsBefore = r.visuals
        #expect(before == 180)
        d.setUserHidden(true)
        #expect(r.paused)
        clock.t += 10; d.step()
        #expect(r.offset == before)                            // 隱藏 10 秒，位移不動
        d.setUserHidden(false)
        #expect(!r.paused)
        d.step()
        #expect(r.offset == before)                            // 剛恢復：不瞬移
        #expect(r.visuals == visualsBefore)
        clock.t += 1; d.step()
        #expect(r.offset == before + 60)
    }

    @Test func occlusionAndUserHiddenAreCombined() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.setOccluded(true); d.setUserHidden(true)
        d.setOccluded(false)
        #expect(d.isFrozen && r.paused)                        // 使用者仍隱藏：不因遮蔽解除而恢復
        d.setUserHidden(false)
        #expect(!d.isFrozen && !r.paused)
    }

    @Test func rebaseKeepsEveryScreenPositionUnchanged() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock, rebaseThreshold: 1_000)
        d.receive(.snapshot(sampleItems(10)))
        d.step()
        for _ in 0..<15 { clock.t += 1; d.step() }              // offset 900，尚未 rebase
        #expect(d.rebaseCount == 0)
        clock.t += 2                                           // 下一次 step 會跨過 1000
        var probe = d.scheduler                                // 值型別複本：預演「不 rebase」的視覺位置
        _ = probe.tick()
        let expected = probe.placed.map { probe.visualX(of: $0) }
        d.step()
        #expect(d.rebaseCount == 1)
        #expect(r.offset == 0)
        #expect(r.calls.contains { if case .rebase(let x) = $0 { return abs(x - 1_020) < 1e-9 } else { return false } })
        // renderer 內仍存在的訊息，其視覺位置必須與 rebase 前相同（容差 < 0.5px）
        let after = r.visuals
        #expect(!after.isEmpty)
        for v in after { #expect(expected.contains { abs($0 - v) < 0.5 }) }
    }

    @Test func prunesScrolledOutLayersSoMemoryDoesNotGrow() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(10)))
        for _ in 0..<600 { clock.t += 1; d.step() }            // 10 分鐘
        #expect(d.itemsPlaced > 30)
        #expect(r.track.entries.count < 12)
    }
}

@MainActor
@Suite struct DemoCadenceTests {
    /// 示範 helper 的節奏：每 8 秒一則新訊息。用真實字型量測寬度與 `ShellConfig.provisional` 的速度，
    /// 驗證佇列會播完而回到重播（否則使用者永遠看不到「重播→即時→重播」）。
    @Test func eightSecondCadenceCyclesReplayLiveReplayRepeatedly() {
        let cfg = ShellConfig.provisional
        let bitmap = ItemBitmapRenderer(style: .default, config: cfg)
        let clock = ManualClock()
        let sched = TickerScheduler(config: cfg.schedulerConfig(timeZone: TimeZone(secondsFromGMT: 0)!), clock: { clock.t }, measurer: bitmap.measurer)
        let r = RecordingRenderer()
        let d = TickerDriver(scheduler: sched, renderer: r)
        let texts = ["Fed 官員表示仍需觀察通膨數據，不排除年內再度降息", "黃金突破 4,000 美元/盎司，創歷史新高", "美國 10 年期公債殖利率降至 4.05%",
                     "最新快訊 #1：WTI 原油上漲 1.2%，報每桶 78.4 美元", "比特幣站上 11 萬美元，24 小時內上漲 3.5%"]
        d.receive(.snapshot((0..<12).map { Item(source: "demo", id: "\(9000 - $0)", publishedAtMs: 1_761_292_800_000 - Int64($0) * 180_000, text: texts[$0 % texts.count]) }))
        var modes: [TickerMode] = [d.mode]
        for second in 1...240 {
            clock.t += 1
            if second % 8 == 0 {
                d.receive(.items([Item(source: "demo", id: "\(9100 + second)", publishedAtMs: 1_761_292_800_000 + Int64(second) * 1000, text: texts[second % texts.count])]))
            }
            d.step()
            if modes.last != d.mode { modes.append(d.mode) }
        }
        let liveToReplay = zip(modes, modes.dropFirst()).filter { $0 == .live && $1 == .replay }.count
        #expect(liveToReplay >= 3, "modes=\(modes)")
        #expect(modes.first == .replay)
    }
}


// MARK: N3（task 7.1）：粗體時間、迴紋針、add 冪等、向後 seek 重建圖層、控制列版面

@Suite struct TickerRendererBoldTimeTests {
    private let r = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384, linkSlotWidth: 26)

    private func psName(_ s: NSAttributedString, at i: Int) -> String? {
        guard let f = s.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: i, effectiveRange: nil) else { return nil }
        return CTFontCopyPostScriptName(f as! CTFont) as String
    }

    @Test func boldPrefixIsExactlyTheTimeAndSpaceAware() {
        #expect(ItemText.boldPrefixLength(of: "12:34:56 美股盤前") == 8)
        #expect(ItemText.boldPrefixLength(of: "00:00:00 ") == 8)
        #expect(ItemText.boldPrefixLength(of: "美股盤前 12:34:56") == 0, "只有開頭的時間粗體")
        #expect(ItemText.boldPrefixLength(of: "1:34:56 x") == 0)
        #expect(ItemText.boldPrefixLength(of: "12-34-56 x") == 0)
        #expect(ItemText.boldPrefixLength(of: "12:34") == 0)
        #expect(ItemText.boldPrefixLength(of: "") == 0)
    }

    @Test func timeRunIsBoldAndRestIsRegular() {
        let s = r.attributedString("12:34:56 美股盤前：道指期貨")
        for i in 0..<8 { #expect(psName(s, at: i) == ItemBitmapRenderer.boldFontName, "index \(i)") }
        for i in 8..<s.length { #expect(psName(s, at: i) == ItemBitmapRenderer.fontName, "index \(i)") }
        #expect(ItemBitmapRenderer.boldFontName != ItemBitmapRenderer.fontName)
    }

    @Test func measurerUsesTheSameAttributedStringAsDrawing() {
        // 粗體時間比一般字重寬或等寬，但量測值必須等於以同一建構函式算出的寬度。
        let s = "12:34:56 abc"
        let direct = Double(CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(r.attributedString(s)), nil, nil, nil)).rounded(.up) + 28)
        #expect(r.measurer(s) == direct)
    }
}

@Suite struct TickerRendererLinkSlotTests {
    private let scale: CGFloat = 2
    private func item(url: String?, slot: Bool, style: FastBullTickerCore.TickerStyle = .replay, width: Double = 0) -> PlacedItem {
        PlacedItem(source: "t", id: "1", style: style, timeString: "12:34:56", text: "美股盤前", truncated: false,
                   tapeX: 0, width: width, url: url, seq: 1, listID: 1, listIndex: 1, hasLinkSlot: slot)
    }
    /// 取 bitmap 中某欄範圍內「前景色（亮於 128）」的像素數（replay 為黑底白字）。
    private func foregroundCount(_ images: [CGImage], px: Range<Int>) -> Int {
        guard let img = images.first, let data = img.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return -1 }
        let bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
        var n = 0
        for y in 0..<img.height { for x in px where x < img.width && ptr[y * bpr + x * bpp] > 128 { n += 1 } }
        return n
    }

    @Test func paperclipIsDrawnInLinkSlotOnlyWhenItemHasLink() {
        let r = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384, linkSlotWidth: 26)
        let textW = r.measurer("12:34:56 美股盤前")
        let w = textW + 26
        let slotPx = Int((CGFloat(w - 26) * scale).rounded(.up))..<Int((CGFloat(w) * scale).rounded(.up))
        let with = r.render(item(url: "https://example.com/demo/1", slot: true, width: w), scale: scale)
        let without = r.render(item(url: nil, slot: false, width: textW), scale: scale)
        #expect(foregroundCount(with, px: slotPx) > 20, "欄位內有迴紋針的前景像素")
        #expect(foregroundCount(without, px: slotPx) == 0, "無連結：該範圍沒有任何前景像素（本來就沒有欄位）")
        let sumWith = with.map(\.width).reduce(0, +), sumWithout = without.map(\.width).reduce(0, +)
        #expect(sumWith == Int((CGFloat(w) * scale).rounded(.up)))
        #expect(sumWithout == Int((CGFloat(textW) * scale).rounded(.up)))
    }

    @Test func paperclipColorFollowsStyle() {
        let r = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384, linkSlotWidth: 26)
        let w = r.measurer("12:34:56 美股盤前") + 26
        // live＝白底黑字：迴紋針是暗色，欄位內「亮於 128」的像素佔絕大多數（背景），replay 則相反。
        let slotPx = Int((CGFloat(w - 26) * scale).rounded(.up))..<Int((CGFloat(w) * scale).rounded(.up))
        let live = r.render(item(url: "https://example.com/demo/1", slot: true, style: .live, width: w), scale: scale)
        let replay = r.render(item(url: "https://example.com/demo/1", slot: true, style: .replay, width: w), scale: scale)
        let total = slotPx.count * live[0].height
        #expect(foregroundCount(live, px: slotPx) > total * 8 / 10)
        #expect(foregroundCount(replay, px: slotPx) < total * 2 / 10)
    }

    @Test func schedulerWidthWithSlotEqualsMeasurerPlusSlotAndMatchesBitmap() throws {
        let r = ItemBitmapRenderer(fontSize: 16, padding: 14, heightPt: 42, textureLimitPx: 16_384, linkSlotWidth: 26)
        var cfg = ShellConfig.provisional.schedulerConfig(timeZone: TimeZone(secondsFromGMT: 0)!)
        cfg.linkSlotWidth = 26
        var sched = TickerScheduler(config: cfg, clock: { 0 }, measurer: r.measurer)
        _ = sched.receive(.snapshot([Item(source: "t", id: "1", publishedAtMs: 0, text: "測試訊息", url: "https://example.com/demo/1")]))
        let p = try #require(sched.tick().first)
        #expect(p.hasLinkSlot)
        #expect(p.width == r.measurer(p.timeString + " " + p.text) + 26)
        let tiles = r.render(p, scale: scale)
        #expect(tiles.map(\.width).reduce(0, +) == Int((CGFloat(p.width) * scale).rounded(.up)))
    }
}

@MainActor
@Suite struct TickerRendererIdempotencyTests {
    @Test func trackModelAddIsIdempotentPerSeq() {
        var m = TrackModel()
        let first = m.add(seq: 5, tapeX: 100, width: 50), second = m.add(seq: 5, tapeX: 999, width: 1)
        #expect(first)
        #expect(!second, "同 seq 第二次略過，座標不被覆蓋")
        #expect(m.entries == [TrackModel.Entry(seq: 5, tapeX: 100, width: 50)])
        #expect(m.contains(seq: 5) && !m.contains(seq: 6))
    }

    @Test func viewAddTwiceKeepsOneLayer() {
        let v = TickerView(config: .provisional)
        let p = PlacedItem(source: "t", id: "1", style: .live, timeString: "12:34:56", text: "x", truncated: false,
                           tapeX: 400, width: 120, url: nil, seq: 9, listID: 1, listIndex: 1, hasLinkSlot: false)
        v.add(p); v.add(p)
        #expect(v.layerCount == 1 && v.layerSeqs == [9] && v.containerCount == 1, "重複 add 不留下孤兒圖層")
    }

    @Test func backwardSeekRebuildsPrunedLayersWithoutDuplicates() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(10)))
        d.step()
        // 讓閱讀位置走到清單第 6 則以後（左側早已被 prune）。
        var guardN = 0
        while (d.scheduler.readingPosition?.index ?? 0) < 6 && guardN < 400 { clock.t += 0.5; d.step(); guardN += 1 }
        #expect((d.scheduler.readingPosition?.index ?? 0) >= 6)
        var rebuilt = 0
        for _ in 0..<4 {
            let beforeSeqs = Set(r.track.entries.map(\.seq))
            let outcome = d.seek(.previous)
            guard case .moved(let target, _) = outcome else { Issue.record("seek 失敗 \(outcome)"); return }
            if !beforeSeqs.contains(target.seq) { rebuilt += 1 }
            #expect(r.track.contains(seq: target.seq), "目標圖層存在")
            #expect(abs(r.offset - target.tapeX) < 1e-9, "目標貼齊視窗左緣")
            let seqs = r.track.entries.map(\.seq)
            #expect(seqs.count == Set(seqs).count, "圖層不重複")
        }
        #expect(rebuilt >= 1, "至少有一次目標圖層原本已被 prune 而需要重建（否則測試沒有鑑別力）")
    }

    @Test func seekNextForcePlacesAndAddsNewLayer() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(3)))
        d.step(); clock.t += 1; d.step()
        let before = d.itemsPlaced
        var n = 0
        while n < 3 { if case .moved = d.seek(.next) { n += 1 } else { break } }
        #expect(n == 3)
        #expect(d.itemsPlaced > before - 1)
        #expect(r.track.contains(seq: d.scheduler.readingItem!.seq))
    }
}

@MainActor
@Suite struct TickerRendererControlStripTests {
    private func pos(_ i: Int, _ n: Int) -> ReadingPosition {
        ReadingPosition(item: PlacedItem(source: "t", id: "1", style: .live, timeString: "", text: "", truncated: false, tapeX: 0, width: 100),
                        index: i, total: n)
    }
    @Test func stateFromReadingPosition() {
        #expect(ControlStripState.from(position: nil) == ControlStripState(text: "", previousEnabled: false, nextEnabled: false))
        #expect(ControlStripState.from(position: pos(1, 10)) == ControlStripState(text: "(1/10)", previousEnabled: false, nextEnabled: true))
        #expect(ControlStripState.from(position: pos(10, 10)) == ControlStripState(text: "(10/10)", previousEnabled: true, nextEnabled: true), "最後一則仍可按 >（跳下一輪）")
    }

    @Test func driverPushesControlStateOnlyWhenItChanges() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(10)))
        d.step()
        #expect(r.controlStates.isEmpty, "初始（無閱讀位置）與視圖預設相同，不送")
        clock.t += 6; d.step()                     // 第一則進入閱讀範圍
        let t1 = r.controlStates.last
        #expect(t1?.text.hasPrefix("(1/10)") == true)
        let n = r.controlStates.count
        d.step(); d.step()
        #expect(r.controlStates.count == n, "狀態沒變就不重送")
    }

    @Test func viewLayoutMatchesControlStripLayoutAndHitTesting() {
        let cfg = ShellConfig.provisional
        let v = TickerView(config: cfg)
        let l = v.layoutSnapshot
        let inset = Double(cfg.labelWidth)          // 控制列在標籤右側（nav-layout-tweaks）
        let labelSlant = 12.0                       // 控制列底延伸到標籤斜切邊下方
        #expect(Double(l.stripFrame.minX) == inset - labelSlant && Double(l.stripFrame.maxX) == inset + cfg.controlStripWidth)
        #expect(Double(l.previousFrame.minX) == cfg.strip.previousButtonRange(leftInset: inset).lowerBound)
        #expect(Double(l.previousFrame.width) == cfg.strip.buttonWidth)
        #expect(Double(l.indicatorFrame.minX) == cfg.strip.indicatorRange(leftInset: inset).lowerBound)
        #expect(Double(l.indicatorFrame.width) == cfg.strip.indicatorWidth)
        #expect(Double(l.nextFrame.minX) == cfg.strip.nextButtonRange(leftInset: inset).lowerBound)
        #expect(Double(l.clipFrame.minX) >= Double(l.stripFrame.maxX), "帶子裁切在控制列之外（帶子在控制列右側）")
        #expect(Double(l.clipFrame.minX) == inset + cfg.controlStripWidth && Double(l.clipFrame.maxX) == Double(cfg.panelSize.width))
        #expect(Double(l.clipFrame.width) == cfg.tapeViewportWidth && l.scrollOriginX == 0, "帶子座標 0 ＝ 可視區左緣")
        // 版面中心點經 HitTesting 必為對應動作（版面與命中測試一致）。
        let g = cfg.hitGeometry
        func hit(_ r: CGRect) -> HitTarget { HitTesting.target(at: CGPoint(x: r.midX, y: r.midY), in: g, items: []) }
        #expect(hit(l.previousFrame) == .previousButton)
        #expect(hit(l.nextFrame) == .nextButton)
        #expect(hit(l.indicatorFrame) == .drag)
    }

    @Test func disabledButtonsAreDimmedAndIndicatorTextShown() {
        let v = TickerView(config: .provisional)
        v.setControlStrip(ControlStripState(text: "(1/10)", previousEnabled: false, nextEnabled: true))
        var l = v.layoutSnapshot
        #expect(l.indicatorText == "(1/10)")
        #expect(l.previousOpacity < l.nextOpacity && l.nextOpacity == 1)
        v.setControlStrip(ControlStripState(text: "(2/10)", previousEnabled: true, nextEnabled: true))
        l = v.layoutSnapshot
        #expect(l.previousOpacity == 1 && l.indicatorText == "(2/10)")
    }

    @Test func tapeViewportIsDerivedFromControlStripNotHardCoded() {
        var cfg = ShellConfig.provisional
        #expect(cfg.tapeViewportWidth == 370 && cfg.controlStripWidth == 100)
        #expect(cfg.schedulerConfig().viewportWidth == 370 && cfg.schedulerConfig().linkSlotWidth == cfg.linkSlotWidth)
        cfg.strip = ControlStripLayout(buttonWidth: 30, indicatorWidth: 60)
        #expect(cfg.tapeViewportWidth == 620 - 150 - 120)
        let l = TickerView(config: cfg).layoutSnapshot
        #expect(Double(l.clipFrame.minX) == 150 + 120 && Double(l.clipFrame.width) == 350 && Double(l.clipFrame.maxX) == 620)
    }
}
