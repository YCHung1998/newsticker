import Testing
import Foundation
@testable import FastBullTickerApp

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// settings-gear task 8（純邏輯）：SettingsPanelModel 描述面板全部項目、檔位、目前值與對應動作，並與 StyleMenuModel／StyleRanges 共用同一份。
// 執行：swift test --filter SettingsPanelModel
@Suite struct SettingsPanelModelTests {
    typealias M = SettingsPanelModel
    private let off = LaunchAtLoginViewState(isOn: false, detail: "未啟用", offersOpenSettings: false, isError: false)

    private func items(_ s: TickerStyle = .default, problem: Bool = false, launch: LaunchAtLoginViewState? = nil) -> [M.Item] {
        M.items(style: s, hasConfigProblem: problem, launch: launch ?? off)
    }
    private func item(_ id: String, _ s: TickerStyle = .default) throws -> M.Item { try #require(items(s).first { $0.id == id }) }
    private func seg(_ id: String, _ s: TickerStyle = .default) throws -> (options: [M.Option], selected: Int?) {
        guard case .segmented(_, _, let o, let sel) = try item(id, s) else { Issue.record("\(id) 不是分段控制"); return ([], nil) }
        return (o, sel)
    }
    private func slider(_ id: String, _ s: TickerStyle = .default) throws -> M.Slider {
        guard case .slider(_, _, let sl) = try item(id, s) else { Issue.record("\(id) 不是滑桿"); return M.Slider(kind: .scrollSpeed, range: 0...1, step: 1, value: 0) }
        return sl
    }

    @Test func itemsAreInSpecOrder() {
        #expect(items().map(\.id) == ["fontSize", "scrollSpeed", "cornerRadius", "replayCount", "liveColors", "showTime", "showLabel",
                                      "seekHold", "pollInterval", "launchAtLogin", "openFile", "reset", "close"])
    }

    @Test func defaultValuesMatchTheSpecScenario() throws {
        #expect(try seg("fontSize").selected == 1, "字級標準")
        #expect(try slider("scrollSpeed").value == 90)
        #expect(try slider("cornerRadius").value == 0)
        #expect(try seg("replayCount").selected == 1, "訊息量 10")
        #expect(try seg("liveColors").selected == 0, "白底黑字")
        if case .toggle(_, _, let on, _) = try item("showTime") { #expect(on) } else { Issue.record("showTime") }
        if case .toggle(_, _, let on, _) = try item("showLabel") { #expect(on) } else { Issue.record("showLabel") }
        #expect(try slider("seekHold").value == 1)
        #expect(try seg("pollInterval").selected == 0, "輪詢 10 秒")
    }

    @Test func segmentedStepsAreTheSameAsStyleMenuModel() throws {
        let menu = StyleMenuModel.entries(for: .default)
        for (panelId, menuId) in [("fontSize", "fontSize"), ("replayCount", "replayCount"), ("liveColors", "liveColors")] {
            let children = try #require(menu.first { $0.id == menuId }).children
            let opts = try seg(panelId).options
            #expect(opts.count == children.count, "\(panelId) 檔位數")
            #expect(opts.map(\.command) == children.map { .style($0.action!) }, "\(panelId) 動作逐項相同")
        }
        #expect(try seg("fontSize").options.map(\.title) == StyleMenuModel.fontSizeSteps.map(\.title))
        #expect(try seg("replayCount").options.map(\.command) == StyleMenuModel.replayCountSteps.map { .style(.setReplayCount($0)) })
        #expect(try seg("liveColors").options.map(\.title) == LiveColorPreset.all.map(\.name))
        #expect(try seg("liveColors").options.map(\.command) == LiveColorPreset.all.indices.map { .style(.setLivePreset($0)) })
    }

    @Test func pollIntervalStepsComeFromStyleRanges() throws {
        let o = try seg("pollInterval").options
        #expect(o.map(\.command) == StyleRanges.pollIntervalSteps.map { .style(.setPollIntervalSeconds($0)) })
        #expect(o.map(\.title) == ["10 秒", "30 秒", "60 秒"])
        var s = TickerStyle.default; s.pollIntervalSeconds = 60
        #expect(try seg("pollInterval", s).selected == 2)
    }

    @Test func slidersShareRangesWithStyleRanges() throws {
        #expect(try slider("scrollSpeed").range == StyleRanges.scrollSpeed && StyleRanges.scrollSpeed == 20...300)
        #expect(try slider("cornerRadius").range == StyleRanges.cornerRadius && StyleRanges.cornerRadius == 0...21)
        #expect(try slider("seekHold").range == StyleRanges.seekHoldSeconds && StyleRanges.seekHoldSeconds == 0.5...10)
        #expect(try slider("seekHold").step == 0.5)
    }

    @Test func sliderCommandsRoundLikeTheMenuSliders() throws {
        #expect(try slider("scrollSpeed").command(for: 120.4) == .style(.setScrollSpeed(120)))
        #expect(try slider("scrollSpeed").command(for: 120.6) == .style(.setScrollSpeed(121)))
        #expect(try slider("cornerRadius").command(for: 8.5) == .style(.setCornerRadius(9)))
        #expect(try slider("scrollSpeed").command(for: 77.7) == StyleMenuModel.Slider(kind: .scrollSpeed, range: StyleRanges.scrollSpeed, value: 90).action(for: 77.7).asCommand)
        #expect(try slider("seekHold").command(for: 3.3) == .style(.setSeekHoldSeconds(3.5)), "停留時間以 0.5 為步進")
        #expect(try slider("seekHold").command(for: 3.2) == .style(.setSeekHoldSeconds(3.0)))
        #expect(try slider("seekHold").command(for: 0.5) == .style(.setSeekHoldSeconds(0.5)))
    }

    @Test func valueTexts() throws {
        var s = TickerStyle.default; s.scrollSpeed = 150; s.cornerRadius = 8; s.seekHoldSeconds = 2.5
        #expect(try slider("scrollSpeed", s).valueText == "150")
        #expect(try slider("cornerRadius", s).valueText == "8")
        #expect(try slider("seekHold", s).valueText == "2.5 秒")
        #expect(try slider("seekHold").valueText == "1.0 秒")
    }

    @Test func selectionFollowsTheEffectiveStyle() throws {
        var s = TickerStyle.default
        s.fontSize = 20; s.replayCount = 20; s.showTime = false; s.showLabel = false
        s.liveBackground = LiveColorPreset.all[2].background; s.liveText = LiveColorPreset.all[2].text
        #expect(try seg("fontSize", s).selected == 2)
        #expect(try seg("replayCount", s).selected == 2)
        #expect(try seg("liveColors", s).selected == 2)
        if case .toggle(_, _, let on, _) = try item("showTime", s) { #expect(!on) }
        if case .toggle(_, _, let on, _) = try item("showLabel", s) { #expect(!on) }
        s.fontSize = 17; s.replayCount = 7
        #expect(try seg("fontSize", s).selected == nil, "手動編輯成非檔位值：不選任何一格")
        #expect(try seg("replayCount", s).selected == nil)
        s.liveBackground = RGBColor(hex: "#123456")!
        #expect(try seg("liveColors", s).selected == nil)
    }

    @Test func togglesAndButtonsCarryTheSharedActions() throws {
        guard case .toggle(_, _, _, let t) = try item("showTime"), case .toggle(_, _, _, let l) = try item("showLabel") else { Issue.record("toggle"); return }
        #expect(t == .style(.toggleShowTime) && l == .style(.toggleShowLabel))
        guard case .button(_, let ot, let oc) = try item("openFile"), case .button(_, let rt, let rc) = try item("reset"),
              case .button(_, let ct, let cc) = try item("close") else { Issue.record("button"); return }
        #expect(oc == .style(.openFile) && rc == .style(.resetToDefault) && cc == .close)
        #expect(ot == "開啟樣式設定檔…" && rt == "重設為預設" && ct == "關閉")
        let menu = StyleMenuModel.entries(for: .default)
        #expect(menu.first { $0.id == "openFile" }?.title == ot && menu.first { $0.id == "reset" }?.title == rt, "按鈕標題與選單相同")
    }

    @Test func everyStyleCommandChangesTheCorrespondingField() {
        // 面板的每個 `.style` 動作都經 StyleMenuModel.apply（沒有另寫一套）：逐項套用後欄位確實改變
        var changed = Set<String>()
        for it in items() {
            var commands: [M.Command] = []
            switch it {
            case .segmented(_, _, let o, _): commands = o.map(\.command)
            case .toggle(_, _, _, let c): commands = [c]
            case .slider(_, _, let sl): commands = [sl.command(for: sl.range.lowerBound), sl.command(for: sl.range.upperBound)]
            default: break
            }
            for c in commands {
                guard case .style(let a) = c else { Issue.record("非 style 動作 \(c)"); continue }
                var s = TickerStyle.default
                if StyleMenuModel.apply(a, to: &s), s != .default { changed.insert(it.id) }
            }
        }
        #expect(changed == ["fontSize", "scrollSpeed", "cornerRadius", "replayCount", "liveColors", "showTime", "showLabel", "seekHold", "pollInterval"])
    }

    @Test func launchAtLoginIsNotAStyleAction() throws {
        let on = LaunchAtLoginViewState(isOn: true, detail: "已啟用", offersOpenSettings: false, isError: false)
        guard case .launchAtLogin(_, let st) = try #require(items(launch: on).first(where: { $0.id == "launchAtLogin" })) else { Issue.record("launch"); return }
        #expect(st == on)
        #expect(M.Command.setLaunchAtLogin(true) != .style(.toggleShowTime))
        #expect(M.Command.setLaunchAtLogin(true) != .style(.resetToDefault) && M.Command.openLoginSettings != .close)
    }

    @Test func configProblemAddsTheSameNoticeFirst() {
        let it = items(problem: true)
        #expect(it.first == .notice(StyleMenuModel.configProblemNotice) && StyleMenuModel.configProblemNotice == "設定檔有誤，沿用上次有效值")
        #expect(Array(it.dropFirst()).map(\.id) == items().map(\.id))
        #expect(items().first?.id != "notice")
    }

    @Test func structureSignatureIgnoresValuesButNotLayout() {
        var s = TickerStyle.default; s.fontSize = 24; s.scrollSpeed = 200
        #expect(M.structure(of: items()) == M.structure(of: items(s)), "值變不算結構變")
        #expect(M.structure(of: items()) != M.structure(of: items(problem: true)), "提示行出現算結構變")
        let approve = LaunchAtLoginViewState(isOn: false, detail: "需要核准", offersOpenSettings: true, isError: false)
        #expect(M.structure(of: items()) != M.structure(of: items(launch: approve)), "多出「開啟系統設定」按鈕算結構變")
    }
}

private extension StyleMenuAction {
    var asCommand: SettingsPanelModel.Command { .style(self) }
}
