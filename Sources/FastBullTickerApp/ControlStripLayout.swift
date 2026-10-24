import Foundation

/// 控制列版面（純函式，無 AppKit）。面板由左至右：〔（預留）齒輪槽〕、標籤、控制列、訊息帶子。
/// 控制列內由左至右：`<` 按鈕、位置指示、`>` 按鈕；預設 24 + 52 + 24 = 100pt【假設，見 ticker-navigation-link design.md 決定 8；待使用者看實物後確認】。
///
/// 所有範圍函式的 `leftInset` 是「控制列左側已被占用的寬度」＝ 標籤寬（`showLabel` 為 false 時 0）；
/// 日後若在標籤左側加齒輪槽，呼叫端只要傳入 `齒輪槽寬 + 標籤寬`，其餘公式不變（nav-layout-tweaks design.md 決定 8）。
/// 帶子可視區為 `[leftInset + controlStripWidth, panelWidth)`；帶子座標 0 對應面板 x = `tapeLeft(leftInset:)`。
public struct ControlStripLayout: Equatable, Sendable {
    public var buttonWidth: Double
    public var indicatorWidth: Double

    public init(buttonWidth: Double = 24, indicatorWidth: Double = 52) {
        self.buttonWidth = buttonWidth; self.indicatorWidth = indicatorWidth
    }

    public var controlStripWidth: Double { 2 * buttonWidth + indicatorWidth }

    /// 帶子可視寬度 = 面板寬 − 控制列左側占用寬 − 控制列寬（620 − 150 − 100 = 370；標籤隱藏 520）。
    public func tapeViewportWidth(panelWidth: Double, labelWidth leftInset: Double) -> Double {
        max(0, panelWidth - leftInset - controlStripWidth)
    }

    /// 帶子座標 0（可視區左緣、`readingInset` 與 seek 對齊的參考線）的面板 x。
    public func tapeLeft(leftInset: Double) -> Double { leftInset + controlStripWidth }

    /// 以下皆為面板座標的 x 範圍（半開區間）。
    public func stripRange(leftInset: Double) -> Range<Double> { leftInset..<(leftInset + controlStripWidth) }
    public func previousButtonRange(leftInset: Double) -> Range<Double> { leftInset..<(leftInset + buttonWidth) }
    public func indicatorRange(leftInset: Double) -> Range<Double> {
        (leftInset + buttonWidth)..<(leftInset + buttonWidth + indicatorWidth)
    }
    public func nextButtonRange(leftInset: Double) -> Range<Double> {
        (leftInset + buttonWidth + indicatorWidth)..<(leftInset + controlStripWidth)
    }
}
