import Testing
import AppKit
@testable import FastBullTickerApp

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// settings-gear task 8：控制項由同一份模型驅動，直接呼叫控制項 action（不開視窗、不 orderFront），
// 樣式經真實 StyleActionRunner → StyleStore（暫存目錄、假監看器）。執行：swift test --filter SettingsPanelControls
// 開機啟動一律用假服務（絕不真的註冊登入項目）。

@MainActor
private final class PanelFakeLaunchService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    var statusAfterEnable: LaunchAtLoginStatus = .enabled
    var enableError: Error?
    private(set) var enableCalls = 0, disableCalls = 0, openSettingsCalls = 0
    init(_ s: LaunchAtLoginStatus = .notRegistered) { status = s }
    func enable() throws { enableCalls += 1; if let e = enableError { throw e }; status = statusAfterEnable }
    func disable() throws { disableCalls += 1; status = .notRegistered }
    func openSystemSettings() { openSettingsCalls += 1 }
}

@MainActor
private final class Rig {
    let env = StyleEnv(inline: true)
    let opener = RecordingFileOpener()
    let service: PanelFakeLaunchService
    let content = SettingsPanelContentView()
    let controller: SettingsPanelController
    let runner: StyleActionRunner

    init(file: String? = nil, launch: LaunchAtLoginStatus = .notRegistered) {
        _ = NSApplication.shared
        if let file { env.put(file) }
        env.store.load()
        service = PanelFakeLaunchService(launch)
        runner = StyleActionRunner(store: env.store, opener: opener, log: env.log)
        controller = SettingsPanelController(content: content, launch: LaunchAtLoginController(service: service))
        let store = env.store
        controller.source = { [weak store] in (store?.style ?? .default, store?.hasConfigProblem ?? false) }
        controller.onStyleAction = { [runner] in runner.run($0) }
        env.store.onChange = { [weak controller] _, _ in MainActor.assumeIsolated { controller?.refresh() } }
        env.store.startWatching()
        controller.willOpen()
    }

    func pick(_ id: String, _ index: Int) {
        let s = content.segmented(id)!
        s.selectedSegment = index
        s.sendAction(s.action, to: s.target)
    }
    func drag(_ id: String, to v: Double) {
        let s = content.slider(id)!
        s.doubleValue = v
        s.sendAction(s.action, to: s.target)
    }
    func flip(_ id: String) {
        let sw = content.toggle(id)!
        sw.state = sw.state == .on ? .off : .on
        sw.sendAction(sw.action, to: sw.target)
    }
    func press(_ id: String) { let b = content.button(id)!; b.sendAction(b.action, to: b.target) }
}

@MainActor
@Suite struct SettingsPanelControlsTests {
    @Test func defaultControlsShowTheDefaultValues() {
        let r = Rig()
        #expect(r.content.segmented("fontSize")?.selectedSegment == 1)
        #expect(r.content.slider("scrollSpeed")?.doubleValue == 90 && r.content.valueText("scrollSpeed") == "90")
        #expect(r.content.slider("cornerRadius")?.doubleValue == 0)
        #expect(r.content.segmented("replayCount")?.selectedSegment == 1)
        #expect(r.content.segmented("liveColors")?.selectedSegment == 0)
        #expect(r.content.toggle("showTime")?.state == .on && r.content.toggle("showLabel")?.state == .on)
        #expect(r.content.slider("seekHold")?.doubleValue == 1 && r.content.valueText("seekHold") == "1.0 秒")
        #expect(r.content.segmented("pollInterval")?.selectedSegment == 0)
        #expect(r.content.toggle("launchAtLogin")?.state == .off && r.content.detailText == "未啟用")
        #expect(r.content.button("openFile") != nil && r.content.button("reset") != nil && r.content.button("close") != nil && r.content.button("quit") != nil)
    }

    @Test func controlOptionsAreTheSharedSteps() {
        let r = Rig()
        #expect(r.content.segmented("fontSize")?.segmentTitles == StyleMenuModel.fontSizeSteps.map(\.title))
        #expect(r.content.segmented("replayCount")?.segmentTitles == StyleMenuModel.replayCountSteps.map { "\($0) 則" })
        #expect(r.content.segmented("liveColors")?.segmentTitles == LiveColorPreset.all.map(\.name))
        #expect(r.content.segmented("pollInterval")?.segmentTitles == StyleRanges.pollIntervalSteps.map { "\($0) 秒" })
        #expect(r.content.slider("scrollSpeed").map { $0.minValue...$0.maxValue } == StyleRanges.scrollSpeed)
        #expect(r.content.slider("cornerRadius").map { $0.minValue...$0.maxValue } == StyleRanges.cornerRadius)
        #expect(r.content.slider("seekHold").map { $0.minValue...$0.maxValue } == StyleRanges.seekHoldSeconds)
    }

    @Test func pickingFontSizeAppliesAndWritesBack() {
        let r = Rig()
        r.pick("fontSize", 2)
        #expect(r.env.store.style.fontSize == 20)
        r.env.store.flushWrite()
        #expect(r.env.listing == ["style.json"])
        #expect(String(data: r.env.bytes ?? Data(), encoding: .utf8)?.contains("\"fontSize\" : 20") == true)
        #expect(r.content.segmented("fontSize")?.selectedSegment == 2)
    }

    @Test func everySegmentedControlChangesItsOwnField() {
        let r = Rig()
        r.pick("replayCount", 2); #expect(r.env.store.style.replayCount == 20)
        r.pick("liveColors", 2)
        #expect(r.env.store.style.liveBackground == LiveColorPreset.all[2].background && r.env.store.style.liveText == LiveColorPreset.all[2].text)
        r.pick("pollInterval", 1); #expect(r.env.store.style.pollIntervalSeconds == 30)
        r.pick("pollInterval", 2); #expect(r.env.store.style.pollIntervalSeconds == 60)
        #expect(r.env.store.style.replayBackground == TickerStyle.default.replayBackground, "即時配色不動重播配色")
    }

    @Test func slidersApplyContinuouslyAndClamp() {
        let r = Rig()
        r.drag("scrollSpeed", to: 150.4); #expect(r.env.store.style.scrollSpeed == 150)
        r.drag("scrollSpeed", to: 151.2); #expect(r.env.store.style.scrollSpeed == 151)
        r.drag("cornerRadius", to: 12); #expect(r.env.store.style.cornerRadius == 12)
        r.drag("seekHold", to: 3.3)
        #expect(r.env.store.style.seekHoldSeconds == 3.5)
        #expect(r.content.valueText("seekHold") == "3.5 秒")
        #expect(r.content.valueText("scrollSpeed") == "151")
    }

    @Test func togglesFlipTheStyleFlags() {
        let r = Rig()
        r.flip("showTime"); #expect(!r.env.store.style.showTime && r.content.toggle("showTime")?.state == .off)
        r.flip("showLabel"); #expect(!r.env.store.style.showLabel)
        r.flip("showTime"); #expect(r.env.store.style.showTime)
    }

    @Test func draggingASliderKeepsTheSameControlInstance() {
        let r = Rig()
        let before = r.content.slider("scrollSpeed")
        let builds = r.content.rebuildCount
        r.drag("scrollSpeed", to: 100); r.drag("scrollSpeed", to: 101); r.drag("scrollSpeed", to: 102)
        #expect(r.content.slider("scrollSpeed") === before, "拖動期間不重建控制項（否則滑桿會在手上被換掉）")
        #expect(r.content.rebuildCount == builds)
        #expect(r.content.slider("scrollSpeed")?.doubleValue == 102)
    }

    @Test func sliderKnobIsNotSnappedWhileDragging() {
        let r = Rig()
        r.drag("scrollSpeed", to: 120.4)
        #expect(r.content.slider("scrollSpeed")?.doubleValue == 120.4, "套用值 120 與旋鈕位置差 < 半格：不回彈")
    }

    @Test func hotReloadRefreshesTheOpenPanel() {
        let r = Rig(file: ##"{"fontSize": 16}"##)
        #expect(r.content.segmented("fontSize")?.selectedSegment == 1)
        r.env.put(##"{"fontSize": 20, "scrollSpeed": 200, "showLabel": false, "seekHoldSeconds": 4, "pollIntervalSeconds": 60}"##)
        r.env.fireAndSettle()
        #expect(r.content.segmented("fontSize")?.selectedSegment == 2, "字級控制項顯示「大」")
        #expect(r.content.slider("scrollSpeed")?.doubleValue == 200 && r.content.toggle("showLabel")?.state == .off)
        #expect(r.content.slider("seekHold")?.doubleValue == 4 && r.content.segmented("pollInterval")?.selectedSegment == 2)
    }

    @Test func resetRestoresDefaultsAndMakesABackup() {
        let r = Rig(file: ##"{"fontSize": 24, "scrollSpeed": 250}"##)
        #expect(r.content.segmented("fontSize")?.selectedSegment == 3)
        r.press("reset")
        #expect(r.env.store.style == .default)
        #expect(r.content.segmented("fontSize")?.selectedSegment == 1 && r.content.slider("scrollSpeed")?.doubleValue == 90)
        #expect(r.env.listing.contains("style.json.bak"), "重設前備份為 .bak：\(r.env.listing)")
    }

    @Test func openFileGoesThroughTheInjectedOpenerOnly() {
        let r = Rig()
        r.press("openFile")
        #expect(r.opener.opened.count == 1 && r.opener.opened.first == r.env.store.fileURL)
        #expect(r.opener.existedAtOpen == [true], "先建立再開啟")
    }

    @Test func closeButtonReportsClose() {
        let r = Rig()
        var closed = 0
        r.controller.onClose = { closed += 1 }
        r.press("close")
        #expect(closed == 1)
    }

    @Test func quitButtonReportsQuitAppAndDoesNotJustClose() {
        let r = Rig()
        var quits = 0, closed = 0
        r.controller.onQuitApp = { quits += 1 }
        r.controller.onClose = { closed += 1 }
        r.press("quit")
        #expect(quits == 1 && closed == 0, "「結束程式」不是「關閉」")
        r.press("close")
        #expect(quits == 1 && closed == 1, "「關閉」維持只關閉設定面板")
    }

    @Test func quitIsRightBeforeCloseAndAllButtonsFitInsideThePanel() {
        let r = Rig()
        let q = r.content.button("quit")!, c = r.content.button("close")!
        #expect(q.title == "結束程式" && c.title == "關閉")
        let row = q.superview as? NSStackView
        #expect(row != nil && row === c.superview, "「結束程式」與「關閉」同一列")
        let views = row?.arrangedSubviews ?? []
        #expect(views.firstIndex(of: q) == (views.firstIndex(of: c) ?? 0) - 1, "結束程式緊接在關閉之前")
        _ = r.content.contentSize
        for b in ["openFile", "reset", "quit", "close"].compactMap({ r.content.button($0) }) {
            let f = b.convert(b.bounds, to: r.content)
            #expect(f.minX >= 0 && f.maxX <= SettingsPanelContentView.panelWidth, "\(b.title) 超出面板：\(f)")
        }
    }

    @Test func configProblemShowsTheNoticeAndClearsWhenFixed() {
        let r = Rig(file: ##"{"fontSize": 20}"##)
        #expect(r.content.noticeText == nil)
        r.env.put("{ \"fontSize\": "); r.env.fireAndSettle()
        r.controller.refresh()
        #expect(r.env.store.hasConfigProblem && r.content.noticeText == "設定檔有誤，沿用上次有效值")
        #expect(r.content.segmented("fontSize")?.selectedSegment == 2, "沿用上次有效值")
        r.env.put(##"{"fontSize": 24}"##); r.env.fireAndSettle()
        #expect(r.content.noticeText == nil && r.content.segmented("fontSize")?.selectedSegment == 3)
    }

    // MARK: 開機自動啟動

    @Test func launchSwitchGoesThroughControllerAndNeverTouchesTheStyleFile() {
        let r = Rig()
        r.flip("launchAtLogin")
        #expect(r.service.enableCalls == 1 && r.content.toggle("launchAtLogin")?.state == .on && r.content.detailText == "已啟用")
        r.env.store.flushWrite()
        #expect(r.env.listing.isEmpty && r.env.store.writeCount == 0 && r.env.store.style == .default, "style.json 不變（也不被建立）")
        r.flip("launchAtLogin")
        #expect(r.service.disableCalls == 1 && r.content.toggle("launchAtLogin")?.state == .off)
    }

    @Test func requiresApprovalShowsDetailAndOpenSettingsButton() {
        let r = Rig()
        r.service.statusAfterEnable = .requiresApproval
        #expect(r.content.button("openLoginSettings") == nil)
        r.flip("launchAtLogin")
        #expect(r.content.toggle("launchAtLogin")?.state == .off, "開關位置以實際狀態為準，不是使用者按了什麼")
        #expect(r.content.detailText?.contains("核准") == true)
        r.press("openLoginSettings")
        #expect(r.service.openSettingsCalls == 1)
    }

    @Test func enableErrorIsShownVerbatim() {
        let r = Rig()
        r.service.enableError = NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        r.flip("launchAtLogin")
        #expect(r.content.toggle("launchAtLogin")?.state == .off && r.content.detailText == "失敗：Operation not permitted")
    }

    @Test func openingThePanelRereadsTheRealStatus() {
        let r = Rig()
        #expect(r.content.toggle("launchAtLogin")?.state == .off)
        r.service.status = .enabled                 // 使用者在系統設定中自己打開了
        r.controller.willOpen()
        #expect(r.content.toggle("launchAtLogin")?.state == .on && r.content.detailText == "已啟用")
        r.service.status = .notFound
        r.controller.willOpen()
        #expect(r.content.toggle("launchAtLogin")?.state == .off && r.content.detailText?.contains("找不到") == true)
    }

    @Test func approvalButtonAppearsAndDisappearsWithStatus() {
        let r = Rig(launch: .requiresApproval)
        #expect(r.content.button("openLoginSettings") != nil)
        r.service.status = .enabled
        r.controller.willOpen()
        #expect(r.content.button("openLoginSettings") == nil)
    }
}
