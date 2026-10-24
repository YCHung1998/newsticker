import Testing
import Foundation
@testable import FastBullTickerCore

/// 閱讀位置查詢（tasks 5.1）。speed 100、gap 20、viewport 200、每則寬 130、readingInset 24。
/// 重播順序：id 10, 9, 8 ... 的 tapeX 依序為 200, 350, 500 ...（間距 150）。
@Suite struct ReadingPositionTests {
    private func make(inset: Double? = nil) -> (FakeClock, TickerScheduler) {
        var cfg = SchedulerConfig.test
        if let inset { cfg.readingInset = inset }
        let clock = FakeClock()
        var s = makeScheduler(clock, config: cfg)
        _ = s.receive(snap(Array(1...10)))
        _ = s.tick()                                   // t=0：第一則排在視窗右緣（tapeX=200）
        return (clock, s)
    }

    @Test func emptyTapeHasNoReadingItem() {
        let s = makeScheduler(FakeClock())
        #expect(s.readingItem == nil && s.readingPosition == nil)
    }

    @Test func allBeyondRightEdgeIsNil() {
        let (_, s) = make()                            // t=0：唯一一則 tapeX=200 = viewportWidth
        #expect(s.placed.count == 1)
        #expect(s.readingItem == nil && s.readingPosition == nil)
    }

    @Test func itemNearLeftEdgeIsReading() {
        var (clock, s) = make()
        s.tickTo(clock, 3)                      // scrollOffset 300：id10 左緣 −100、右緣 30；id9 左緣 50
        #expect(s.readingItem?.id == "10")
    }

    @Test func rightEdgeEqualToInsetMeansNextOne() {
        var (clock, s) = make(inset: 30)
        s.tickTo(clock, 3)                      // id10 右緣 = 330 − 300 = 30 = readingInset（須「大於」）
        #expect(s.readingItem?.id == "9")
    }

    @Test func replayPositionIndexAndTotal() {
        var (clock, s) = make()
        s.tickTo(clock, 5)                      // scrollOffset 500 → id8 左緣 0
        let pos = s.readingPosition
        #expect(pos?.item.id == "8" && pos?.index == 3 && pos?.total == 10)
    }

    @Test func queryIsPureAndHasNoSideEffects() {
        var (clock, s) = make()
        s.tickTo(clock, 5)
        let placed = s.placed, tape = s.tapeTime, off = s.scrollOffset, hold = s.holdRemaining, base = s.baseOffset
        let p1 = s.readingPosition, p2 = s.readingPosition, r1 = s.readingItem, r2 = s.readingItem
        #expect(p1 == p2 && r1 == r2 && p1 != nil)
        #expect(s.placed == placed && s.tapeTime == tape && s.scrollOffset == off && s.holdRemaining == hold && s.baseOffset == base)
        clock.t += 100                                 // 時鐘前進但沒有 tick/advance：查詢不得讀時鐘
        #expect(s.readingPosition == p1)
    }

    @Test func hiddenKeepsTheSameResultAsAtHideMoment() {
        var (clock, s) = make()
        s.tickTo(clock, 5)
        let atHide = s.readingPosition
        s.hide()
        clock.t += 3600; _ = s.tick()
        #expect(s.readingPosition == atHide)
    }

    @Test func liveBatchTotalGrowsAndLeftEdgeListWins() {
        var (clock, s) = make()
        s.tickTo(clock, 2)                      // 10@200, 9@350
        _ = s.receive(live([21, 22, 23]))
        s.tickTo(clock, 3)                      // 21@500 排入
        // 重播的 9（2/10）仍在左緣：以左緣那一則的清單為準
        s.tickTo(clock, 4.4)
        #expect(s.readingPosition?.item.id == "9")
        #expect(s.readingPosition?.index == 2 && s.readingPosition?.total == 10)
        s.tickTo(clock, 5)                      // 21 到左緣
        #expect(s.readingPosition?.item.id == "21" && s.readingPosition?.index == 1 && s.readingPosition?.total == 3)
        _ = s.receive(live([24]))                      // 同一批次追加
        #expect(s.readingPosition?.total == 4)
    }

    @Test func readingInsetIsSmallerThanEveryItemWidth() {
        // seek 後閱讀中必為目標的前提：readingInset < 任何訊息 width（時間字串本身 8 字元 > 24pt）
        let c = SchedulerConfig()
        let timeOnly = flatMeasure("16:56:41 ")
        #expect(c.readingInset < timeOnly)
    }
}
