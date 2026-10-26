import Testing
import Foundation
import FastBullTickerCore
@testable import FastBullTickerApp

/// 來源子選單的資料模型與切換流程（change source-switcher）。全程不開視窗、不啟動 helper。
@MainActor
@Suite struct SourceSwitcherTests {
    final class Calls {
        var log: [String] = []
        var args: [[String]] = []
        var labels: [String?] = []
    }

    private func tmp() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("sources.json")
    }

    private func make(file: String? = nil, available: Set<String> = ["fastbull", "jin10"], env: String? = nil, poll: Int = 10)
        -> (SourceSwitcher, Calls, SourceRegistryStore) {
        let u = tmp()
        if let file { try! Data(file.utf8).write(to: u) }
        let store = SourceRegistryStore(url: u)
        let c = Calls()
        let actions = SourceSwitcher.Actions(
            beginSwitch: { c.log.append("begin") },
            resetTicker: { c.log.append("reset") },
            restartHelper: { c.log.append("restart"); c.args.append($0) },
            applyLabel: { c.log.append("label"); c.labels.append($0) })
        let sw = SourceSwitcher(store: store, available: available, environmentSource: env, pollIntervalSeconds: { poll },
                                log: AppLog(fileURL: nil, toStderr: false), actions: actions)
        return (sw, c, store)
    }

    // MARK: 選單模型

    @Test func menuListsSourcesWithCheckAndDisabledUnavailable() {
        let reg = SourceRegistry(selected: "jin10", sources: [SourceEntry(id: "fastbull", name: "FastBull 快訊"),
                                                              SourceEntry(id: "jin10", name: "金十數據"),
                                                              SourceEntry(id: "bloomberg", name: "彭博")])
        let items = SourceMenuModel.items(registry: reg, available: ["fastbull", "jin10"], current: "jin10", notice: nil)
        #expect(items.map(\.title) == ["FastBull 快訊", "金十數據", "彭博（尚無連接器）", "", "開啟來源設定檔…"])
        #expect(items.map(\.checked) == [false, true, false, false, false])
        #expect(items.map(\.enabled) == [true, true, false, true, true])
        #expect(items[2].kind == .source("bloomberg") && items[3].kind == .separator && items[4].kind == .openFile)
    }

    @Test func noticeIsAFirstDisabledLine() {
        let items = SourceMenuModel.items(registry: .default, available: ["fastbull"], current: "fastbull", notice: "來源設定檔無法解讀")
        #expect(items.first?.kind == .notice && items.first?.enabled == false && items.first?.title == "來源設定檔無法解讀")
    }

    // MARK: 初始來源

    @Test func startupUsesSavedSelectionWhenAvailable() {
        let (sw, _, _) = make(file: #"{"selected":"jin10","sources":[{"id":"fastbull","name":"FB"},{"id":"jin10","name":"J"}]}"#)
        #expect(sw.current == "jin10")
    }

    @Test func startupFallsBackToFastbullWhenSelectedHasNoConnector() throws {
        let file = #"{"selected":"jin10","sources":[{"id":"fastbull","name":"FB"},{"id":"jin10","name":"J"}]}"#
        let (sw, _, store) = make(file: file, available: ["fastbull"])
        #expect(sw.current == "fastbull")
        #expect(try String(contentsOf: store.url, encoding: .utf8) == file, "不修改檔案")
    }

    @Test func environmentWinsAndNeverWritesSelected() throws {
        let file = #"{"selected":"fastbull","sources":[{"id":"fastbull","name":"FB"},{"id":"jin10","name":"J"}]}"#
        let (sw, _, store) = make(file: file, env: "jin10")
        #expect(sw.current == "jin10")
        #expect(try String(contentsOf: store.url, encoding: .utf8) == file)
        #expect(store.load().registry.selected == "fastbull")
    }

    @Test func environmentSourceNotInListIsStillUsed() {
        let (sw, _, _) = make(available: ["fastbull", "bloomberg"], env: "bloomberg")
        #expect(sw.current == "bloomberg")
        #expect(sw.initialLabel == nil)
    }

    // MARK: 切換

    @Test func selectRunsFullSequenceInOrderAndPersists() {
        let (sw, c, store) = make(poll: 30)
        #expect(sw.select("jin10"))
        #expect(c.log == ["begin", "reset", "restart", "label"], "先擋舊訊息、再清畫面、再重啟 helper、最後換標籤")
        #expect(c.args == [["--source", "jin10", "--interval-ms", "30000"]], "保留目前輪詢間隔")
        #expect(c.labels == ["金十數據"])
        #expect(sw.current == "jin10")
        #expect(store.load().registry.selected == "jin10")
    }

    @Test func selectingCurrentDoesNothing() {
        let (sw, c, _) = make()
        #expect(sw.select("fastbull") == false)
        #expect(c.log.isEmpty)
    }

    @Test func unavailableOrUnknownSourcesCannotBeSelected() {
        let (sw, c, store) = make(file: #"{"selected":"fastbull","sources":[{"id":"fastbull","name":"FB"},{"id":"bloomberg","name":"彭博"}]}"#)
        #expect(sw.select("bloomberg") == false, "清單裡有但沒有連接器")
        #expect(sw.select("nope") == false, "清單裡沒有")
        #expect(c.log.isEmpty && c.args.isEmpty)
        #expect(sw.current == "fastbull")
        #expect(store.load().registry.selected == "fastbull")
    }

    @Test func sourceWithoutLabelClearsTheOverride() {
        let (sw, c, _) = make(file: #"{"selected":"fastbull","sources":[{"id":"fastbull","name":"FB","label":"快訊"},{"id":"jin10","name":"J"}]}"#)
        #expect(sw.initialLabel == "快訊")
        #expect(sw.select("jin10"))
        #expect(c.labels == [nil], "沒有 label 的來源改用 style.json 的 labelText")
    }

    @Test func menuOpenRereadsTheFile() throws {
        let (sw, _, store) = make()
        #expect(sw.menuItems().filter { if case .source = $0.kind { return true } else { return false } }.count == 2)
        try Data(#"{"selected":"fastbull","sources":[{"id":"fastbull","name":"FB"},{"id":"jin10","name":"J"},{"id":"extra1","name":"新增"}]}"#.utf8).write(to: store.url)
        let titles = sw.menuItems().map(\.title)
        #expect(titles.contains("新增（尚無連接器）"), "手動編輯後不需重啟：新來源出現（helper 沒有連接器所以停用）")
    }

    @Test func persistFailureStillSwitchesForThisRun() {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blk-\(UUID().uuidString)")
        try! Data("x".utf8).write(to: blocker)
        let c = Calls()
        let actions = SourceSwitcher.Actions(beginSwitch: {}, resetTicker: {}, restartHelper: { c.args.append($0) }, applyLabel: { c.labels.append($0) })
        let sw = SourceSwitcher(store: SourceRegistryStore(url: blocker.appendingPathComponent("sources.json")), available: ["fastbull", "jin10"],
                                environmentSource: nil, pollIntervalSeconds: { 10 }, log: AppLog(fileURL: nil, toStderr: false), actions: actions)
        #expect(sw.select("jin10"))
        #expect(sw.current == "jin10" && c.args.count == 1)
    }
}

/// 切換後晚到的舊 helper 訊息要被丟棄（change source-switcher）。
@MainActor
@Suite struct SourceSwitchDropTests {
    @Test func messagesBetweenSwitchAndNextStartAreDropped() {
        let clock = ManualClock()
        let (d, _) = makeDriver(clock: clock)
        let c = AppCoordinator(driver: d, log: AppLog(fileURL: nil, toStderr: false))
        let item = Item(source: "fastbull", id: "1", publishedAtMs: 1, text: "舊")
        c.beginSourceSwitch()
        c.handle(.message(.snapshot([item])))
        c.handle(.message(.items([item])))
        #expect(d.messagesReceived == 0 && c.snapshots == 0, "舊來源的訊息被丟棄")
        #expect(c.droppedDuringSwitch == 2)
        c.handle(.started(generation: 2, pid: 123))
        c.handle(.message(.snapshot([Item(source: "jin10", id: "9", publishedAtMs: 2, text: "新")])))
        #expect(d.messagesReceived == 1 && c.snapshots == 1)
    }

    @Test func statusAndBadLinesStillLoggedWhileSwitching() {
        let clock = ManualClock()
        let (d, _) = makeDriver(clock: clock)
        let log = AppLog(fileURL: nil, toStderr: false)
        let c = AppCoordinator(driver: d, log: log)
        c.beginSourceSwitch()
        c.handle(.exited(generation: 1, status: 15, restartIn: 0))
        #expect(log.recorded.contains { $0.contains("helper exited") })
    }
}

/// 標籤覆寫不寫 style.json，且與使用者樣式分開（change source-switcher）。
@MainActor
@Suite struct SourceLabelOverrideTests {
    @Test func overrideShowsOnLabelAndClearingRestoresStyleLabel() {
        let rig = StyleRig()
        #expect(rig.view.layoutSnapshot.labelString == "即時財經快訊")
        rig.applier.setLabelOverride("金十數據")
        #expect(rig.view.layoutSnapshot.labelString == "金十數據")
        rig.applier.setLabelOverride(nil)
        #expect(rig.view.layoutSnapshot.labelString == "即時財經快訊")
    }

    @Test func userStyleLabelChangesAreHiddenWhileOverrideIsActiveAndReturnAfter() {
        let rig = StyleRig()
        rig.applier.setLabelOverride("金十數據")
        var custom = FastBullTickerApp.TickerStyle.default; custom.labelText = "我的標籤"
        rig.applier.apply(custom, source: "file")
        #expect(rig.view.layoutSnapshot.labelString == "金十數據")
        rig.applier.setLabelOverride(nil)
        #expect(rig.view.layoutSnapshot.labelString == "我的標籤")
    }

    @Test func overrideDoesNotTouchOtherStyleFields() {
        let rig = StyleRig()
        rig.applier.setLabelOverride("金十數據")
        #expect(rig.applier.current.fontSize == FastBullTickerApp.TickerStyle.default.fontSize)
    }
}

/// 「來源」子選單的呈現層：選單展開前重新取項目、停用項目點不動、動作回呼。
@MainActor
@Suite struct SourceMenuControllerTests {
    private func items(_ current: String) -> [SourceMenuItem] {
        SourceMenuModel.items(registry: SourceRegistry(selected: current, sources: [SourceEntry(id: "fastbull", name: "FastBull 快訊"),
                                                                                    SourceEntry(id: "bloomberg", name: "彭博"),
                                                                                    SourceEntry(id: "jin10", name: "金十數據")]),
                              available: ["fastbull", "jin10"], current: current, notice: nil)
    }
    private func click(_ c: SourceMenuController, _ i: Int) {
        let it = c.menu.items[i]
        _ = it.target?.perform(it.action, with: it)
    }

    @Test func buildsMenuItemsWithCheckAndDisabled() {
        let c = SourceMenuController()
        c.provider = { self.items("jin10") }
        c.rebuild()
        #expect(c.menu.items.map(\.title) == ["FastBull 快訊", "彭博（尚無連接器）", "金十數據", "", "開啟來源設定檔…"])
        #expect(c.menu.items.map(\.state) == [.off, .off, .on, .off, .off])
        #expect(c.menu.items[1].isEnabled == false)
    }

    @Test func clickingFiresCallbacksAndDisabledDoesNothing() {
        let c = SourceMenuController()
        c.provider = { self.items("fastbull") }
        c.rebuild()
        var picked: [String] = [], opened = 0
        c.onSelect = { picked.append($0) }
        c.onOpenFile = { opened += 1 }
        click(c, 2)            // 金十數據
        click(c, 1)            // 彭博：停用，不得觸發
        click(c, 4)            // 開啟來源設定檔…
        #expect(picked == ["jin10"])
        #expect(opened == 1)
    }

    @Test func menuNeedsUpdateRebuildsFromProviderEachTime() {
        let c = SourceMenuController()
        var current = "fastbull"
        c.provider = { self.items(current) }
        c.menuNeedsUpdate(c.menu)
        #expect(c.menu.items[0].state == .on)
        current = "jin10"
        c.menuNeedsUpdate(c.menu)
        #expect(c.menu.items[0].state == .off && c.menu.items[2].state == .on)
    }

    @Test func statusMenuHostsTheSourceSubmenu() {
        let m = StatusMenuController(config: .provisional, initialAlpha: 0.9)
        let item = m.menu.items.first { $0.title == "來源" }
        #expect(item?.submenu === m.sourceMenu.menu)
    }
}
