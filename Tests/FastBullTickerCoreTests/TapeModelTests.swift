import Testing
import Foundation
@testable import FastBullTickerCore

@Suite struct TapeModelTests {
    @Test func emptyBandStartsAtRightEdge() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1]))
        let first = s.tick()
        #expect(first.count == 1)
        #expect(first[0].tapeX == 200)           // 視窗右緣 = scrollOffset(0) + viewportWidth(200)
        #expect(first[0].width == itemWidth)
        #expect(s.tick().isEmpty)                 // 尾端 + gap = 350 > 200：不補料
    }

    @Test func fillsWhenTailHasRoomAtGap() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2]))
        let a = s.tick()
        clock.t = 1.4                              // scrollOffset 140 → 右緣 340 < 350
        #expect(s.tick().isEmpty)
        clock.t = 1.5                              // 右緣 350 == 尾端 + gap
        let b = s.tick()
        #expect(a.count == 1 && b.count == 1)
        #expect(b[0].tapeX == a[0].tapeX + a[0].width + 20)
    }

    @Test func scrollOffsetIsPureFunctionOfTapeTime() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        clock.t = 4; _ = s.tick()
        let order1 = [3.0, 0.0, 10.0, 3.0].map { s.scrollOffset(atTapeTime: $0) }
        let order2 = [3.0, 10.0, 0.0, 3.0].map { s.scrollOffset(atTapeTime: $0) }
        #expect(order1 == [300, 0, 1000, 300])
        #expect(order2 == [300, 1000, 0, 300])
        #expect(s.scrollOffset == s.scrollOffset(atTapeTime: s.tapeTime))
        #expect(s.scrollOffset == 400)
    }

    @Test func visualXIsTapeXMinusScrollOffset() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1]))
        let p = s.tick()[0]
        clock.t = 0.5; _ = s.tick()
        #expect(s.visualX(of: p) == 200 - 50)
        #expect(s.visualX(of: p, atTapeTime: 2) == 200 - 200)
    }

    @Test func clockRollbackDoesNotMoveTapeTimeBackwards() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        clock.t = 10; _ = s.tick()
        #expect(s.tapeTime == 10)
        clock.t = 5; _ = s.tick()
        #expect(s.tapeTime == 10)                  // 回撥 → 0 增量
        clock.t = 7; _ = s.tick()
        #expect(s.tapeTime == 12)                  // 以回撥後的值重新起算
    }

    @Test func fakeClockDrivesFiveSecondsWithoutWaiting() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        clock.t = 5; _ = s.tick()
        #expect(s.tapeTime == 5)
    }

    @Test func tapeXAndWidthNeverChangeAfterPlacement() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2, 3]))
        var seen = s.tick()
        seen += s.run(clock, seconds: 2)
        let snapshotOfPlaced = s.placed
        _ = s.receive(live([10, 11]))              // 新訊息抵達 + 模式切換
        s.hide(); clock.t += 100; s.show()          // 隱藏後恢復
        _ = s.run(clock, seconds: 5)
        for old in snapshotOfPlaced {
            let now = s.placed.first { $0.source == old.source && $0.id == old.id && $0.tapeX == old.tapeX }
            #expect(now != nil)
            #expect(now?.width == old.width)
        }
        #expect(!seen.isEmpty)
    }

    @Test func spacingIsConstantWithIrregularTicks() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2, 3, 4, 5]))
        var all: [PlacedItem] = []
        for t in [0.0, 0.1, 0.9, 1.0, 2.4, 2.45, 3.9, 4.0, 5.2, 6.6, 7.0, 8.4] {
            clock.t = t
            all += s.tick()
        }
        #expect(all.count >= 5)
        for (a, b) in zip(all, all.dropFirst()) {
            #expect(b.tapeX - a.tapeX == a.width + 20, "\(a.id)->\(b.id)")
        }
    }

    @Test func veryLateTickRestartsFromRightEdgeWhenTailAlreadyLeft() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2]))
        _ = s.tick()
        clock.t = 100                                 // 尾端早已捲出視窗左緣
        let p = s.tick()
        #expect(p.first?.tapeX == s.scrollOffset + 200)
    }
}
