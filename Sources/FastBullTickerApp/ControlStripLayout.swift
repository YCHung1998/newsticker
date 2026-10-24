import Foundation

/// 控制列版面（純函式，無 AppKit）：面板右端固定寬度，由左至右 `<` 按鈕、位置指示、`>` 按鈕。
/// 預設 24 + 52 + 24 = 100pt【假設，見 ticker-navigation-link design.md 決定 8；待使用者看實物後確認】。
/// 帶子可視寬度 = 面板寬 − 標籤寬 − 控制列寬（620 − 150 − 100 = 370）。
public struct ControlStripLayout: Equatable, Sendable {
    public var buttonWidth: Double
    public var indicatorWidth: Double

    public init(buttonWidth: Double = 24, indicatorWidth: Double = 52) {
        self.buttonWidth = buttonWidth; self.indicatorWidth = indicatorWidth
    }

    public var controlStripWidth: Double { 2 * buttonWidth + indicatorWidth }

    public func tapeViewportWidth(panelWidth: Double, labelWidth: Double) -> Double {
        max(0, panelWidth - labelWidth - controlStripWidth)
    }

    /// 以下皆為面板座標的 x 範圍（半開區間）。
    public func stripRange(panelWidth: Double) -> Range<Double> { (panelWidth - controlStripWidth)..<panelWidth }
    public func previousButtonRange(panelWidth: Double) -> Range<Double> {
        let l = panelWidth - controlStripWidth
        return l..<(l + buttonWidth)
    }
    public func indicatorRange(panelWidth: Double) -> Range<Double> {
        let l = panelWidth - controlStripWidth + buttonWidth
        return l..<(l + indicatorWidth)
    }
    public func nextButtonRange(panelWidth: Double) -> Range<Double> { (panelWidth - buttonWidth)..<panelWidth }
}
