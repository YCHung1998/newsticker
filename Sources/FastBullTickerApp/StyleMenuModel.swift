import Foundation

/// 「樣式」子選單的純資料模型（ticker-style-settings 5.1）：輸入目前樣式與「設定檔有誤」狀態，輸出項目描述；
/// `NSMenu` 層（`StyleMenuController`）只負責呈現。不 import AppKit，所以項目清單、檔位、勾選與動作都能不建立 `NSMenu` 就測試。

public enum StyleMenuAction: Equatable, Sendable {
    case setFontSize(Double)
    case setReplayCount(Int)
    case setScrollSpeed(Double)
    case setCornerRadius(Double)
    case setLivePreset(Int)              // `LiveColorPreset.all` 的索引
    case toggleShowTime
    case toggleShowLabel
    case openFile
    case resetToDefault
}

public enum StyleMenuModel {
    /// 字級檔位【假設】：小 13、標準 16（預設）、大 20、特大 24。
    public static let fontSizeSteps: [(title: String, value: Double)] = [("小", 13), ("標準", 16), ("大", 20), ("特大", 24)]
    /// 訊息量檔位【假設】：5、10（預設）、20 則。
    public static let replayCountSteps: [Int] = [5, 10, 20]
    public static let configProblemNotice = "設定檔有誤，沿用上次有效值"

    public enum SliderKind: Equatable, Sendable { case scrollSpeed, cornerRadius }

    public struct Slider: Equatable, Sendable {
        public var kind: SliderKind
        public var range: ClosedRange<Double>
        public var value: Double
        public func action(for v: Double) -> StyleMenuAction { StyleMenuModel.sliderAction(kind, v) }
    }

    public enum Kind: Equatable, Sendable { case notice, submenu, slider, toggle, action, separator }

    public struct Entry: Equatable, Sendable {
        public var id: String
        public var kind: Kind
        public var title: String
        public var checked = false
        public var enabled = true
        public var children: [Entry] = []
        public var action: StyleMenuAction?
        public var slider: Slider?
    }

    static func sliderAction(_ kind: SliderKind, _ v: Double) -> StyleMenuAction {
        switch kind {
        case .scrollSpeed: return .setScrollSpeed(v.rounded())
        case .cornerRadius: return .setCornerRadius(v.rounded())
        }
    }

    /// 項目清單（順序見 spec `style-menu`）。
    public static func entries(for style: TickerStyle, hasConfigProblem: Bool = false) -> [Entry] {
        var out: [Entry] = []
        if hasConfigProblem {
            out.append(Entry(id: "notice", kind: .notice, title: configProblemNotice, enabled: false))
        }
        out.append(Entry(id: "fontSize", kind: .submenu, title: "字級", children: fontSizeSteps.map { s in
            Entry(id: "fontSize.\(Int(s.value))", kind: .action, title: "\(s.title)（\(Int(s.value))）",
                  checked: style.fontSize == s.value, action: .setFontSize(s.value))
        }))
        out.append(Entry(id: "scrollSpeed", kind: .slider, title: "捲動速度",
                         slider: Slider(kind: .scrollSpeed, range: StyleRanges.scrollSpeed, value: style.scrollSpeed)))
        out.append(Entry(id: "replayCount", kind: .submenu, title: "訊息量", children: replayCountSteps.map { n in
            Entry(id: "replayCount.\(n)", kind: .action, title: "\(n) 則", checked: style.replayCount == n, action: .setReplayCount(n))
        }))
        out.append(Entry(id: "cornerRadius", kind: .slider, title: "圓角",
                         slider: Slider(kind: .cornerRadius, range: StyleRanges.cornerRadius, value: style.cornerRadius)))
        out.append(Entry(id: "liveColors", kind: .submenu, title: "即時配色", children: LiveColorPreset.all.enumerated().map { i, p in
            Entry(id: "liveColors.\(i)", kind: .action, title: p.name,
                  checked: style.liveBackground == p.background && style.liveText == p.text, action: .setLivePreset(i))
        }))
        out.append(Entry(id: "separator1", kind: .separator, title: ""))
        out.append(Entry(id: "showTime", kind: .toggle, title: "顯示時間", checked: style.showTime, action: .toggleShowTime))
        out.append(Entry(id: "showLabel", kind: .toggle, title: "顯示標籤", checked: style.showLabel, action: .toggleShowLabel))
        out.append(Entry(id: "separator2", kind: .separator, title: ""))
        out.append(Entry(id: "openFile", kind: .action, title: "開啟樣式設定檔…", action: .openFile))
        out.append(Entry(id: "reset", kind: .action, title: "重設為預設", action: .resetToDefault))
        return out
    }

    /// 動作對樣式的影響（純函式；結果由 `StyleStore.update` 夾進合法範圍）。`openFile`／`resetToDefault` 不改欄位，回傳 false。
    @discardableResult
    public static func apply(_ action: StyleMenuAction, to style: inout TickerStyle) -> Bool {
        switch action {
        case .setFontSize(let v): style.fontSize = v
        case .setReplayCount(let n): style.replayCount = n
        case .setScrollSpeed(let v): style.scrollSpeed = v
        case .setCornerRadius(let v): style.cornerRadius = v
        case .setLivePreset(let i):
            guard LiveColorPreset.all.indices.contains(i) else { return false }
            style.liveBackground = LiveColorPreset.all[i].background
            style.liveText = LiveColorPreset.all[i].text            // 只動這兩個欄位，不動重播配色
        case .toggleShowTime: style.showTime.toggle()
        case .toggleShowLabel: style.showLabel.toggle()
        case .openFile, .resetToDefault: return false
        }
        return true
    }
}
