import Foundation
import CoreGraphics

/// 設定面板的位置與「面板外」判斷（settings-gear task 7，純函式，不依賴 AppKit 視窗）。座標為 Cocoa 螢幕座標（原點左下、y 向上）。
public enum SettingsPanelPlacement {
    /// 面板與跑馬燈之間的間距【假設：6pt】。
    public static let defaultGap: CGFloat = 6

    /// 面板外框：預設貼在跑馬燈正下方、左緣對齊；下方放不下改放正上方；水平夾進 `screenVisibleFrame`；
    /// 上下皆放不下時取空間較大的一側並夾進可視區（此時可能壓到跑馬燈）。
    public static func frame(panelSize: CGSize, tickerFrame t: CGRect, screenVisibleFrame vis: CGRect, gap: CGFloat = defaultGap) -> CGRect {
        let w = panelSize.width, h = panelSize.height
        let spaceBelow = t.minY - vis.minY - gap
        let spaceAbove = vis.maxY - t.maxY - gap
        let below = t.minY - gap - h, above = t.maxY + gap
        let y: CGFloat
        if spaceBelow >= h { y = below }
        else if spaceAbove >= h { y = above }
        else { y = clamp(spaceBelow >= spaceAbove ? below : above, vis.minY, vis.maxY - h) }
        let x = clamp(t.minX, vis.minX, vis.maxX - w)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 點是否在「面板外」：同時不在面板內、也不在跑馬燈內（半開區間，與 `CGRect.contains` 一致）。
    public static func isOutside(_ point: CGPoint, panelFrame: CGRect, tickerFrame: CGRect) -> Bool {
        !panelFrame.contains(point) && !tickerFrame.contains(point)
    }

    /// 夾進 [lo, hi]；hi < lo（放不下）時貼齊 lo。
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { hi < lo ? lo : min(max(v, lo), hi) }
}
