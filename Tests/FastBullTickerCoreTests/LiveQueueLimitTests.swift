import Testing
import Foundation
@testable import FastBullTickerCore

@Suite struct LiveQueueLimitTests {
    @Test func over30DropsOldest() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        s.hide()
        let ev = s.receive(live(Array(11...45)))             // 35 則
        #expect(ev == [.liveQueueOverflow(dropped: 5)])
        #expect(s.liveQueueCount == 30)
        #expect(s.totalDropped == 5)
        s.show()
        let placed = s.run(clock, seconds: 100)
        let liveIds = placed.filter { $0.style == .live }.map(\.id)
        #expect(liveIds == (16...45).map(String.init))       // 最舊 11..15 被丟
    }

    @Test func exactly30DropsNothing() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(snap(Array(1...10)))
        let ev = s.receive(live(Array(11...40)))
        #expect(ev.isEmpty && s.liveQueueCount == 30 && s.totalDropped == 0)
    }

    @Test func droppedCountAccumulatesAcrossMessages() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live(Array(11...40)))
        let ev = s.receive(live([41, 42, 43]))
        #expect(ev == [.liveQueueOverflow(dropped: 3)])
        #expect(s.totalDropped == 3)
    }

    @Test func droppedItemsStillInLatestTenAndReplayLater() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        s.hide()
        _ = s.receive(.items([it(91), it(92), it(93), it(94), it(95)]))   // 先到、時間最新 → 在佇列最舊端
        _ = s.receive(live(Array(11...40)))                              // 共 35 → 丟掉 91..95
        #expect(s.totalDropped == 5)
        #expect(s.latestItems.map(\.id).prefix(5) == ["95", "94", "93", "92", "91"])
        s.show()
        let placed = s.run(clock, seconds: 120)
        #expect(!placed.contains { $0.id == "95" && $0.style == .live })
        #expect(placed.contains { $0.id == "95" && $0.style == .replay })
    }
}
