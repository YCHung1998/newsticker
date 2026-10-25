import Testing
import Foundation
@testable import FastBullTickerApp
import FastBullTickerCore

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// settings-gear task 5：輪詢間隔的整條路徑——樣式變更 → `StyleApplier.onPollIntervalChange` → `FeedClient.reconfigure` → 假 helper 重啟
// → 新 helper 重送 snapshot → `AppCoordinator` → `TickerDriver`／Core。headless、無視窗、不連網。執行：swift test --filter PollIntervalSmoke
@MainActor
@Suite struct PollIntervalSmokeTests {
    private func waitFor(_ timeout: Double = 10, _ cond: @MainActor () -> Bool) async -> Bool {
        await AppSmokeTests().awaitCondition(timeout, cond)
    }

    @MainActor private struct Rig {
        let sb = Sandbox()
        let rig = StyleRig()
        let coord: AppCoordinator
        let client: FeedClient
        let args: URL
        init(initialPoll: Int = 10) {
            args = sb.dir.appendingPathComponent("args.log")
            let helper = sb.script("snapshot-on-start", "echo \"$*\" >> \"\(args.path)\"\necho '\(Lines.snapshot)'\nexec cat >/dev/null")
            coord = AppCoordinator(driver: rig.driver, log: AppLog(fileURL: nil, toStderr: false))
            client = FeedClient(config: FeedClientConfig(helperURL: helper, arguments: FeedClientConfig.helperArguments(pollIntervalSeconds: initialPoll), pidFileURL: nil),
                                onEvent: AppCoordinator.bridge(to: coord))
            let client = self.client
            rig.applier.onPollIntervalChange = { client.reconfigure(arguments: FeedClientConfig.helperArguments(pollIntervalSeconds: $0)) }
        }
        var argLines: [String] { ((try? String(contentsOf: args, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) }
        func stop() { client.shutdown() }
    }

    @Test func restartResendsSnapshotWithoutTriggeringLiveOrClearingTheBelt() async throws {
        let r = Rig()
        r.client.start()
        defer { r.stop() }
        #expect(await waitFor { r.coord.snapshots >= 1 })
        r.rig.run(seconds: 6); r.coord.noteMode()
        let placedBefore = r.rig.driver.scheduler.placed
        let countBefore = r.rig.driver.itemsPlaced
        #expect(!placedBefore.isEmpty && r.coord.modesSeen == [.replay])

        var s = TickerStyle.default; s.pollIntervalSeconds = 30
        #expect(r.rig.applier.apply(s, source: "test"))
        #expect(await waitFor { r.coord.snapshots >= 2 && r.coord.helperStarts >= 2 })
        #expect(r.argLines == ["", "--interval-ms 30000"], "新 helper 以 --interval-ms 30000 啟動：\(r.argLines)")

        r.rig.run(seconds: 6); r.coord.noteMode()
        #expect(r.coord.modesSeen == [.replay], "重送 snapshot 沒有誤觸即時模式：\(r.coord.modesSeen)")
        #expect(Array(r.rig.driver.scheduler.placed.prefix(placedBefore.count)) == placedBefore, "帶子上的訊息沒有被洗掉或重排")
        #expect(r.rig.driver.itemsPlaced >= countBefore && r.rig.driver.scheduler.liveQueueCount == 0)
    }

    @Test func restartWhileLiveKeepsTheLiveQueue() async throws {
        let r = Rig()
        r.client.start()
        defer { r.stop() }
        #expect(await waitFor { r.coord.snapshots >= 1 })
        r.rig.run(seconds: 4)
        r.rig.driver.receive(.items([Item(source: "fastbull", id: "99", publishedAtMs: 9_000, text: "即時：重啟前到達")]))
        r.coord.noteMode()
        #expect(r.rig.driver.mode == .live && r.rig.driver.scheduler.liveQueueCount == 1)

        var s = TickerStyle.default; s.pollIntervalSeconds = 60
        r.rig.applier.apply(s, source: "test")
        #expect(await waitFor { r.coord.snapshots >= 2 })
        #expect(r.rig.driver.mode == .live && r.rig.driver.scheduler.liveQueueCount == 1, "重送 snapshot 沒有洗掉即時佇列")
        #expect(r.argLines.last == "--interval-ms 60000")
    }

    @Test func otherStyleChangesNeverRestartTheHelper() async throws {
        let r = Rig()
        r.client.start()
        defer { r.stop() }
        #expect(await waitFor { r.coord.helperStarts >= 1 && r.argLines.count == 1 })
        var s = TickerStyle.default; s.fontSize = 20; s.seekHoldSeconds = 3; s.scrollSpeed = 120
        r.rig.applier.apply(s, source: "test")
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(r.coord.helperStarts == 1 && r.argLines.count == 1)
    }

    @Test func applierCallbackFiresOncePerChangeAndNeverOnStartup() {
        let rig = StyleRig()
        var calls: [Int] = []
        rig.applier.onPollIntervalChange = { calls.append($0) }
        var s = TickerStyle.default; s.pollIntervalSeconds = 30
        rig.applier.apply(s, source: "menu")
        #expect(calls == [30])
        s.fontSize = 20
        rig.applier.apply(s, source: "menu")
        #expect(calls == [30], "只改其他欄位不回呼")
        rig.applier.apply(s, source: "menu")
        #expect(calls == [30], "相同樣式不重套")
        s.pollIntervalSeconds = 10
        rig.applier.apply(s, source: "file")
        #expect(calls == [30, 10])

        let startup = StyleRig()
        var startupCalls: [Int] = []
        startup.applier.onPollIntervalChange = { startupCalls.append($0) }
        var t = TickerStyle.default; t.pollIntervalSeconds = 60
        startup.applier.apply(t, source: "startup")
        #expect(startupCalls.isEmpty && startup.applier.current.pollIntervalSeconds == 60, "啟動套用不回呼（啟動參數由載入的樣式直接決定）")
    }
}
