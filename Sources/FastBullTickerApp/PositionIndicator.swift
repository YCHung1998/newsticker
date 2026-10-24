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
