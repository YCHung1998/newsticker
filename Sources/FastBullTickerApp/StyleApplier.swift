import Foundation
import FastBullTickerCore

/// 樣式套用的唯一路徑（ticker-style-settings 6.1）：啟動載入、設定檔熱重載、選單修改都呼叫 `apply`。
/// 做兩件事：(1) `TickerView.apply(style:)`（顏色、標籤、圓角、字級，已排入訊息的 bitmap 就地重繪）；
/// (2) Core `reconfigure`（速度、可視寬度、訊息量、時間顯示、新字級的 measurer）。主執行緒。
@MainActor
public final class StyleApplier {
    private let config: ShellConfig
    private let view: TickerView
    private let driver: TickerDriver
    private let log: AppLog?
    private let timeZone: TimeZone
    /// 實際生效的樣式（含來源標籤覆寫）。
    public private(set) var current: TickerStyle
    /// 使用者樣式（`style.json`），不含覆寫；覆寫變更時用它重算生效樣式。
    private var userStyle: TickerStyle
    /// 目前來源的標籤（change source-switcher）。非 nil 時取代 `labelText`，且絕不寫回 `style.json`。
    public private(set) var labelOverride: String?
    /// 實際套用（樣式有變）的次數；相同樣式不重套，不計。
    public private(set) var applyCount = 0
    public private(set) var lastReport: TickerView.StyleApplyReport?
    /// `pollIntervalSeconds` 變更時呼叫（參數為新值，秒）。啟動套用（`source == "startup"`）不呼叫：啟動時 helper 尚未建立，
    /// 啟動參數由載入的樣式直接決定（settings-gear「poll-interval」）。
    public var onPollIntervalChange: ((Int) -> Void)?

    /// `initial` 必須是 `view` 與 `driver` 建構時所用的樣式（預設樣式）。
    public init(config: ShellConfig, view: TickerView, driver: TickerDriver, log: AppLog?,
                initial: TickerStyle = .default, timeZone: TimeZone = .current) {
        self.config = config; self.view = view; self.driver = driver; self.log = log
        self.current = initial; self.userStyle = initial; self.timeZone = timeZone
    }

    /// 欄位差異（日誌用）。
    static func changedKeys(from a: TickerStyle, to b: TickerStyle) -> [String] {
        var k: [String] = []
        if a.cornerRadius != b.cornerRadius { k.append("cornerRadius") }
        if a.fontSize != b.fontSize { k.append("fontSize") }
        if a.scrollSpeed != b.scrollSpeed { k.append("scrollSpeed") }
        if a.replayCount != b.replayCount { k.append("replayCount") }
        if a.showTime != b.showTime { k.append("showTime") }
        if a.showLabel != b.showLabel { k.append("showLabel") }
        if a.labelText != b.labelText { k.append("labelText") }
        if a.labelBackground != b.labelBackground { k.append("labelBackground") }
        if a.labelColor != b.labelColor { k.append("labelColor") }
        if a.tapeBackground != b.tapeBackground { k.append("tapeBackground") }
        if a.liveBackground != b.liveBackground { k.append("liveBackground") }
        if a.liveText != b.liveText { k.append("liveText") }
        if a.replayBackground != b.replayBackground { k.append("replayBackground") }
        if a.replayText != b.replayText { k.append("replayText") }
        if a.seekHoldSeconds != b.seekHoldSeconds { k.append("seekHoldSeconds") }
        if a.pollIntervalSeconds != b.pollIntervalSeconds { k.append("pollIntervalSeconds") }
        return k
    }

    /// 設定或清除來源標籤（nil = 回到 `style.json` 的 `labelText`）。
    public func setLabelOverride(_ label: String?) {
        guard label != labelOverride else { return }
        labelOverride = label
        apply(userStyle, source: "source")
    }

    /// `source`：`startup`／`file`／`menu`（日誌用）。樣式與目前相同則不做事。
    @discardableResult
    public func apply(_ userStyle: TickerStyle, source: String) -> Bool {
        self.userStyle = userStyle
        var style = userStyle
        if let l = labelOverride { style.labelText = l }
        guard style != current else { return false }
        let changed = Self.changedKeys(from: current, to: style)
        let pollChanged = style.pollIntervalSeconds != current.pollIntervalSeconds
        let report = view.apply(style: style)
        let viewport = config.tapeViewport(showLabel: style.showLabel)
        let tunables = SchedulerTunables(speed: style.scrollSpeed, viewportWidth: viewport, maxItemWidth: max(viewport, 600),
                                         replayCount: style.replayCount, showTime: style.showTime, timeZone: timeZone,
                                         seekHoldSeconds: style.seekHoldSeconds)
        driver.reconfigure(tunables, measurer: view.itemMeasurer, boldMeasurer: view.itemBoldMeasurer)
        current = style
        if pollChanged && source != "startup" { onPollIntervalChange?(style.pollIntervalSeconds) }
        applyCount += 1
        lastReport = report
        log?.write("style: applied source=\(source) changed=[\(changed.joined(separator: ","))] viewport=\(Int(viewport)) "
                   + "redrew=\(report.redrawnItems) redrawMs=\(String(format: "%.2f", report.redrawMillis)) totalRedrawn=\(view.redrawCount)")
        return true
    }
}

/// 把 `StyleStore`、套用端與選單接起來（`AppDelegate` 與 headless 煙霧測試共用同一段，確保路徑相同）：
/// 熱重載與選單修改都經 `store.onChange` → `StyleApplier.apply`；選單的資料來源是 store 的生效樣式與「設定檔有誤」狀態。
/// `store.onChange` 必須在主執行緒呼叫（正式的 `StyleStore` 以 `.main` 為 queue；選單操作本來就在主執行緒）。
@MainActor
public enum StyleWiring {
    /// `onApplied`：每次經 `store.onChange` 套用之後呼叫（設定面板據此重新整理控制項；主執行緒）。
    public static func connect(store: StyleStore, applier: StyleApplier, menu: StyleMenuController, runner: StyleActionRunner,
                               onApplied: (@MainActor () -> Void)? = nil) {
        menu.source = { [weak store] in (store?.style ?? .default, store?.hasConfigProblem ?? false) }
        menu.onAction = { [weak runner] in runner?.run($0) }
        store.onChange = { [weak applier] style, src in
            MainActor.assumeIsolated {
                _ = applier?.apply(style, source: src == .file ? "file" : "menu")
                onApplied?()
            }
        }
    }
}

extension TickerStyle {
    /// 單行摘要（日誌用）。
    public var summary: String {
        "cornerRadius=\(cornerRadius) fontSize=\(fontSize) scrollSpeed=\(scrollSpeed) replayCount=\(replayCount) showTime=\(showTime) showLabel=\(showLabel) "
        + "labelText=\(labelText) live=\(liveBackground.hex)/\(liveText.hex) replay=\(replayBackground.hex)/\(replayText.hex) "
        + "label=\(labelBackground.hex)/\(labelColor.hex) tape=\(tapeBackground.hex) seekHold=\(seekHoldSeconds) pollInterval=\(pollIntervalSeconds)"
    }
}
