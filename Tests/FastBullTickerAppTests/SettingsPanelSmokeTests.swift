import Testing
import AppKit
@testable import FastBullTickerApp
import FastBullTickerCore

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// settings-gear task 10：headless 組裝煙霧測試。用與 AppDelegate 相同的 `SettingsPanelWiring.assemble`／`StyleWiring.connect`，
// 假視窗、假監看器、假開機啟動服務、暫存目錄的 StyleStore、記錄用假 opener；輪詢路徑用假 helper 腳本＋真 FeedClient。
// 不開視窗、不裝全域監看器、不寫真實 style.json、不開編輯器、不註冊登入項目。執行：swift test --filter SettingsPanelSmoke

@MainActor
private final class SmokeWindow: SettingsPanelWindowing {
    var panelSize = CGSize(width: 330, height: 560)
    private(set) var frame: CGRect = .zero
    private(set) var shown = 0, hidden = 0
    func show(at frame: CGRect) { self.frame = frame; shown += 1 }
    func hide() { hidden += 1 }
}
@MainActor
private final class SmokeMonitor: MouseDownMonitoring {
    private(set) var installs = 0, removes = 0
    private(set) var isInstalled = false
    func install(_ handler: @escaping (CGPoint) -> Void) { installs += 1; isInstalled = true }
    func remove() { removes += 1; isInstalled = false }
}
@MainActor
private final class SmokeLaunch: LaunchAtLoginService {
    var status: LaunchAtLoginStatus = .notRegistered
    private(set) var enables = 0
    func enable() throws { enables += 1; status = .enabled }
    func disable() throws { status = .notRegistered }
    func openSystemSettings() {}
}

@MainActor
@Suite struct SettingsPanelSmokeTests {
    @MainActor private final class Rig {
        let env = StyleEnv(inline: true)
        let view: TickerView, driver: TickerDriver, applier: StyleApplier, menu = StyleMenuController(), runner: StyleActionRunner
        let opener = RecordingFileOpener()
        let clock = ManualClock()
        let window = SmokeWindow(), monitor = SmokeMonitor(), launch = SmokeLaunch()
        let content = SettingsPanelContentView()
        let wiring: SettingsPanelWiring

        init() {
            _ = NSApplication.shared
            let cfg = ShellConfig.provisional
            let utc = TimeZone(secondsFromGMT: 0)!
            view = TickerView(config: cfg)
            let clock = self.clock
            driver = TickerDriver(scheduler: TickerScheduler(config: cfg.schedulerConfig(timeZone: utc), clock: { clock.t }, measurer: view.itemMeasurer), renderer: view)
            applier = StyleApplier(config: cfg, view: view, driver: driver, log: env.log, timeZone: utc)
            runner = StyleActionRunner(store: env.store, opener: opener, log: env.log)
            env.store.load()
            applier.apply(env.store.style, source: "startup")
            let tickerFrame = CGRect(x: 100, y: 500, width: 648, height: 42)
            wiring = SettingsPanelWiring.assemble(content: content, window: window, monitor: monitor, launch: launch, store: env.store, runner: runner, view: view,
                                                  tickerFrame: { tickerFrame }, visibleFrame: { CGRect(x: 0, y: 0, width: 1440, height: 900) })
            StyleWiring.connect(store: env.store, applier: applier, menu: menu, runner: runner, onApplied: wiring.refreshIfOpen)
            env.store.startWatching()
        }
        func clickGear() {
            func ev(_ t: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: CGPoint(x: 14, y: 21), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: ev(.leftMouseDown)); view.mouseUp(with: ev(.leftMouseUp))
        }
        var applies: [String] { env.log.recorded.filter { $0.hasPrefix("style: applied") } }
    }

    @Test func gearOpensThePanelAndAStyleChangeReachesTheViewOnceAndTheFile() throws {
        let r = Rig()
        r.clickGear()
        #expect(r.wiring.coordinator.isOpen && r.window.shown == 1 && r.monitor.installs == 1)
        let before = r.applier.applyCount
        let seg = try #require(r.content.segmented("fontSize"))
        seg.selectedSegment = 2; seg.sendAction(seg.action, to: seg.target)       // 「大」
        #expect(r.env.store.style.fontSize == 20)
        #expect(r.applier.applyCount == before + 1, "畫面端只收到一次套用")
        #expect(r.applies.last?.contains("source=menu") == true && r.applies.last?.contains("changed=[fontSize]") == true)
        r.env.store.flushWrite()
        #expect(r.env.listing == ["style.json"] && String(data: r.env.bytes ?? Data(), encoding: .utf8)?.contains("\"fontSize\" : 20") == true)
    }

    @Test func menuChangeAndFileEditRefreshTheOpenPanel() {
        let r = Rig()
        r.clickGear()
        r.runner.run(.setFontSize(24))                                            // 選單列路徑
        #expect(r.content.segmented("fontSize")?.selectedSegment == 3)
        r.env.put(##"{"fontSize": 13, "pollIntervalSeconds": 60}"##); r.env.fireAndSettle()   // 熱重載
        #expect(r.content.segmented("fontSize")?.selectedSegment == 0 && r.content.segmented("pollInterval")?.selectedSegment == 2)
    }

    @Test func closedPanelIsNotRefreshedByStyleChanges() {
        let r = Rig()
        r.clickGear(); r.clickGear()
        #expect(!r.wiring.coordinator.isOpen && r.monitor.removes == 1)
        let builds = r.content.rebuildCount
        r.runner.run(.setFontSize(24))
        #expect(r.content.segmented("fontSize")?.selectedSegment == 1, "關閉時不更新；下次開啟才整理")
        #expect(r.content.rebuildCount == builds)
        r.clickGear()
        #expect(r.content.segmented("fontSize")?.selectedSegment == 3, "再開啟時顯示目前生效值")
    }

    @Test func launchAtLoginSwitchDoesNotTouchStyleOrApplyCount() throws {
        let r = Rig()
        r.clickGear()
        let before = r.applier.applyCount
        let sw = try #require(r.content.toggle("launchAtLogin"))
        sw.state = .on; sw.sendAction(sw.action, to: sw.target)
        #expect(r.launch.enables == 1 && r.applier.applyCount == before)
        r.env.store.flushWrite()
        #expect(r.env.listing.isEmpty)
    }

    @Test func pressingTheTapeWhileOpenClosesThePanelAndRemovesTheMonitor() {
        let r = Rig()
        r.clickGear()
        let nextX = Double(r.view.layoutSnapshot.nextFrame.midX)
        r.view.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: nextX, y: 21), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        #expect(!r.wiring.coordinator.isOpen && r.monitor.removes == 1 && !r.monitor.isInstalled)
    }

    @Test func panelCloseButtonClosesIt() throws {
        let r = Rig()
        r.clickGear()
        let b = try #require(r.content.button("close"))
        b.sendAction(b.action, to: b.target)
        #expect(!r.wiring.coordinator.isOpen && r.window.hidden == 1 && !r.monitor.isInstalled)
    }

    @Test func openFileButtonUsesOnlyTheInjectedOpener() throws {
        let r = Rig()
        r.clickGear()
        let b = try #require(r.content.button("openFile"))
        b.sendAction(b.action, to: b.target)
        #expect(r.opener.opened == [r.env.store.fileURL])
    }

    // MARK: 輪詢間隔：面板 → StyleApplier → FeedClient 重啟（假 helper 腳本）

    @Test func changingPollIntervalInThePanelRestartsTheFakeHelperExactlyOnce() async throws {
        let r = Rig()
        let sb = Sandbox()
        let args = sb.dir.appendingPathComponent("args.log")
        let helper = sb.script("snapshot-on-start", "echo \"$*\" >> \"\(args.path)\"\necho '\(Lines.snapshot)'\nexec cat >/dev/null")
        let coord = AppCoordinator(driver: r.driver, log: AppLog(fileURL: nil, toStderr: false))
        let client = FeedClient(config: FeedClientConfig(helperURL: helper, arguments: FeedClientConfig.helperArguments(pollIntervalSeconds: r.env.store.style.pollIntervalSeconds), pidFileURL: nil),
                                onEvent: AppCoordinator.bridge(to: coord))
        r.applier.onPollIntervalChange = { client.reconfigure(arguments: FeedClientConfig.helperArguments(pollIntervalSeconds: $0)) }
        client.start()
        defer { client.shutdown() }
        func lines() -> [String] { ((try? String(contentsOf: args, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) }
        #expect(await AppSmokeTests().awaitCondition(10) { coord.helperStarts >= 1 && lines().count == 1 })

        r.clickGear()
        let seg = try #require(r.content.segmented("pollInterval"))
        seg.selectedSegment = 1; seg.sendAction(seg.action, to: seg.target)       // 30 秒
        #expect(r.env.store.style.pollIntervalSeconds == 30)
        #expect(await AppSmokeTests().awaitCondition(10) { coord.helperStarts >= 2 && lines().count == 2 })
        #expect(lines() == ["", "--interval-ms 30000"])
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(coord.helperStarts == 2 && lines().count == 2, "只重啟一次")
        r.runner.run(.setFontSize(20))                                            // 其他欄位變更不重啟
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(lines().count == 2)
    }
}
