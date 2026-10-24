import Testing
import Foundation
@testable import FastBullTickerCore

@Suite struct FreezeResumeTests {
    private func warmedUp() -> (FakeClock, TickerScheduler) {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.run(clock, seconds: 3)
        return (clock, s)
    }

    @Test func hideForOneHourDoesNotJump() {
        var (clock, s) = warmedUp()
        let before = s.placed.map { s.visualX(of: $0) }
        let offset = s.scrollOffset
        #expect(!before.isEmpty)
        s.hide()
        clock.t += 3600
        _ = s.tick()                                          // 隱藏中 tick 不得推進
        s.show()
        #expect(s.placed.map { s.visualX(of: $0) } == before)
        #expect(s.scrollOffset == offset)
    }

    @Test func resumesFromFrozenTapeTime() {
        var (clock, s) = warmedUp()
        s.hide(); clock.t += 3600; s.show()
        let frozen = s.scrollOffset
        clock.t += 2; _ = s.tick()
        #expect(abs(s.scrollOffset - (frozen + 2 * 100)) < 1e-9)   // 預熱用 0.1 步長，浮點誤差在容忍度內
    }

    @Test func hideAccruesTimeUpToHideMoment() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        clock.t = 2
        s.hide()
        #expect(s.tapeTime == 2)
    }

    @Test func hiddenDoesNotFillButQueueKeepsLiveItems() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2, 3]))
        s.hide()
        _ = s.receive(live([11]))
        clock.t += 10
        #expect(s.tick().isEmpty && s.placed.isEmpty)         // 隱藏期間不補料
        #expect(s.liveQueueCount == 1)
        s.show()
        let p = s.tick()
        #expect(p.count == 1 && p[0].id == "11" && p[0].style == .live)
    }

    @Test func repeatedHideIsIdempotent() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        clock.t = 1; s.hide()
        clock.t = 5; s.hide()
        clock.t = 9; s.show()
        clock.t = 10; _ = s.tick()
        #expect(s.tapeTime == 2)                              // 1(隱藏前) + 1(恢復後)
    }

    @Test func repeatedShowIsIdempotent() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        clock.t = 1; s.show()                                 // 本來就可見
        clock.t = 3; s.show()
        _ = s.tick()
        #expect(s.tapeTime == 3)
    }

    @Test func hiddenFlagFollowsHideShow() {
        var s = makeScheduler(FakeClock())
        #expect(!s.isHidden)
        s.hide(); #expect(s.isHidden)
        s.show(); #expect(!s.isHidden)
    }
}
