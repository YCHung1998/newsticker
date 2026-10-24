import Testing
import Foundation
@testable import FastBullTickerCore

@Suite struct HistoryTests {
    @Test func snapshotBuildsNewestTenDescending() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(snap(Array(1...15)))
        #expect(s.latestItems.map(\.id) == (6...15).reversed().map(String.init))
    }

    @Test func itemsMergeAndPushOutOldest() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live([11, 12]))
        #expect(s.latestItems.map(\.id) == (3...12).reversed().map(String.init))
    }

    @Test func duplicateKeyUpdatesHistoryButIsNotQueuedAgain() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(snap([1, 2, 3]))
        var changed = it(3); changed.text = "NEW!"
        let ev = s.receive(.items([changed]))
        #expect(ev == [.duplicatesSkipped(count: 1)])
        #expect(s.liveQueueCount == 0)
        #expect(s.mode == .replay)
        #expect(s.latestItems.first?.text == "NEW!")        // 同鍵以後到者為準
        #expect(s.latestItems.count == 3)
    }

    @Test func sameIdDifferentSourceAreDistinct() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(.snapshot([it(2, source: "b"), it(1, source: "a")]))
        let ev = s.receive(.items([it(1, source: "b")]))
        #expect(ev.isEmpty)
        #expect(s.liveQueueCount == 1)
    }

    @Test func duplicatesInsideOneSnapshotKeepLast() {
        var s = makeScheduler(FakeClock())
        var later = it(5); later.text = "LAST"
        _ = s.receive(.snapshot([it(5), later, it(4)]))
        #expect(s.latestItems.count == 2)
        #expect(s.latestItems.first { $0.id == "5" }?.text == "LAST")
    }

    @Test func midStreamSnapshotReplacesHistoryOnlyAndKeepsQueueAndTape() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap([1, 2, 3]))
        let first = s.tick()
        _ = s.receive(live([10, 11]))
        #expect(s.mode == .live && s.liveQueueCount == 2)
        let ev = s.receive(snap([50, 49]))                  // 重設基準
        #expect(ev.isEmpty)
        #expect(s.latestItems.map(\.id) == ["50", "49"])
        #expect(s.liveQueueCount == 2)                      // 不清佇列
        #expect(s.mode == .live)                            // 不改模式
        #expect(s.placed == first)                          // 不動帶子
    }

    @Test func midStreamSnapshotDoesNotTriggerLive() {
        var s = makeScheduler(FakeClock())
        _ = s.receive(snap([1, 2, 3]))
        _ = s.receive(snap([50, 49]))
        #expect(s.mode == .replay && s.liveQueueCount == 0)
    }

    @Test func itemsBeforeFirstSnapshotAreIgnoredWithErrorEvent() {
        var s = makeScheduler(FakeClock())
        let ev = s.receive(live([1, 2]))
        #expect(ev == [.itemsBeforeSnapshotIgnored(count: 2)])
        #expect(s.liveQueueCount == 0 && s.latestItems.isEmpty && s.mode == .replay)
        _ = s.receive(snap([5]))
        #expect(s.latestItems.map(\.id) == ["5"])
    }

    @Test func statusMessagesAreIgnored() {
        var s = makeScheduler(FakeClock())
        let ev = s.receive(.status(Status(source: "fastbull", state: .error, message: "x")))
        #expect(ev.isEmpty && s.liveQueueCount == 0)
    }

    @Test func historyIsCapped() {
        var c = SchedulerConfig.test; c.historyLimit = 20
        var s = makeScheduler(FakeClock(), config: c)
        _ = s.receive(snap(Array(1...15)))
        for n in 16...60 { _ = s.receive(live([n])) }
        #expect(s.latestItems.map(\.id) == (51...60).reversed().map(String.init))
    }
}
