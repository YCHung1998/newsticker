import CoreGraphics

/// 設定齒輪的路徑（settings-gear 決定 3：自繪路徑，不使用 SF Symbol）。純函式，無 AppKit。
/// 外形【假設，待使用者目視】：8 齒、外半徑 8pt（直徑 16）、齒根半徑 6.2pt、中心孔半徑 2.8pt；以 `evenOdd` 填色挖出中心孔。
/// 八個齒對稱於兩軸與兩條對角線，所以墨跡外框的中心恰為 `bounds` 的中心（置中不依賴任何度量）。
public enum GearGlyph {
    public static let teeth = 8
    public static let outerRadius: CGFloat = 8
    public static let rootRadius: CGFloat = 6.2
    public static let holeRadius: CGFloat = 2.8
    /// 齒的半角（弧度）：齒尖較窄、齒根較寬。
    private static let tipHalfAngle: CGFloat = 8.5 * .pi / 180
    private static let rootHalfAngle: CGFloat = 12.5 * .pi / 180

    public static func path(in bounds: CGRect) -> CGPath {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let p = CGMutablePath()
        let step = 2 * CGFloat.pi / CGFloat(teeth)
        func pt(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        for i in 0..<teeth {
            let a = CGFloat(i) * step
            let rootStart = pt(rootRadius, a - rootHalfAngle)
            if i == 0 { p.move(to: rootStart) } else { p.addLine(to: rootStart) }
            p.addLine(to: pt(outerRadius, a - tipHalfAngle))
            p.addLine(to: pt(outerRadius, a + tipHalfAngle))
            p.addLine(to: pt(rootRadius, a + rootHalfAngle))
            // 齒與齒之間沿齒根圓走弧
            p.addArc(center: c, radius: rootRadius, startAngle: a + rootHalfAngle, endAngle: a + step - rootHalfAngle, clockwise: false)
        }
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: c.x - holeRadius, y: c.y - holeRadius, width: 2 * holeRadius, height: 2 * holeRadius))
        return p
    }
}
