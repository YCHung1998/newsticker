import Testing
import AppKit
@testable import FastBullTickerApp

// ticker-style-settings 5.1：「樣式」子選單。執行：swift test --filter StyleMenu
// 項目清單與動作用純資料的 StyleMenuModel 測；NSMenu 層只做組裝（不顯示、不建立 NSStatusItem、不開視窗）；
// 開啟檔案只經假 opener（絕不呼叫真實的 NSWorkspace）；檔案全在暫存目錄（StyleEnv，見 StyleStoreTests.swift）。

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

/// 記錄用假 opener：自動測試只能用它。
@MainActor
final class RecordingFileOpener: FileOpener {
    private(set) var opened: [URL] = []
    var result = true
    /// 開啟當下檔案是否存在（驗證「先建立再開啟」的順序）。
    private(set) var existedAtOpen: [Bool] = []
    func open(_ url: URL) -> Bool {
        opened.append(url)
        existedAtOpen.append(FileManager.default.fileExists(atPath: url.path))
        return result
    }
}

@Suite struct StyleMenuModelTests {
    private func ids(_ s: TickerStyle = .default, problem: Bool = false) -> [String] { StyleMenuModel.entries(for: s, hasConfigProblem: problem).map(\.id) }

    @Test func defaultEntriesAreInSpecOrderWithoutNotice() {
        #expect(ids() == ["fontSize", "scrollSpeed", "replayCount", "cornerRadius", "liveColors", "separator1", "showTime", "showLabel", "separator2", "openFile", "reset"])
        let titles = StyleMenuModel.entries(for: .default).filter { $0.kind != .separator }.map(\.title)
        #expect(titles == ["字級", "捲動速度", "訊息量", "圓角", "即時配色", "顯示時間", "顯示標籤", "開啟樣式設定檔…", "重設為預設"])
        #expect(StyleMenuModel.entries(for: .default).map(\.kind) == [.submenu, .slider, .submenu, .slider, .submenu, .separator, .toggle, .toggle, .separator, .action, .action])
    }

    @Test func configProblemAddsADisabledNoticeFirst() {
        let e = StyleMenuModel.entries(for: .default, hasConfigProblem: true)
        #expect(e.first?.id == "notice" && e.first?.title == "設定檔有誤，沿用上次有效值" && e.first?.enabled == false && e.first?.kind == .notice)
        #expect(Array(ids(problem: true).dropFirst()) == ids())
    }

    @Test func fontSizeStepsAndCheckmarks() throws {
        #expect(StyleMenuModel.fontSizeSteps.map(\.value) == [13, 16, 20, 24])
        #expect(StyleMenuModel.fontSizeSteps.allSatisfy { StyleRanges.fontSize.contains($0.value) })
        func checked(_ fs: Double) throws -> [Bool] {
            var s = TickerStyle.default; s.fontSize = fs
            return try #require(StyleMenuModel.entries(for: s).first { $0.id == "fontSize" }).children.map(\.checked)
        }
        #expect(try checked(16) == [false, true, false, false])
        #expect(try checked(20) == [false, false, true, false])
        #expect(try checked(17) == [false, false, false, false], "手動編輯成 17：四個檔位都不勾")
        let titles = try #require(StyleMenuModel.entries(for: .default).first { $0.id == "fontSize" }).children.map(\.title)
        #expect(titles == ["小（13）", "標準（16）", "大（20）", "特大（24）"])
    }

    @Test func replayCountStepsAndCheckmarks() throws {
        #expect(StyleMenuModel.replayCountSteps == [5, 10, 20])
        #expect(StyleMenuModel.replayCountSteps.allSatisfy { StyleRanges.replayCount.contains($0) })
        var s = TickerStyle.default; s.replayCount = 20
        let e = try #require(StyleMenuModel.entries(for: s).first { $0.id == "replayCount" })
        #expect(e.children.map(\.title) == ["5 則", "10 則", "20 則"] && e.children.map(\.checked) == [false, false, true])
        s.replayCount = 7
        #expect(try #require(StyleMenuModel.entries(for: s).first { $0.id == "replayCount" }).children.allSatisfy { !$0.checked })
    }

    @Test func slidersCarryTheValidRangesAndCurrentValues() throws {
        var s = TickerStyle.default; s.scrollSpeed = 130; s.cornerRadius = 9
        let all = StyleMenuModel.entries(for: s)
        let speed = try #require(all.first { $0.id == "scrollSpeed" }?.slider), corner = try #require(all.first { $0.id == "cornerRadius" }?.slider)
        #expect(speed.range == StyleRanges.scrollSpeed && speed.range == 20...300 && speed.value == 130)
        #expect(corner.range == StyleRanges.cornerRadius && corner.range == 0...21 && corner.value == 9)
        #expect(speed.action(for: 299.6) == .setScrollSpeed(300) && corner.action(for: 10.4) == .setCornerRadius(10))
    }

    @Test func liveColorPresetsAreThreeReadableAndCheckedOnExactMatch() throws {
        #expect(LiveColorPreset.all.count == 3)
        #expect(LiveColorPreset.all.allSatisfy { ContrastRatio.ratio($0.background, $0.text) >= 4.5 })
        #expect(LiveColorPreset.all.map { $0.background.hex + "/" + $0.text.hex } == ["#FFFFFF/#000000", "#FFE45C/#000000", "#1E7B3C/#FFFFFF"])
        func checks(_ s: TickerStyle) throws -> [Bool] { try #require(StyleMenuModel.entries(for: s).first { $0.id == "liveColors" }).children.map(\.checked) }
        #expect(try checks(.default) == [true, false, false])
        var s = TickerStyle.default; s.liveBackground = RGBColor(hex: "#FFE45C")!        // 文字仍是預設黑 → 與黃底黑字相符
        #expect(try checks(s) == [false, true, false])
        s.liveText = RGBColor(hex: "#111111")!
        #expect(try checks(s) == [false, false, false], "只有背景相符不算（兩個色碼都要相同）")
    }

    @Test func togglesReflectCurrentStyle() {
        var s = TickerStyle.default; s.showTime = false
        let e = StyleMenuModel.entries(for: s)
        #expect(e.first { $0.id == "showTime" }?.checked == false && e.first { $0.id == "showLabel" }?.checked == true)
    }

    @Test func actionsChangeOnlyTheirOwnFieldsAndStayValidAfterClamp() {
        var s = TickerStyle.default
        StyleMenuModel.apply(.setFontSize(20), to: &s)
        #expect(s.fontSize == 20 && s == { var d = TickerStyle.default; d.fontSize = 20; return d }())
        s = .default; StyleMenuModel.apply(.setLivePreset(1), to: &s)
        #expect(s.liveBackground.hex == "#FFE45C" && s.liveText.hex == "#000000")
        #expect(s.replayBackground == TickerStyle.default.replayBackground && s.replayText == TickerStyle.default.replayText, "不動重播配色")
        s = .default; StyleMenuModel.apply(.toggleShowLabel, to: &s); #expect(!s.showLabel && s.showTime)
        StyleMenuModel.apply(.toggleShowTime, to: &s); #expect(!s.showTime)
        #expect(!StyleMenuModel.apply(.openFile, to: &s) && !StyleMenuModel.apply(.resetToDefault, to: &s))
        #expect(!StyleMenuModel.apply(.setLivePreset(99), to: &s))
        for a in [StyleMenuAction.setFontSize(999), .setReplayCount(0), .setScrollSpeed(-5), .setCornerRadius(500)] {
            var t = TickerStyle.default; StyleMenuModel.apply(a, to: &t)
            #expect(t.clamped().isValid, "\(a)")
        }
    }
}

@MainActor
@Suite struct StyleMenuControllerTests {
    @Test func buildsMenuFromModelAndMirrorsCheckmarks() {
        let c = StyleMenuController()
        var s = TickerStyle.default; s.fontSize = 24; s.showLabel = false
        c.source = { (s, false) }
        c.rebuild()
        #expect(c.menu.items.map(\.title).filter { !$0.isEmpty }.contains("字級") && c.menu.items.map(\.title).contains("重設為預設"))
        let font = c.menu.items.first { $0.title == "字級" }!.submenu!
        #expect(font.items.map(\.state) == [.off, .off, .off, .on])
        #expect(c.menu.items.first { $0.title == "顯示標籤" }?.state == .off && c.menu.items.first { $0.title == "顯示時間" }?.state == .on)
        #expect(c.menu.items.filter(\.isSeparatorItem).count == 2)
        #expect(c.menu.items.filter { $0.view != nil }.count == 2, "兩個滑桿")
    }

    @Test func menuNeedsUpdateRefreshesFromTheLatestStyle() {
        let c = StyleMenuController()
        var s = TickerStyle.default
        c.source = { (s, false) }
        c.rebuild()
        #expect(c.menu.items.first { $0.title == "字級" }!.submenu!.items.map(\.state) == [.off, .on, .off, .off])
        s.fontSize = 20                                   // 例如熱重載後
        c.menuNeedsUpdate(c.menu)
        #expect(c.menu.items.first { $0.title == "字級" }!.submenu!.items.map(\.state) == [.off, .off, .on, .off])
    }

    @Test func configProblemNoticeRowIsDisabledAndAppearsFirst() {
        let c = StyleMenuController()
        c.source = { (.default, true) }
        c.rebuild()
        #expect(c.menu.items.first?.title == "設定檔有誤，沿用上次有效值" && c.menu.items.first?.isEnabled == false)
    }

    @Test func actionItemsAndSlidersCallOnAction() throws {
        let c = StyleMenuController()
        var got: [StyleMenuAction] = []
        c.onAction = { got.append($0) }
        c.rebuild()
        let large = c.menu.items.first { $0.title == "字級" }!.submenu!.items[2]
        _ = large.target?.perform(large.action, with: large)
        let reset = c.menu.items.first { $0.title == "重設為預設" }!
        _ = reset.target?.perform(reset.action, with: reset)
        c.simulateSlider(.scrollSpeed, to: 300)
        c.simulateSlider(.cornerRadius, to: 10.2)
        #expect(got == [.setFontSize(20), .resetToDefault, .setScrollSpeed(300), .setCornerRadius(10)])
        #expect(c.sliderRange(.scrollSpeed) == 20...300 && c.sliderRange(.cornerRadius) == 0...21)
        #expect(c.valueText(.scrollSpeed) == "300" && c.valueText(.cornerRadius) == "10", "滑桿旁顯示整數值")
    }

    @Test func buildingAndRunningEveryActionCreatesNoWindowOrAlert() {
        _ = NSApplication.shared
        let before = NSApp.windows.count
        let c = StyleMenuController()
        c.rebuild()
        for it in c.menu.items {
            if let sub = it.submenu { for s in sub.items where s.action != nil { _ = s.target?.perform(s.action, with: s) } }
        }
        #expect(NSApp.windows.count == before)
    }

    @Test func statusMenuHasFiveItemsAndStyleSubmenuIsTheSharedOne() {
        let m = StatusMenuController(config: .provisional, initialAlpha: 0.9)
        #expect(m.items.map(\.kind) == [.opacity, .toggleVisibility, .clickThrough, .style, .quit])
        #expect(m.items.map(\.title) == ["透明度", "隱藏帶子", "點穿模式", "樣式", "結束"])
        let styleItem = m.menu.items.first { $0.title == "樣式" }
        #expect(styleItem?.submenu === m.styleMenu.menu)
        #expect(m.menu.items.last?.title == "結束" && m.menu.items.firstIndex { $0.title == "樣式" }! < m.menu.items.firstIndex { $0.isSeparatorItem }!)
    }
}

@MainActor
@Suite struct StyleActionRunnerTests {
    private func rig(_ json: String? = nil) -> (StyleEnv, StyleActionRunner, RecordingFileOpener) {
        let e = StyleEnv()
        if let json { e.put(json) }
        e.store.start()
        let o = RecordingFileOpener()
        return (e, StyleActionRunner(store: e.store, opener: o, log: e.log), o)
    }

    @Test func menuActionUpdatesStyleNotifiesAndWritesBackAfterDebounce() {
        let (e, r, o) = rig()
        r.run(.setFontSize(20))
        #expect(e.store.style.fontSize == 20 && e.changes.sources == [.menu])
        #expect(e.bytes == nil, "debounce 內還沒寫")
        e.settleWrite()
        #expect(String(decoding: e.bytes ?? Data(), as: UTF8.self).contains("\"fontSize\" : 20"))
        #expect(o.opened.isEmpty)
    }

    @Test func menuLivePresetWritesBothLiveColorsOnly() {
        let (e, r, _) = rig(##"{"replayBackground": "#102030"}"##)
        r.run(.setLivePreset(1)); e.settleWrite()
        let s = e.store.style
        #expect(s.liveBackground.hex == "#FFE45C" && s.liveText.hex == "#000000" && s.replayBackground.hex == "#102030")
    }

    @Test func openFileWhenMissingCreatesItFirstThenOpensExactlyOnce() {
        let (e, r, o) = rig()
        #expect(e.bytes == nil)
        r.run(.openFile)
        #expect(o.opened == [e.file] && o.existedAtOpen == [true], "先建立檔案，再呼叫 opener 一次，參數是該檔案")
        #expect(e.bytes == TickerStyle.default.normalizedJSON(), "內容是目前生效樣式的正規化格式")
        #expect(e.file.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    @Test func openFileWhenPresentDoesNotRewriteIt() {
        let original = ##"{"fontSize": 22, "myNote": "keep"}"##
        let (e, r, o) = rig(original)
        let writes = e.store.writeCount
        r.run(.openFile)
        #expect(o.opened == [e.file] && e.bytes == Data(original.utf8) && e.store.writeCount == writes)
    }

    @Test func openFileOpenerFailureIsOnlyLogged() {
        let (e, r, o) = rig()
        o.result = false
        r.run(.openFile)
        #expect(o.opened.count == 1 && e.logs.contains { $0.contains("open file requested ok=false") })
    }

    @Test func resetBacksUpThenWritesDefault() {
        let original = ##"{"fontSize": 24, "liveBackground": "#FFE45C"}"##
        let (e, r, _) = rig(original)
        r.run(.resetToDefault); e.settleWrite()
        #expect(e.store.style == .default && e.bakBytes == Data(original.utf8) && e.bytes == TickerStyle.default.normalizedJSON())
    }

    @Test func hotReloadedValuesAreVisibleToTheMenuOnNextOpen() {
        let (e, _, _) = rig()
        let c = StyleMenuController()
        c.source = { [store = e.store] in (store.style, store.hasConfigProblem) }
        e.put(##"{"fontSize": 20}"##); e.fireAndSettle()
        c.menuNeedsUpdate(c.menu)
        #expect(c.menu.items.first { $0.title == "字級" }!.submenu!.items.map(\.state) == [.off, .off, .on, .off])
        e.put("{ broken"); e.fireAndSettle()
        c.menuNeedsUpdate(c.menu)
        #expect(c.menu.items.first?.title == "設定檔有誤，沿用上次有效值", "損壞的檔案：提示行出現，樣式仍是上次有效值")
        #expect(c.menu.items.first { $0.title == "字級" }!.submenu!.items.map(\.state) == [.off, .off, .on, .off])
    }
}

@Suite struct StyleMenuGuardTests {
    @Test func onlyTheTwoWorkspaceOpenerFilesMayCallTheRealOpen() throws {
        let root = try #require(OpenerGuard.repoRoot())
        let withOpen = OpenerGuard.swiftFiles(under: root.appendingPathComponent("Sources")).filter {
            ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains(OpenerGuard.forbidden)
        }.map(\.lastPathComponent).sorted()
        #expect(withOpen == ["WorkspaceFileOpener.swift", "WorkspaceURLOpener.swift"])
        #expect(OpenerGuard.violations(root: root).isEmpty)
        #expect(OpenerGuard.isAllowedOpenerFile(URL(fileURLWithPath: "/x/WorkspaceFileOpener.swift")))
        #expect(!OpenerGuard.isAllowedOpenerFile(URL(fileURLWithPath: "/x/StyleMenuController.swift")))
    }

    @Test func styleMenuSourcesNeverCreateWindowsAlertsOrActivate() throws {
        let root = try #require(OpenerGuard.repoRoot())
        for name in ["StyleMenuController.swift", "StyleMenuModel.swift", "StyleApplier.swift", "WorkspaceFileOpener.swift"] {
            let raw = try String(contentsOf: root.appendingPathComponent("Sources/FastBullTickerApp/\(name)"), encoding: .utf8)
            let s = raw.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")   // 只掃程式碼，不掃註解
            for bad in ["NSAlert", "NSWindow(", "NSPanel(", "NSApp.activate", "makeKeyAndOrderFront", "runModal", "beginSheet"] {
                #expect(!s.contains(bad), "\(name) 不得包含 \(bad)")
            }
        }
        #expect(OpenerGuard.activationViolations(root: root).isEmpty)
    }

    @Test func testsNeverCallTheRealOpen() throws {
        let root = try #require(OpenerGuard.repoRoot())
        #expect(OpenerGuard.violations(root: root).filter { $0.hasPrefix("Tests:") }.isEmpty)
    }
}
