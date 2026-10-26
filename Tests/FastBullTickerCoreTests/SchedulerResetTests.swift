import Testing
import Foundation
@testable import FastBullTickerCore

/// `reset()`（change source-switcher）：切換來源時清掉舊來源的一切，序號與時間軸保持單調。
@Suite struct SchedulerResetTests {
    private func busy() -> (FakeClock, TickerScheduler) {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.tick()
        clock.t += 2; _ = s.tick()
        _ = s.receive(live([21, 22]))
        return (clock, s)
    }

    @Test func clearsHistoryQueuePlacedAndReading() {
        var (_, s) = busy()
        #expect(!s.placed.isEmpty && s.liveQueueCount > 0 && s.mode == .live)
        s.reset()
        #expect(s.placed.isEmpty)
        #expect(s.liveQueueCount == 0)
        #expect(s.latestItems.isEmpty)
        #expect(s.readingItem == nil && s.readingPosition == nil)
        #expect(s.mode == .replay)
    }

    @Test func itemsBeforeSnapshotAreIgnoredAfterReset() {
        var (_, s) = busy()
        s.reset()
        let ev = s.receive(live([30]))
        #expect(ev == [.itemsBeforeSnapshotIgnored(count: 1)])
        #expect(s.liveQueueCount == 0)
    }

    @Test func seqKeepsIncreasingAcrossReset() {
        var (clock, s) = busy()
        let lastSeq = s.placed.map(\.seq).max()!
        let lastList = s.placed.map(\.listID).max()!
        s.reset()
        _ = s.receive(snap(Array(1...5)))
        clock.t += 1
        let placed = s.tick()
        #expect(!placed.isEmpty)
        #expect(placed.allSatisfy { $0.seq > lastSeq && $0.listID > lastList })
    }

    @Test func newItemsStartAtTheRightEdgeNotBehindOldTail() {
        var (clock, s) = busy()
        s.reset()
        _ = s.receive(snap(Array(1...5)))
        clock.t += 0.1
        let first = s.tick().first!
        #expect(first.tapeX <= s.scrollOffset + s.config.viewportWidth + 0.001)
    }

    @Test func configAndTimelineAreUntouched() {
        var (_, s) = busy()
        let cfg = s.config, off = s.scrollOffset, t = s.tapeTime
        s.reset()
        #expect(s.config.speed == cfg.speed && s.config.viewportWidth == cfg.viewportWidth)
        #expect(s.scrollOffset == off && s.tapeTime == t)
    }

    @Test func hiddenAndPointerStateSurviveReset() {
        var (_, s) = busy()
        s.hide(); s.setPointerInside(true)
        s.reset()
        #expect(s.isHidden && s.isPointerInside)
    }
}
