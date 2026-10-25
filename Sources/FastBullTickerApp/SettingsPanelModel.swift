import Foundation

/// 設定面板的純資料模型（settings-gear task 8）：輸入目前樣式、「設定檔有誤」狀態與開機啟動的顯示狀態，輸出全部項目、檔位、目前值與對應動作。
/// 不 import AppKit；檔位與範圍全部取自 `StyleMenuModel`／`StyleRanges`／`LiveColorPreset`（與選單列「樣式」子選單同一份），
/// 樣式動作一律是 `StyleMenuAction`（經 `StyleActionRunner`／`StyleStore.update`），這裡不做夾制、不做寫回。視圖層只負責呈現。
public enum SettingsPanelModel {
    /// 控制項產生的指令。
    public enum Command: Equatable, Sendable {
        case style(StyleMenuAction)
        case setLaunchAtLogin(Bool)         // 經 `LaunchAtLoginController`，不寫 style.json
        case openLoginSettings              // 需要核准時的「開啟系統設定」
        case close
    }

    public struct Option: Equatable, Sendable {
        public var title: String
        public var command: Command
    }

    public enum SliderKind: Equatable, Sendable { case scrollSpeed, cornerRadius, seekHold }

    public struct Slider: Equatable, Sendable {
        public var kind: SliderKind
        public var range: ClosedRange<Double>
        public var step: Double
        public var value: Double

        public func command(for v: Double) -> Command {
            switch kind {
            case .scrollSpeed: return .style(StyleMenuModel.sliderAction(.scrollSpeed, v))
            case .cornerRadius: return .style(StyleMenuModel.sliderAction(.cornerRadius, v))
            case .seekHold: return .style(.setSeekHoldSeconds((v / step).rounded() * step))
            }
        }
        /// 目前（或拖到的）值的文字。
        public func text(for v: Double) -> String {
            switch kind {
            case .scrollSpeed, .cornerRadius: return String(Int(v.rounded()))
            case .seekHold: return String(format: "%.1f 秒", (v / step).rounded() * step)
            }
        }
        public var valueText: String { text(for: value) }
    }

    public enum Item: Equatable, Sendable {
        case notice(String)
        case segmented(id: String, title: String, options: [Option], selected: Int?)
        case slider(id: String, title: String, slider: Slider)
        case toggle(id: String, title: String, isOn: Bool, command: Command)
        case launchAtLogin(title: String, state: LaunchAtLoginViewState)
        case button(id: String, title: String, command: Command)

        public var id: String {
            switch self {
            case .notice: return "notice"
            case .segmented(let id, _, _, _), .slider(let id, _, _), .toggle(let id, _, _, _), .button(let id, _, _): return id
            case .launchAtLogin: return "launchAtLogin"
            }
        }
    }

    /// 全部項目，順序見 spec `settings-panel`：字級、速度、圓角、訊息量、即時配色、顯示時間、顯示標籤、停留、輪詢、開機啟動、開啟檔案、重設、關閉。
    public static func items(style: TickerStyle, hasConfigProblem: Bool, launch: LaunchAtLoginViewState) -> [Item] {
        var out: [Item] = []
        if hasConfigProblem { out.append(.notice(StyleMenuModel.configProblemNotice)) }

        let fonts = StyleMenuModel.fontSizeSteps
        out.append(.segmented(id: "fontSize", title: "字級",
                              options: fonts.map { Option(title: $0.title, command: .style(.setFontSize($0.value))) },
                              selected: fonts.firstIndex { $0.value == style.fontSize }))
        out.append(.slider(id: "scrollSpeed", title: "捲動速度",
                           slider: Slider(kind: .scrollSpeed, range: StyleRanges.scrollSpeed, step: 1, value: style.scrollSpeed)))
        out.append(.slider(id: "cornerRadius", title: "圓角",
                           slider: Slider(kind: .cornerRadius, range: StyleRanges.cornerRadius, step: 1, value: style.cornerRadius)))
        let counts = StyleMenuModel.replayCountSteps
        out.append(.segmented(id: "replayCount", title: "重播訊息量",
                              options: counts.map { Option(title: "\($0) 則", command: .style(.setReplayCount($0))) },
                              selected: counts.firstIndex(of: style.replayCount)))
        let presets = LiveColorPreset.all
        out.append(.segmented(id: "liveColors", title: "即時配色",
                              options: presets.enumerated().map { Option(title: $1.name, command: .style(.setLivePreset($0))) },
                              selected: presets.firstIndex { $0.background == style.liveBackground && $0.text == style.liveText }))
        out.append(.toggle(id: "showTime", title: "顯示時間", isOn: style.showTime, command: .style(.toggleShowTime)))
        out.append(.toggle(id: "showLabel", title: "顯示標籤", isOn: style.showLabel, command: .style(.toggleShowLabel)))
        out.append(.slider(id: "seekHold", title: "切換後停留",
                           slider: Slider(kind: .seekHold, range: StyleRanges.seekHoldSeconds, step: 0.5, value: style.seekHoldSeconds)))
        let polls = StyleRanges.pollIntervalSteps
        out.append(.segmented(id: "pollInterval", title: "輪詢間隔",
                              options: polls.map { Option(title: "\($0) 秒", command: .style(.setPollIntervalSeconds($0))) },
                              selected: polls.firstIndex(of: style.pollIntervalSeconds)))
        out.append(.launchAtLogin(title: "開機自動啟動", state: launch))
        out.append(.button(id: "openFile", title: "開啟樣式設定檔…", command: .style(.openFile)))
        out.append(.button(id: "reset", title: "重設為預設", command: .style(.resetToDefault)))
        out.append(.button(id: "close", title: "關閉", command: .close))
        return out
    }

    /// 版面結構簽章：只有項目種類、檔位數、是否有提示行／「開啟系統設定」按鈕會影響；值變化不影響（值變只就地更新控制項，避免拖動中的滑桿被換掉）。
    public static func structure(of items: [Item]) -> [String] {
        items.map { item in
            switch item {
            case .notice: return "notice"
            case .segmented(let id, _, let o, _): return "seg:\(id):\(o.map(\.title).joined(separator: "|"))"
            case .slider(let id, _, let s): return "slider:\(id):\(s.range.lowerBound)-\(s.range.upperBound):\(s.step)"
            case .toggle(let id, _, _, _): return "toggle:\(id)"
            case .launchAtLogin(_, let st): return "launch:\(st.offersOpenSettings)"
            case .button(let id, let t, _): return "button:\(id):\(t)"
            }
        }
    }
}
