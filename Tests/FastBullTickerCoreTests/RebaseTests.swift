import Testing
import Foundation
@testable import FastBullTickerCore

@Suite struct RebaseTests {
    /// 兩個以相同輸入驅動的排程器；A 之後會 rebase，B 為對照。
    private func pair(seconds: Double) -> (FakeClock, TickerScheduler, TickerScheduler) {
        let clock = FakeClock()
        var a = makeScheduler(clock), b = makeScheduler(clock)
        _ = a.receive(snap(Array(1...10))); _ = b.receive(snap(Array(1...10)))
        var t = 0.0
        while t < seconds { t += 0.25; clock.t = t; _ = a.tick(); _ = b.tick() }
        return (clock, a, b)
    }

    @Test func visualPositionsUnchangedAndMagnitudesShrink() {
        let (_, a0, b) = pair(seconds: 5000)
        var a = a0
        let beforeVisual = a.placed.map { a.visualX(of: $0) }
        let beforeOffset = a.scrollOffset
        let delta = a.rebase()
        #expect(delta == beforeOffset)
        #expect(abs(a.scrollOffset) < abs(beforeOffset) / 100)
        let afterVisual = a.placed.map { a.visualX(of: $0) }
        // rebase 可能移除已捲出者：以尾端對齊比較
        let tail = beforeVisual.suffix(afterVisual.count)
        #expect(Array(tail) == afterVisual)
        #expect(a.placed.map(\.tapeX).allSatisfy { abs($0) < 5000 })
        // tapeX 位移恰為 delta，間距/寬度/順序不變
        let bTail = b.placed.suffix(a.placed.count)
        for (x, y) in zip(a.placed, bTail) {
            #expect(x.tapeX == y.tapeX - delta && x.width == y.width && x.id == y.id)
        }
    }

    @Test func keepsTailAndContinuesFillingWithGapLikeControl() {
        var (clock, a, b) = pair(seconds: 3000)
        _ = a.rebase()
        var pa: [PlacedItem] = [], pb: [PlacedItem] = []
        var t = clock.t
        for _ in 0..<400 { t += 0.25; clock.t = t; pa += a.tick(); pb += b.tick() }
        #expect(!pa.isEmpty && pa.count == pb.count)
        for (x, y) in zip(pa, pb) {
            #expect(x.id == y.id && x.style == y.style)
            #expect(a.visualX(of: x) == b.visualX(of: y))
        }
        for (p, q) in zip(pa, pa.dropFirst()) { #expect(q.tapeX - p.tapeX == p.width + 20) }
        // 尾端與 rebase 前最後一則仍相距 gap
        let firstNew = pa[0]
        let lastOld = a.placed.last { $0.tapeX < firstNew.tapeX }
        #expect(lastOld != nil)
        #expect(firstNew.tapeX - (lastOld!.tapeX + lastOld!.width) == 20)
    }

    @Test func rebaseWhileHiddenDoesNotJumpOnResume() {
        var (clock, a, b) = pair(seconds: 1000)
        a.hide(); b.hide()
        let beforeVisual = a.placed.map { a.visualX(of: $0) }
        let d = a.rebase()
        #expect(d != 0)
        clock.t += 3600
        a.show(); b.show()
        let tail = beforeVisual.suffix(a.placed.count)
        #expect(a.placed.map { a.visualX(of: $0) } == Array(tail))
        #expect(a.tapeTime == b.tapeTime)
    }

    @Test func rebaseDoesNotChangeModeQueueOrOrder() {
        var (clock, a, _) = pair(seconds: 100)
        _ = a.receive(live([11, 12]))
        let mode = a.mode, q = a.liveQueueCount
        _ = a.rebase()
        #expect(a.mode == mode && a.liveQueueCount == q)
        let placed = a.run(clock, seconds: 10)
        #expect(placed.prefix(2).map(\.id) == ["11", "12"])
    }

    @Test func shouldRebaseThresholdIsPure() {
        #expect(!TickerScheduler.shouldRebase(scrollOffset: 499_999, threshold: 500_000))
        #expect(TickerScheduler.shouldRebase(scrollOffset: 500_000, threshold: 500_000))
        #expect(TickerScheduler.shouldRebase(scrollOffset: -600_000, threshold: 500_000))
        var s = makeScheduler(FakeClock())
        #expect(!s.shouldRebase)
        var c = SchedulerConfig.test; c.rebaseThreshold = 100
        let clock = FakeClock()
        s = makeScheduler(clock, config: c)
        clock.t = 2; _ = s.tick()
        #expect(s.shouldRebase)
    }
}
