import Testing
import Foundation
@testable import FastBullTickerCore

/// 排入序號與清單識別（tasks 4.1）。假時鐘、flatMeasure，不碰真實時間。
@Suite struct ListIdentityTests {
    private func warmed(count: Int = 10, seconds: Double) -> (FakeClock, TickerScheduler, [PlacedItem]) {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...count)))
        let placed = s.run(clock, seconds: seconds)
        return (clock, s, placed)
    }

    @Test func newConfigDefaultsDoNotChangeExistingBehaviour() {
        let c = SchedulerConfig()
        #expect(c.seekHoldSeconds == 1 && c.readingInset == 24 && c.linkSlotWidth == 0 && c.retainPlacedCount == 64)
    }

    @Test func replayRoundSequenceAndListIndex() {
        let (_, s, placed) = warmed(seconds: 40)          // 每則 1.5 秒，足夠排 11 則以上
        #expect(placed.count > 12)
        let first = Array(placed.prefix(10)), eleventh = placed[10]
        #expect(Set(first.map(\.listID)).count == 1)
        #expect(first.map(\.listIndex) == Array(1...10))
        #expect(first.map(\.id) == (1...10).reversed().map(String.init))      // 最新者名次 1
        #expect(eleventh.listID != first[0].listID && eleventh.listIndex == 1 && eleventh.id == "10")
        let seqs = placed.map(\.seq)
        #expect(seqs == Array(1...placed.count), "seq 從 1 起、單調遞增、互不相同")
        #expect(s.listTotal(of: first[0].listID) == 10)
    }

    @Test func historyShorterThanReplayCount() {
        let (_, s, placed) = warmed(count: 7, seconds: 30)
        #expect(placed.prefix(7).map(\.listIndex) == Array(1...7))
        #expect(placed[7].listIndex == 1 && placed[7].listID != placed[0].listID)
        #expect(s.listTotal(of: placed[0].listID) == 7)
    }

    @Test func liveBatchIdentityAndTotals() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live([21, 22, 23]))
        var out: [PlacedItem] = []
        clock.t = 0; out += s.tick()                    // 第一則即時訊息排入
        #expect(out.count == 1 && out[0].id == "21" && out[0].style == .live)
        #expect(s.listTotal(of: out[0].listID) == 3, "已排入 1 + 佇列 2")
        out += s.run(clock, seconds: 6)
        let lives = out.filter { $0.style == .live }
        #expect(lives.map(\.id) == ["21", "22", "23"])
        #expect(Set(lives.map(\.listID)).count == 1)
        #expect(lives.map(\.listIndex) == [1, 2, 3])
        #expect(s.listTotal(of: lives[0].listID) == 3)
        // 批次關閉後的重播是新清單
        let replayAfter = out.first { $0.style == .replay && $0.seq > lives[2].seq }
        #expect(replayAfter != nil && replayAfter!.listID != lives[0].listID && replayAfter!.listIndex == 1)
    }

    @Test func liveAppendWhileLiveIncreasesTotal() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live([21]))
        let n1 = s.tick()
        #expect(n1.count == 1 && s.listTotal(of: n1[0].listID) == 1)
        _ = s.receive(live([22]))
        #expect(s.listTotal(of: n1[0].listID) == 2, "LIVE 追加使同一批次總數 1 → 2")
        _ = s.receive(live([23, 24]))
        #expect(s.listTotal(of: n1[0].listID) == 4)
    }

    @Test func overflowDropShrinksOpenBatchTotal() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live(Array(100..<140)))            // 40 則，佇列上限 30，丟最舊 10
        let p = s.tick()
        #expect(p.count == 1 && p[0].id == "110")
        #expect(s.listTotal(of: p[0].listID) == 30)
    }

    @Test func urlIsCarriedUnchangedAndLinkSlotFlagged() {
        var cfg = SchedulerConfig.test
        cfg.linkSlotWidth = 26
        let clock = FakeClock()
        var s = makeScheduler(clock, config: cfg)
        _ = s.receive(.snapshot([itu(3), it(2), itu(1)]))
        let placed = s.run(clock, seconds: 10)
        let a = placed[0], b = placed[1], c = placed[2]
        #expect(a.url == "https://example.test/n/3" && a.hasLinkSlot && a.width == itemWidth + 26)
        #expect(b.url == nil && !b.hasLinkSlot && b.width == itemWidth)
        #expect(c.url == "https://example.test/n/1" && c.hasLinkSlot)
        #expect(b.tapeX - (a.tapeX + a.width) == 20, "間距仍為 gap（含連結欄位）")
    }

    @Test func zeroLinkSlotKeepsLayoutIdenticalEvenWithURL() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(.snapshot([itu(2), itu(1)]))
        let placed = s.run(clock, seconds: 5)
        #expect(placed.allSatisfy { !$0.hasLinkSlot && $0.width == itemWidth } && placed[0].url != nil)
    }

    @Test func rebaseDoesNotChangeIdentityFields() {
        let (_, s0, _) = warmed(seconds: 60)
        var s = s0
        let before = s.placed.map { [$0.seq, $0.listID, $0.listIndex] }
        let totals = Set(s.placed.map(\.listID)).map { s.listTotal(of: $0) }
        _ = s.rebase()
        let kept = s.placed.map { [$0.seq, $0.listID, $0.listIndex] }
        #expect(kept == Array(before.suffix(kept.count)))
        #expect(Set(s.placed.map(\.listID)).allSatisfy { s.listTotal(of: $0) != nil })
        #expect(totals.allSatisfy { $0 != nil })
    }
}
