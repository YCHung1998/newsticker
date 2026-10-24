import Testing
import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

// task 4.2：headless 煙霧測試——假 helper → FeedClient → AppCoordinator → TickerDriver（Core Scheduler）。
// 不建立任何視窗、不連網。執行：swift test --filter AppSmoke

@MainActor
@Suite struct AppSmokeTests {
    func awaitCondition(_ timeout: Double = 10, _ cond: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return cond()
    }

    static var demoHelper: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/demo-helper.sh")
    }

    @Test func snapshotThenItemsDriveSchedulerReplayToLiveToReplay() async throws {
        let sb = Sandbox()
        // 包一層：縮短示範 helper 的間隔，且用 exec 保留 stdin。
        let wrapper = sb.script("wrapped-demo.sh", "DEMO_ITEM_INTERVAL=2 DEMO_STATUS_INTERVAL=3 exec \"\(Self.demoHelper.path)\"")
        let clock = ManualClock()
        let (driver, renderer) = makeDriver(clock: clock)
        let coord = AppCoordinator(driver: driver, log: AppLog(fileURL: nil, toStderr: false))
        let client = FeedClient(config: FeedClientConfig(helperURL: wrapper, pidFileURL: nil),
                                onEvent: AppCoordinator.bridge(to: coord))
        client.start()
        defer { client.shutdown() }

        #expect(await awaitCondition { coord.snapshots >= 1 })
        #expect(driver.mode == .replay)
        #expect(driver.scheduler.latestItems.count == 10)          // 12 則 snapshot，重播取最新 10
        driver.step(); clock.t += 1; driver.step()
        #expect(driver.itemsPlaced >= 1)
        #expect(renderer.calls.contains { if case .add = $0 { return true } else { return false } })

        #expect(await awaitCondition { coord.itemBatches >= 1 })   // 約 2 秒後第一則新訊息
        #expect(coord.modesSeen.contains(.live))
        // 快速推進假時鐘，直到即時佇列播完 → 回到重播。
        var guardCount = 0
        while (driver.mode == .live || driver.scheduler.liveQueueCount > 0) && guardCount < 500 {
            clock.t += 1; driver.step(); coord.noteMode(); guardCount += 1
        }
        #expect(driver.mode == .replay)
        #expect(Array(coord.modesSeen.prefix(3)) == [.replay, .live, .replay])
        #expect(coord.statuses >= 1)
        #expect(coord.badLines == 0)
        #expect(coord.statsLine.contains("mode=replay"))
    }

    @Test func demoHelperExitsOnStdinEofWithoutOrphan() async throws {
        let sb = Sandbox()
        let wrapper = sb.script("wrapped-demo2.sh", "exec \"\(Self.demoHelper.path)\"")
        let log = EventLog()
        let clock = FakeClock()
        let client = makeClient(wrapper, clock: clock, log: log)
        client.start()
        #expect(waitUntil { log.pids.count == 1 && !log.messages.isEmpty })
        let pid = try #require(log.pids.first)
        let done = Box()
        client.shutdown { done.eof() }
        #expect(waitUntil(timeout: 5) { done.eofCount == 1 })
        #expect(waitUntil(timeout: 5) { !processIsAlive(pid) })
    }
}
