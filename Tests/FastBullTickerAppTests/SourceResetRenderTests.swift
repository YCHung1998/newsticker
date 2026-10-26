import Testing
import Foundation
import FastBullTickerCore
@testable import FastBullTickerApp

/// 切換來源時畫面與 driver 的重設（change source-switcher）。
@MainActor
@Suite struct SourceResetRenderTests {
    private func placed(_ seq: Int) -> PlacedItem {
        PlacedItem(source: "fastbull", id: "\(seq)", style: .live, timeString: "12:34:56", text: "x", truncated: false,
                   tapeX: 400 + Double(seq) * 200, width: 120, url: nil, seq: seq, listID: 1, listIndex: seq, hasLinkSlot: false)
    }

    @Test func viewRemoveAllLeavesNoLayersAndAcceptsNewOnes() {
        let v = TickerView(config: .provisional)
        v.add(placed(1)); v.add(placed(2))
        #expect(v.layerCount == 2 && v.containerCount == 2)
        v.removeAll()
        #expect(v.layerCount == 0 && v.containerCount == 0, "不留孤兒圖層")
        v.add(placed(3))
        #expect(v.layerSeqs == [3])
    }

    @Test func driverResetClearsRendererAndSchedulerAndDropsOldSource() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        d.receive(.snapshot(sampleItems(10)))
        d.step()
        #expect(!r.track.entries.isEmpty)
        d.reset()
        #expect(r.track.entries.isEmpty, "renderer 被清空")
        #expect(r.removeAllCalls == 1)
        #expect(d.scheduler.placed.isEmpty && d.scheduler.latestItems.isEmpty)
        #expect(d.mode == .replay)
        d.receive(.items([Item(source: "jin10", id: "z", publishedAtMs: 1, text: "新來源")]))
        #expect(d.scheduler.liveQueueCount == 0, "新的 snapshot 之前的 items 被忽略")
    }
}
