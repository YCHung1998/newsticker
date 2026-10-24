import Testing
import Foundation
@testable import FastBullTickerCore

@Suite struct ReplayLiveStateTests {
    @Test func startupSnapshotNeverTriggersLive() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        let placed = s.run(clock, seconds: 60)             // 遠超一輪
        #expect(placed.count > 10)
        #expect(placed.allSatisfy { $0.style == .replay })
        #expect(s.mode == .replay)
    }

    @Test func newMessageDuringReplayAppendsAfterTailWithoutInterrupting() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        let r1 = s.tick()[0]
        clock.t = 1.5
        let r2 = s.tick()[0]
        let before = s.placed
        _ = s.receive(live([11]))
        #expect(s.mode == .live)                            // 供料器切為 LIVE
        #expect(s.placed == before)                         // 已排入者不變
        #expect(s.tick().isEmpty)                           // 尾端還沒空位
        clock.t = 3.0                                       // 右緣 500 == R2 尾端 480 + gap
        let n = s.tick()
        #expect(n.count == 1 && n[0].id == "11" && n[0].style == .live)
        #expect(n[0].tapeX == r2.tapeX + r2.width + 20)
        #expect(s.placed.first == r1)
    }

    @Test func liveAppendKeepsOrderAndStyle() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1]))
        _ = s.receive(live([11]))
        _ = s.receive(live([12, 13]))
        let placed = s.run(clock, seconds: 10)
        #expect(placed.prefix(3).map(\.id) == ["11", "12", "13"])
        #expect(placed.prefix(3).allSatisfy { $0.style == .live })
    }

    @Test func multipleLiveItemsPlayOldestFirst() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1]))
        _ = s.receive(live([30, 10, 20]))                   // live() 會排成舊到新 10,20,30
        let placed = s.run(clock, seconds: 10)
        #expect(placed.prefix(3).map(\.id) == ["10", "20", "30"])
    }

    @Test func afterLiveQueueDrainsReturnsToReplayStartingFromNewest() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live([11, 12]))
        let placed = s.run(clock, seconds: 12)
        let ids = placed.map(\.id), styles = placed.map(\.style)
        #expect(Array(ids.prefix(2)) == ["11", "12"] && Array(styles.prefix(2)) == [.live, .live])
        // 歷史已含剛播過的即時訊息：最新 10 則 = 12,11,10,...,3；replay 從最新(12)開始
        #expect(Array(ids[2..<6]) == ["12", "11", "10", "9"])
        #expect(styles[2...].allSatisfy { $0 == .replay })
        #expect(s.mode == .replay)
    }

    @Test func eachLiveItemPlaysLiveExactlyOnce() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live([11, 12, 13]))
        let placed = s.run(clock, seconds: 40)
        for n in ["11", "12", "13"] {
            #expect(placed.filter { $0.id == n && $0.style == .live }.count == 1)
        }
    }

    @Test func placedItemsKeepTheirStyleAfterModeChange() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.run(clock, seconds: 3)
        let replayed = s.placed
        #expect(!replayed.isEmpty && replayed.allSatisfy { $0.style == .replay })
        _ = s.receive(live([11]))
        _ = s.run(clock, seconds: 3)
        #expect(Array(s.placed.prefix(replayed.count)) == replayed)
    }

    @Test func replayCyclesBackToNewestAfterTen() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        let placed = s.run(clock, seconds: 40)
        let ids = placed.prefix(22).map(\.id)
        let expected = (0..<22).map { String(10 - ($0 % 10)) }
        #expect(ids == expected)
    }

    @Test func replayWithFewerThanTenCyclesOverWhatExists() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2, 3]))
        let placed = s.run(clock, seconds: 20)
        #expect(placed.prefix(7).map(\.id) == ["3", "2", "1", "3", "2", "1", "3"])
    }

    @Test func emptyHistoryKeepsBandBlank() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        #expect(s.run(clock, seconds: 10).isEmpty)
        _ = s.receive(snap([1]))
        #expect(!s.run(clock, seconds: 1).isEmpty)
    }

    @Test func liveItemGetsTimeStringToo() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1]))
        _ = s.receive(live([2]))
        let p = s.run(clock, seconds: 1)
        let l = p.first { $0.style == .live }
        #expect(l?.timeString == "00:16:42")                  // 1_002_000 ms = 00:16:42 UTC
        #expect(l?.width == itemWidth)
    }
}
