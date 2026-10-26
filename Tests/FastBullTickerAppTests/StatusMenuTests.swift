import Testing
import AppKit
@testable import FastBullTickerApp

// task 3.3：StatusMenu。執行：swift test --filter StatusMenu（不建立 NSStatusItem、不顯示選單）

@MainActor
@Suite struct StatusMenuTests {
    let cfg = ShellConfig.provisional

    @Test func menuContainsSixKindsWithExpectedTitles() {
        // ticker-style-settings 5.1：原本恰為四項（透明度、隱藏／顯示、點穿、結束），新增「樣式」後為五項，其餘順序與標題不變。
        let m = StatusMenuController(config: cfg, initialAlpha: 0.9)
        // change source-switcher：在「點穿模式」與「樣式」之間新增「來源」，共六項，其餘順序與標題不變。
        #expect(m.items.map(\.kind) == [.opacity, .toggleVisibility, .clickThrough, .source, .style, .quit])
        #expect(m.items.map(\.title) == ["透明度", "隱藏帶子", "點穿模式", "來源", "樣式", "結束"])
        #expect(m.menu.items.contains { $0.view is NSView && $0.view?.subviews.contains { $0 is NSSlider } == true })
    }

    @Test func hideTogglesTitleToShowAndFiresCallback() {
        let m = StatusMenuController(config: cfg, initialAlpha: 0.9)
        var got: [Bool] = []
        m.onVisibilityChanged = { got.append($0) }
        m.setHidden(true)
        #expect(m.items[1].title == "顯示帶子")
        m.setHidden(false)
        #expect(m.items[1].title == "隱藏帶子")
        #expect(got == [true, false])
    }

    @Test func sliderRangeMatchesFloorAndAlphaIsClamped() {
        let m = StatusMenuController(config: cfg, initialAlpha: 0.9)
        #expect(m.sliderRange == cfg.alphaRange)
        var last = 1.0
        m.onAlphaChanged = { last = $0 }
        m.setAlpha(0.0)
        #expect(last == cfg.alphaRange.lowerBound && last > 0.2)
        #expect(StatusMenuController(config: cfg, initialAlpha: -3).alpha == cfg.alphaRange.lowerBound)
    }

    @Test func clickThroughIsNeverPersistedAndResetsOnRecreate() {
        let name = "FastBullTickerMenuTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; defer { d.removePersistentDomain(forName: name) }
        let m = StatusMenuController(config: cfg, initialAlpha: 0.9)
        var seen: [Bool] = []
        m.onClickThroughChanged = { seen.append($0) }
        m.setClickThrough(true)
        #expect(m.items[2].checked && seen == [true])
        #expect(d.persistentDomain(forName: name) == nil)
        let reborn = StatusMenuController(config: cfg, initialAlpha: 0.9)       // 模擬重啟
        #expect(reborn.clickThrough == false && reborn.items[2].checked == false)
    }

    @Test func quitFiresCallbackAndSameMenuInstanceServesPanelRightClick() {
        let m = StatusMenuController(config: cfg, initialAlpha: 0.9)
        var quit = 0
        m.onQuit = { quit += 1 }
        let quitItem = m.menu.items.last!
        _ = quitItem.target?.perform(quitItem.action)
        #expect(quit == 1)
        let v = TickerView(config: cfg); v.contextMenu = m.menu
        #expect(v.contextMenu === m.menu)
    }
}
