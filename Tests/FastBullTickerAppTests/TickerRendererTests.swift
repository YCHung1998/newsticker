import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp
import FastBullTickerCore

// task 4.1：TickerRenderer／TickerDriver。執行：swift test --filter TickerRenderer

final class ManualClock { var t: Double = 100 }

/// 測試替身：記錄呼叫序列，並用 TrackModel 維護座標（與真 renderer 同一套邏輯）。
@MainActor
final class RecordingRenderer: TickerRenderer {
    enum Call: Equatable { case add(String), offset(Double), rebase(Double), paused(Bool) }
    var calls: [Call] = []
    var track = TrackModel()
    var offset = 0.0
    var paused = false
    func add(_ item: PlacedItem) { calls.append(.add(item.id)); track.add(tapeX: item.tapeX, width: item.width) }
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
        let a = m.add(tapeX: 1_000_000, width: 300)
        let b = m.add(tapeX: 1_000_348, width: 300)
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
        let bitmap = ItemBitmapRenderer(fontSize: cfg.fontSize, padding: cfg.itemPadding, heightPt: cfg.panelSize.height, textureLimitPx: cfg.textureLimitPx)
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
