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

// MARK: N3（task 8.1）：導覽與連結的 headless 煙霧測試。執行：swift test --filter AppSmoke
// 全程無視窗、假 opener；示範 helper 的輸出經 FeedClient 的嚴格解碼（含 url 規則）。

@MainActor
@Suite struct AppSmokeNavigationTests {
    private let cfg = ShellConfig.provisional

    private struct Rig {
        var driver: TickerDriver
        var renderer: RecordingRenderer
        var clock: ManualClock
        var opener: RecordingURLOpener
        var actions: NavigationActions
        var router: NavigationInputRouter
        var log: AppLog
    }

    private func makeRig(measurer: @escaping TextMeasurer = { Double($0.count) * 10 }) -> Rig {
        let clock = ManualClock()
        var sc = cfg.schedulerConfig(timeZone: TimeZone(secondsFromGMT: 0)!)
        sc.speed = 60
        let sched = TickerScheduler(config: sc, clock: { clock.t }, measurer: measurer)
        let renderer = RecordingRenderer()
        let driver = TickerDriver(scheduler: sched, renderer: renderer)
        let opener = RecordingURLOpener()
        let log = AppLog(fileURL: nil, toStderr: false)
        let actions = NavigationActions(driver: driver, opener: opener, log: log)
        let router = NavigationInputRouter(geometry: cfg.hitGeometry)
        router.hitItems = { [unowned driver] in driver.hitItems() }
        actions.bind(to: router)
        return Rig(driver: driver, renderer: renderer, clock: clock, opener: opener, actions: actions, router: router, log: log)
    }

    private func items(_ n: Int, url: (Int) -> String?) -> [Item] {
        (0..<n).map { Item(source: "t", id: "\(n - $0)", publishedAtMs: 1_761_292_800_000 + Int64(n - $0) * 1000, text: "訊息\(n - $0)", url: url(n - $0)) }
    }

    private func click(_ r: Rig, _ x: Double) {
        r.router.mouseDown(at: CGPoint(x: x, y: 21), button: .left, performDrag: {})
        r.router.mouseUp(at: CGPoint(x: x, y: 21), button: .left)
    }

    private func advanceUntilLinkVisible(_ r: inout Rig, minSeq: Int = 0) -> HitItem? {
        for _ in 0..<200 {
            r.clock.t += 0.25; r.driver.step()
            if let h = r.driver.hitItems().first(where: { $0.hasLinkSlot && $0.seq >= minSeq && cfg.labelWidth + $0.visualLeft + $0.width < 520 && $0.visualLeft >= 0 }) { return h }
        }
        return nil
    }

    @Test func clickingPaperclipOpensExactlyOneHttpURLAndNeverAnythingElse() throws {
        var r = makeRig()
        r.driver.receive(.snapshot(items(10) { "https://example.com/demo/\($0)" }))
        r.driver.step()
        let h = try #require(advanceUntilLinkVisible(&r, minSeq: 3))      // 不是第一則：能分辨「開了別則的連結」
        let x = Double(cfg.labelWidth) + h.visualLeft + h.width - cfg.linkSlotWidth / 2
        click(r, x)
        #expect(r.opener.opened.count == 1)
        let u = try #require(r.opener.opened.first)
        #expect(u.scheme == "https" && u.host == "example.com")
        let clicked = try #require(r.driver.placedItem(seq: h.seq))
        #expect(u.absoluteString == "https://example.com/demo/\(clicked.id)", "開啟的是被點擊那一則的連結，不是別則")
        #expect(r.actions.linkResults == [.opened])
        click(r, x)
        #expect(r.opener.opened.count == 2, "每次點擊恰一次")
    }

    @Test func itemsWithoutURLShowNoPaperclipAndCannotOpen() throws {
        var r = makeRig()
        r.driver.receive(.snapshot(items(10) { _ in nil }))
        r.driver.step()
        for _ in 0..<80 { r.clock.t += 0.25; r.driver.step() }
        #expect(r.driver.hitItems().allSatisfy { !$0.hasLinkSlot })
        #expect(r.driver.scheduler.placed.allSatisfy { !$0.hasLinkSlot })
        for x in stride(from: 150.0, to: 520.0, by: 7.0) { click(r, x) }
        #expect(r.opener.opened.isEmpty)
    }

    @Test func policyBlockedURLNeverReachesTheOpener() throws {
        var r = makeRig()
        // 協定層之外再塞一個壞網址（模擬資料被竄改）：第二道防線擋下。
        r.driver.receive(.snapshot(items(10) { _ in "javascript:alert(1)" }))
        r.driver.step()
        let h = try #require(advanceUntilLinkVisible(&r))
        click(r, Double(cfg.labelWidth) + h.visualLeft + h.width - 13)
        #expect(r.opener.opened.isEmpty)
        #expect(r.actions.linkResults == [.blockedByPolicy])
    }

    @Test func failedOpenIsNotRetried() throws {
        var r = makeRig()
        r.opener.result = false
        r.driver.receive(.snapshot(items(10) { "https://example.com/demo/\($0)" }))
        r.driver.step()
        let h = try #require(advanceUntilLinkVisible(&r))
        click(r, Double(cfg.labelWidth) + h.visualLeft + h.width - 13)
        #expect(r.opener.opened.count == 1 && r.actions.linkResults == [.openerFailed])
    }

    @Test func arrowButtonsChangePositionAndHoldTimer() throws {
        var r = makeRig()
        r.driver.receive(.snapshot(items(10) { "https://example.com/demo/\($0)" }))
        r.driver.step()
        while (r.driver.scheduler.readingPosition?.index ?? 0) < 4 { r.clock.t += 0.25; r.driver.step() }
        let before = try #require(r.driver.scheduler.readingPosition)
        click(r, 530)                                           // <
        let afterPrev = try #require(r.driver.scheduler.readingPosition)
        #expect(afterPrev.index == before.index - 1 && afterPrev.total == 10)
        #expect(r.renderer.controlStates.last?.text == "(\(before.index - 1)/10)")
        #expect(r.driver.scheduler.holdRemaining == 8)
        let off = r.driver.scheduler.scrollOffset
        r.clock.t += 5; r.driver.step()
        #expect(r.driver.scheduler.scrollOffset == off, "保持期間不捲動")
        r.clock.t += 4; r.driver.step()
        #expect(r.driver.scheduler.scrollOffset > off, "第 8 秒後恢復捲動")
        click(r, 610)                                           // >
        #expect(r.driver.scheduler.readingPosition?.index == before.index)
        #expect(r.driver.scheduler.holdRemaining == 8, "再次切換重設為 8 秒")
    }

    @Test func previousAtListStartDoesNothing() throws {
        var r = makeRig()
        r.driver.receive(.snapshot(items(10) { _ in nil }))
        r.driver.step()
        while r.driver.scheduler.readingPosition == nil { r.clock.t += 0.25; r.driver.step() }
        #expect(r.driver.scheduler.readingPosition?.index == 1)
        let off = r.driver.scheduler.scrollOffset
        click(r, 530)
        #expect(r.driver.scheduler.scrollOffset == off && r.driver.scheduler.holdRemaining == 0)
        #expect(r.actions.seekOutcomes.last == .atListStart)
    }

    @Test func pointerInsideFreezesScrollingAndLeavingResumes() {
        let r = makeRig()
        r.driver.receive(.snapshot(items(10) { _ in nil }))
        r.driver.step()
        r.clock.t += 3; r.driver.step()
        let off = r.driver.scheduler.scrollOffset
        r.driver.setPointerInside(true)
        r.clock.t += 20; r.driver.step()
        #expect(r.driver.scheduler.scrollOffset == off)
        r.driver.setPointerInside(false)
        r.clock.t += 1; r.driver.step()
        #expect(r.driver.scheduler.scrollOffset == off + 60)
    }

    @Test func lostExitEventIsRecoveredByMouseLocationReconcile() {
        let r = makeRig()
        r.driver.receive(.snapshot(items(10) { _ in nil }))
        r.driver.step()
        let frame = CGRect(x: 100, y: 800, width: 620, height: 42)
        // 追蹤區說「在內」，且實際指標也在內 → 維持暫停。
        r.driver.setPointerInside(true)
        r.driver.reconcilePointer(mouse: CGPoint(x: 300, y: 820), panelFrame: frame, panelVisible: true, clickThrough: false)
        #expect(r.driver.scheduler.isPointerInside)
        // exit 事件遺失：指標其實已在外 → 核對後恢復。
        r.driver.reconcilePointer(mouse: CGPoint(x: 5, y: 5), panelFrame: frame, panelVisible: true, clickThrough: false)
        #expect(!r.driver.scheduler.isPointerInside)
        // 指標在內但面板點穿或隱藏 → 不暫停。
        r.driver.reconcilePointer(mouse: CGPoint(x: 300, y: 820), panelFrame: frame, panelVisible: true, clickThrough: true)
        #expect(!r.driver.scheduler.isPointerInside)
        r.driver.reconcilePointer(mouse: CGPoint(x: 300, y: 820), panelFrame: frame, panelVisible: false, clickThrough: false)
        #expect(!r.driver.scheduler.isPointerInside)
        r.driver.reconcilePointer(mouse: CGPoint(x: 300, y: 820), panelFrame: frame, panelVisible: true, clickThrough: false)
        #expect(r.driver.scheduler.isPointerInside, "指標在內且面板可見：由核對補上 enter")
    }

    @Test func clickThroughDisablesRouter() {
        var r = makeRig()
        r.driver.receive(.snapshot(items(10) { "https://example.com/demo/\($0)" }))
        r.driver.step()
        while r.driver.scheduler.readingPosition == nil { r.clock.t += 0.25; r.driver.step() }
        r.router.isEnabled = false
        let off = r.driver.scheduler.scrollOffset
        click(r, 530); click(r, 610)
        #expect(r.driver.scheduler.scrollOffset == off && r.opener.opened.isEmpty)
        _ = advanceUntilLinkVisible(&r)
    }

    @Test func coordinatorCountsItemsWithURLFromDemoHelper() async throws {
        let sb = Sandbox()
        let wrapper = sb.script("wrapped-demo-url.sh", "DEMO_ITEM_INTERVAL=1 DEMO_STATUS_INTERVAL=30 exec \"\(AppSmokeTests.demoHelper.path)\"")
        let rig = makeRig()
        let coord = AppCoordinator(driver: rig.driver, log: AppLog(fileURL: nil, toStderr: false))
        let client = FeedClient(config: FeedClientConfig(helperURL: wrapper, pidFileURL: nil), onEvent: AppCoordinator.bridge(to: coord))
        client.start()
        defer { client.shutdown() }
        let ok = await AppSmokeTests().awaitCondition { coord.snapshots >= 1 && coord.itemBatches >= 3 }
        #expect(ok)
        #expect(coord.itemsReceived > 12)
        #expect(coord.itemsWithURL > 0 && coord.itemsWithURL < coord.itemsReceived, "示範訊息有些帶 url、有些故意不帶")
        #expect(coord.badLines == 0, "示範 helper 輸出（含 url）通過 Swift 端嚴格解碼")
        #expect(coord.statsLine.contains("withUrl=\(coord.itemsWithURL)"))
    }
}

// MARK: ticker-style-settings 6.1：樣式的 headless 煙霧測試。執行：swift test --filter AppSmokeStyle
// 假 helper（暫存目錄的腳本）＋暫存目錄的 StyleStore（假監看器、假時鐘）＋記錄用假 opener。
// 不開視窗、不碰真實 style.json、不開編輯器。組裝用與 AppDelegate 相同的 `StyleWiring.connect`。

@MainActor
@Suite struct AppSmokeStyleTests {
    private final class Rig {
        let env: StyleEnv
        let view: TickerView
        let driver: TickerDriver
        let applier: StyleApplier
        let menu: StyleMenuController
        let runner: StyleActionRunner
        let opener = RecordingFileOpener()
        let clock = ManualClock()
        let log: AppLog
        let coordinator: AppCoordinator

        @MainActor init(startFile: String? = nil) {
            env = StyleEnv(inline: true)
            if let startFile { env.put(startFile) }
            log = env.log
            let cfg = ShellConfig.provisional
            view = TickerView(config: cfg)
            let clock = self.clock
            let sched = TickerScheduler(config: cfg.schedulerConfig(timeZone: TimeZone(secondsFromGMT: 0)!), clock: { clock.t }, measurer: view.itemMeasurer)
            driver = TickerDriver(scheduler: sched, renderer: view)
            applier = StyleApplier(config: cfg, view: view, driver: driver, log: env.log, timeZone: TimeZone(secondsFromGMT: 0)!)
            menu = StyleMenuController()
            runner = StyleActionRunner(store: env.store, opener: opener, log: env.log)
            coordinator = AppCoordinator(driver: driver, log: env.log)
            // 與 AppDelegate 相同的順序：載入 → 啟動套用 → 接線 → 開始監看
            env.store.load()
            applier.apply(env.store.style, source: "startup")
            StyleWiring.connect(store: env.store, applier: applier, menu: menu, runner: runner)
            env.store.startWatching()
        }
        var applies: [String] { log.recorded.filter { $0.hasPrefix("style: applied") } }
    }

    @Test func startupLoadsTheFileAndAppliesThroughTheSamePath() {
        let r = Rig(startFile: ##"{"fontSize": 20, "scrollSpeed": 150, "showLabel": false, "liveBackground": "#FFE45C", "cornerRadius": 8}"##)
        #expect(r.env.store.style.fontSize == 20)
        #expect(r.applier.current == r.env.store.style && r.applies.count == 1 && r.applies[0].contains("source=startup"))
        let l = r.view.layoutSnapshot
        #expect(l.labelHidden && l.cornerRadius == 8 && Double(l.clipFrame.maxX) == 520)
        #expect(r.driver.scheduler.config.speed == 150 && r.driver.scheduler.config.viewportWidth == 520)
        #expect(r.env.listing == ["style.json"], "啟動只讀不寫（沒有 .bak、沒有暫存檔）")
    }

    @Test func noFileMeansDefaultStyleAndNothingApplied() {
        let r = Rig()
        #expect(r.env.store.style == .default && r.applier.applyCount == 0 && r.applies.isEmpty)
        #expect(r.driver.scheduler.config.speed == 90 && r.driver.scheduler.config.viewportWidth == 370)
        #expect(r.env.listing.isEmpty)
    }

    @Test func editingTheFileChangesTheEffectiveStyleAndTheViewReceivesOneApply() {
        let r = Rig(startFile: ##"{"fontSize": 16}"##)
        let before = r.applier.applyCount
        r.env.put(##"{"fontSize": 16, "liveBackground": "#1E7B3C", "liveText": "#FFFFFF", "scrollSpeed": 200}"##)
        r.env.fireAndSettle()
        #expect(r.env.store.style.scrollSpeed == 200 && r.applier.applyCount == before + 1)
        #expect(r.driver.scheduler.config.speed == 200)
        #expect(r.applies.last?.contains("source=file") == true && r.applies.last?.contains("changed=[scrollSpeed,liveBackground,liveText]") == true)
        r.env.fireAndSettle()                               // 同樣內容再來一次事件
        #expect(r.applier.applyCount == before + 1, "位元組相同不重套")
    }

    @Test func corruptFileKeepsTheEffectiveStyleAndLogsTheError() {
        let r = Rig(startFile: ##"{"fontSize": 20}"##)
        let applies = r.applier.applyCount, speed = r.driver.scheduler.config.speed
        r.env.put("{ \"fontSize\": ")
        r.env.fireAndSettle()
        #expect(r.env.store.style.fontSize == 20 && r.env.store.hasConfigProblem)
        #expect(r.applier.applyCount == applies && r.driver.scheduler.config.speed == speed && r.applier.current.fontSize == 20)
        #expect(r.env.logs.contains { $0.hasPrefix("style: error") })
        r.menu.rebuild()
        #expect(r.menu.entries.first?.id == "notice", "選單出現提示行")
        r.env.put(##"{"fontSize": 24}"##); r.env.fireAndSettle()
        #expect(r.applier.current.fontSize == 24 && !r.env.store.hasConfigProblem)
        r.menu.rebuild()
        #expect(r.menu.entries.first?.id == "fontSize")
    }

    @Test func menuChangeAppliesImmediatelyWritesBackAndIsNotReappliedFromItsOwnWrite() {
        let r = Rig(startFile: ##"{"fontSize": 16}"##)
        let before = r.applier.applyCount
        r.runner.run(.setFontSize(24))
        #expect(r.applier.current.fontSize == 24 && r.applier.applyCount == before + 1 && r.applies.last?.contains("source=menu") == true)
        r.env.settleWrite()
        #expect(String(decoding: r.env.bytes ?? Data(), as: UTF8.self).contains("\"fontSize\" : 24"))
        r.env.fireAndSettle()                               // 自己寫檔觸發的目錄事件
        #expect(r.applier.applyCount == before + 1, "自寫入不重套")
        // 選單滑桿拖動：連續多次只寫一次檔
        let writes = r.env.store.writeCount
        for v in stride(from: 100.0, through: 160.0, by: 10.0) { r.menu.rebuild(); r.menu.simulateSlider(.scrollSpeed, to: v) }
        #expect(r.driver.scheduler.config.speed == 160 && r.applier.applyCount == before + 1 + 7)
        r.env.settleWrite()
        #expect(r.env.store.writeCount == writes + 1)
    }

    @Test func menuOpenFileUsesOnlyTheRecordingOpener() {
        let r = Rig()
        r.menu.rebuild()
        let open = r.menu.menu.items.first { $0.title == "開啟樣式設定檔…" }!
        _ = open.target?.perform(open.action, with: open)
        #expect(r.opener.opened == [r.env.file] && r.opener.existedAtOpen == [true])
    }

    @Test func resetFromTheMenuRestoresDefaultsAndKeepsABackup() {
        let r = Rig(startFile: ##"{"fontSize": 24, "scrollSpeed": 250, "showLabel": false}"##)
        r.menu.rebuild()
        let reset = r.menu.menu.items.first { $0.title == "重設為預設" }!
        _ = reset.target?.perform(reset.action, with: reset)
        r.env.settleWrite()
        #expect(r.applier.current == .default && r.driver.scheduler.config.speed == 90 && r.driver.scheduler.config.viewportWidth == 370)
        #expect(r.env.bakBytes != nil && r.env.bytes == TickerStyle.default.normalizedJSON())
        #expect(!r.view.layoutSnapshot.labelHidden)
    }

    @Test func fakeHelperFeedThenStyleChangeKeepsLayersAndPositions() async throws {
        let r = Rig()
        let sb = Sandbox()
        let helper = sb.script("style-helper.sh", "printf '%s\\n' '\(Lines.snapshot)'\nwhile read -r _; do :; done")
        let client = FeedClient(config: FeedClientConfig(helperURL: helper, pidFileURL: nil), onEvent: AppCoordinator.bridge(to: r.coordinator))
        client.start()
        defer { client.shutdown() }
        #expect(await AppSmokeTests().awaitCondition { r.coordinator.snapshots >= 1 })
        r.driver.step()
        for _ in 0..<12 { r.clock.t += 0.5; r.driver.step() }
        let seqs = r.view.layerSeqs
        #expect(!seqs.isEmpty)
        let xs = seqs.map { r.view.layerTapeX(seq: $0) }
        r.runner.run(.setLivePreset(1)); r.runner.run(.setReplayCount(5)); r.runner.run(.toggleShowTime)
        #expect(r.view.layerSeqs == seqs && seqs.map { r.view.layerTapeX(seq: $0) } == xs, "樣式變更不使訊息位置跳動、不重建圖層")
        #expect(r.driver.scheduler.config.replayCount == 5 && !r.driver.scheduler.config.showTime)
        #expect(r.coordinator.badLines == 0)
    }
}
