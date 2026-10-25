import Foundation
import CoreGraphics

/// 設定面板的視窗抽象（真實實作 `SettingsPanel`；測試用假視窗，不開真實視窗）。
@MainActor
public protocol SettingsPanelWindowing: AnyObject {
    var panelSize: CGSize { get }
    var frame: CGRect { get }
    func show(at frame: CGRect)
    func hide()
}

/// 設定面板的開關邏輯（settings-gear task 9）：齒輪切換、關閉條件與全域滑鼠監看的安裝／移除。
/// 規則：開啟時安裝監看器、任何關閉路徑都移除（不洩漏）；全域按下在「面板與跑馬燈以外」關閉；
/// 本 App 自己的跑馬燈上按下（非齒輪）也視為面板外而關閉，齒輪上的按下不關閉（由 `onGear` 的 `toggle` 負責，避免關了又重開）。
@MainActor
public final class SettingsPanelCoordinator {
    private let window: SettingsPanelWindowing
    private let monitor: MouseDownMonitoring
    public var tickerFrame: () -> CGRect = { .zero }
    public var visibleFrame: () -> CGRect = { .zero }
    /// 開啟前呼叫（App 接到 `SettingsPanelController.willOpen`：重讀開機啟動狀態、整理控制項）。
    public var onWillOpen: () -> Void = {}
    /// 開啟狀態改變（日誌用）。
    public var onOpenChange: (Bool) -> Void = { _ in }
    public private(set) var isOpen = false

    public init(window: SettingsPanelWindowing, monitor: MouseDownMonitoring) {
        self.window = window; self.monitor = monitor
    }

    public func toggle() { isOpen ? close() : open() }

    public func open() {
        guard !isOpen else { return }
        onWillOpen()
        window.show(at: placement())
        monitor.install { [weak self] p in self?.globalMouseDown(at: p) }
        isOpen = true
        onOpenChange(true)
    }

    public func close() {
        guard isOpen else { return }
        monitor.remove()
        window.hide()
        isOpen = false
        onOpenChange(false)
    }

    /// 跑馬燈被隱藏時關閉。
    public func tickerWillHide() { close() }
    /// App 結束時關閉並確保監看器已移除。
    public func shutdown() { close() }

    /// 本 App 跑馬燈上的滑鼠按下（`TickerView` 回報；`onGear`＝按在齒輪上）。
    public func tickerPointerDown(onGear: Bool) { if !onGear { close() } }

    /// 內容高度改變（例如提示行出現）：開啟中時重新定位。
    public func contentSizeChanged() {
        guard isOpen else { return }
        window.show(at: placement())
    }

    func globalMouseDown(at p: CGPoint) {
        guard isOpen else { return }
        if SettingsPanelPlacement.isOutside(p, panelFrame: window.frame, tickerFrame: tickerFrame()) { close() }
    }

    private func placement() -> CGRect {
        SettingsPanelPlacement.frame(panelSize: window.panelSize, tickerFrame: tickerFrame(), screenVisibleFrame: visibleFrame())
    }
}
