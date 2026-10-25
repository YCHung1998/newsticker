import Testing
import Foundation
@testable import FastBullTickerCore

/// settings-gear task 5（`poll-interval`「重啟後 snapshot 重送不誤觸即時模式」）：helper 計畫性重啟後，新 helper 的第一次成功輪詢
/// 必送 `snapshot`，所以 Core 會在執行途中再收到一次 snapshot。這些測試固定 Core 對「中途 snapshot」的語意：
/// 只取代歷史、設定基準；不改模式、不碰即時佇列、不動已排入的訊息、不改進行中清單的 `(n/N)`。
/// 基準狀態沿用 `SchedulerSupport`：speed 100、gap 20、viewport 200、每則寬 130。執行：swift test --filter SnapshotResend
@Suite struct SnapshotResendTests {
    private func replayRig(seconds: Double = 3) -> (FakeClock, TickerScheduler) {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        _ = s.run(clock, seconds: seconds)
        return (clock, s)
    }

    @Test func resendDuringReplayKeepsModeQueueAndBelt() {
        var (clock, s) = replayRig()
        #expect(s.mode == .replay && !s.placed.isEmpty)
        let placed = s.placed, pos = s.readingPosition
        let ev = s.receive(snap(Array(1...10)))
        #expect(ev.isEmpty, "不產生任何排程事件")
        #expect(s.mode == .replay && s.liveQueueCount == 0)
        #expect(s.placed == placed, "已排入的訊息不被清掉、不被重排")
        #expect(s.readingPosition == pos, "進行中清單的 (n/N) 不變")
        let more = s.run(clock, seconds: 20)
        #expect(!more.isEmpty && more.allSatisfy { $0.style == .replay }, "之後仍是重播，沒有誤入 LIVE")
        #expect(s.mode == .replay)
    }

    @Test func resendDuringLiveKeepsTheLiveQueueAndOrder() {
        var (clock, s) = replayRig()
        _ = s.receive(live([11, 12, 13]))
        #expect(s.mode == .live && s.liveQueueCount == 3)
        // 尾端有空位時先播出一則即時訊息
        var firstLive: [PlacedItem] = []
        while firstLive.isEmpty { clock.t += 0.1; firstLive = s.tick().filter { $0.style == .live } }
        let queue = s.liveQueueCount, placed = s.placed
        #expect(queue < 3)
        let ev = s.receive(snap(Array(1...13)))            // 新 helper 的 snapshot 已含這幾則
        #expect(ev.isEmpty)
        #expect(s.mode == .live && s.liveQueueCount == queue, "即時佇列不被洗掉")
        #expect(s.placed == placed)
        let rest = s.run(clock, seconds: 30)
        let liveIDs = (firstLive + rest).filter { $0.style == .live }.map(\.id)
        #expect(liveIDs == ["11", "12", "13"], "每則即時訊息仍只以 live 播一次、由舊到新：\(liveIDs)")
        #expect(s.mode == .replay, "佇列播完才回到重播")
    }

    @Test func itemsAlreadyInTheResentSnapshotAreDuplicatesNotLive() {
        var (_, s) = replayRig()
        _ = s.receive(snap(Array(1...10)))
        let ev = s.receive(live([10]))
        #expect(ev == [.duplicatesSkipped(count: 1)])
        #expect(s.mode == .replay && s.liveQueueCount == 0)
    }

    @Test func aGenuinelyNewItemAfterTheResentSnapshotStillTriggersLive() {
        var (_, s) = replayRig()
        _ = s.receive(snap(Array(1...10)))
        _ = s.receive(live([11]))
        #expect(s.mode == .live && s.liveQueueCount == 1)
    }

    @Test func messagesPublishedDuringTheRestartGapGoStraightToHistoryNotLive() {
        // 已知取捨【假設】：舊 helper 最後一次輪詢到新 helper 首次輪詢之間出現的訊息（11）只出現在新 snapshot 內。
        var (_, s) = replayRig()
        _ = s.receive(snap(Array(1...11)))
        #expect(s.mode == .replay && s.liveQueueCount == 0)
        #expect(s.latestItems.first?.id == "11", "它進了重播歷史")
    }

    @Test func resendReplacesHistoryAndFixesThePlayedRound() {
        var (clock, s) = replayRig()
        let pos = s.readingPosition
        _ = s.receive(snap(Array(6...10)))                  // 新 snapshot 只有 5 則（重啟後來源頁面內容較少）
        #expect(s.latestItems.map(\.id) == ["10", "9", "8", "7", "6"], "歷史被取代，重播清單隨之更新")
        #expect(s.readingPosition == pos, "但進行中那一輪的 (n/N) 不變")
        let more = s.run(clock, seconds: 30)
        #expect(more.allSatisfy { $0.style == .replay } && s.mode == .replay)
    }

    @Test func manyRestartsInARowNeverChangeMode() {
        var (clock, s) = replayRig()
        for _ in 0..<8 {
            _ = s.receive(snap(Array(1...10)))
            _ = s.run(clock, seconds: 2)
            #expect(s.mode == .replay && s.liveQueueCount == 0)
        }
    }

    @Test func snapshotBeforeAnyBaselineSetsTheBaselineAndStillNeverMakesLive() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        #expect(s.receive(live([5])) == [.itemsBeforeSnapshotIgnored(count: 1)])
        _ = s.receive(snap(Array(1...10)))
        #expect(s.mode == .replay && s.liveQueueCount == 0)
    }
}
