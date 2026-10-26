import Testing
import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

// change source-switcher：假 helper（依 --source 輸出不同來源的 snapshot）→ 真的 FeedClient → AppCoordinator → TickerDriver，
// 加上真的 SourceSwitcher 與 sources.json。不開視窗、不連網。執行：swift test --filter SourceSwitchIntegration

@MainActor
@Suite struct SourceSwitchIntegrationTests {
    func awaitCondition(_ timeout: Double = 15, _ cond: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return cond()
    }

    private func fakeHelper(_ sb: Sandbox) -> URL {
        sb.script("fake-helper.sh", """
        if [ "$1" = "--list-sources" ]; then printf 'fastbull\\njin10\\n'; exit 0; fi
        SRC=fastbull; [ "$1" = "--source" ] && SRC="$2"
        echo $$ > "\(sb.dir.path)/$SRC.pid"
        printf '{"v":1,"type":"snapshot","items":[{"source":"%s","id":"%s-2","published_at_ms":1761292800000,"text":"%s 第二則"},{"source":"%s","id":"%s-1","published_at_ms":1761292700000,"text":"%s 第一則"}]}\\n' "$SRC" "$SRC" "$SRC" "$SRC" "$SRC" "$SRC"
        while read -r _; do :; done
        """)
    }

    private func pid(_ sb: Sandbox, _ src: String) -> Int32? {
        (try? String(contentsOf: sb.dir.appendingPathComponent("\(src).pid"), encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    private func alive(_ p: Int32) -> Bool { kill(p, 0) == 0 }

    @Test func switchingReplacesEverythingAndLeavesOneHelper() async throws {
        let sb = Sandbox()
        let helper = fakeHelper(sb)
        let clock = ManualClock()
        let (driver, renderer) = makeDriver(clock: clock)
        let coord = AppCoordinator(driver: driver, log: AppLog(fileURL: nil, toStderr: false))
        let available = try #require(AvailableSources.fetch(helper: helper))
        #expect(available == ["fastbull", "jin10"])

        let client = FeedClient(config: FeedClientConfig(helperURL: helper, arguments: ["--source", "fastbull"], pidFileURL: nil),
                                onEvent: AppCoordinator.bridge(to: coord))
        let store = SourceRegistryStore(url: sb.dir.appendingPathComponent("sources.json"))
        var labels: [String?] = []
        let sw = SourceSwitcher(store: store, available: available, environmentSource: nil, pollIntervalSeconds: { 10 },
                                log: AppLog(fileURL: nil, toStderr: false),
                                actions: SourceSwitcher.Actions(beginSwitch: { coord.beginSourceSwitch() }, resetTicker: { driver.reset() },
                                                                restartHelper: { client.reconfigure(arguments: $0) }, applyLabel: { labels.append($0) }))
        #expect(sw.current == "fastbull")
        client.start()
        defer { client.shutdown() }

        #expect(await awaitCondition { coord.snapshots >= 1 })
        driver.step(); clock.t += 1; driver.step()
        #expect(driver.scheduler.latestItems.allSatisfy { $0.source == "fastbull" } && !driver.scheduler.latestItems.isEmpty)
        #expect(!renderer.track.entries.isEmpty)
        let oldPid = try #require(pid(sb, "fastbull"))
        #expect(alive(oldPid))

        // 切換
        #expect(sw.select("jin10"))
        #expect(renderer.track.entries.isEmpty, "畫面立即清空（reset 在舊 helper 結束前就做了）")
        #expect(await awaitCondition { coord.snapshots >= 2 }, "新 helper 的 snapshot 進來")
        driver.step(); clock.t += 1; driver.step()

        let items = driver.scheduler.latestItems
        #expect(items.count == 2 && items.allSatisfy { $0.source == "jin10" }, "只剩新來源的訊息：\(items.map(\.source))")
        #expect(driver.scheduler.placed.allSatisfy { $0.source == "jin10" })
        #expect(labels == ["金十數據"])
        #expect(store.load().registry.selected == "jin10")

        #expect(await awaitCondition { !alive(oldPid) }, "舊 helper 已結束")
        let newPid = try #require(pid(sb, "jin10"))
        #expect(alive(newPid) && newPid != oldPid)
    }

    @Test func staleSnapshotFromOldHelperAfterSwitchNeverReachesTheTicker() async throws {
        // 對應規格「切換後晚到的舊訊息」：用事件直接模擬，順序與 FeedClient 的序列化事件相同。
        let clock = ManualClock()
        let (driver, _) = makeDriver(clock: clock)
        let coord = AppCoordinator(driver: driver, log: AppLog(fileURL: nil, toStderr: false))
        coord.handle(.message(.snapshot([Item(source: "fastbull", id: "1", publishedAtMs: 1, text: "舊")])))
        coord.beginSourceSwitch(); driver.reset()
        coord.handle(.message(.snapshot([Item(source: "fastbull", id: "2", publishedAtMs: 2, text: "舊 helper 晚到")])))
        #expect(driver.scheduler.latestItems.isEmpty)
        coord.handle(.started(generation: 2, pid: 1))
        coord.handle(.message(.snapshot([Item(source: "jin10", id: "9", publishedAtMs: 3, text: "新")])))
        #expect(driver.scheduler.latestItems.map(\.source) == ["jin10"])
    }
}
