import FastBullTickerCore

/// 位置指示文字 `(n/N)`：半形括號與斜線、十進位 ASCII 數字、無前導零與空白。無閱讀位置時為空字串（不顯示 `(0/0)`）。
public enum PositionIndicator {
    public static func text(for position: ReadingPosition?) -> String {
        guard let p = position else { return "" }
        return text(index: p.index, total: p.total)
    }

    public static func text(index: Int, total: Int) -> String {
        guard index >= 1, total >= 1 else { return "" }
        return "(" + String(index) + "/" + String(total) + ")"
    }
}

/// 控制列的顯示狀態（純值）：位置指示文字與兩個按鈕是否可用（不可用者淡化）。
public struct ControlStripState: Equatable, Sendable {
    public var text: String
    public var previousEnabled: Bool
    public var nextEnabled: Bool
    public init(text: String, previousEnabled: Bool, nextEnabled: Bool) {
        self.text = text; self.previousEnabled = previousEnabled; self.nextEnabled = nextEnabled
    }

    /// 清單第一則時 `<` 停用；沒有閱讀中的訊息時兩者皆停用；最後一則仍可按 `>`（跳下一輪起點，見 design 決定 6）。
    public static func from(position: ReadingPosition?) -> ControlStripState {
        guard let p = position else { return ControlStripState(text: "", previousEnabled: false, nextEnabled: false) }
        return ControlStripState(text: PositionIndicator.text(for: p), previousEnabled: p.index > 1, nextEnabled: true)
    }
}
