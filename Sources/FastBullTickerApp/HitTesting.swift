import Foundation
import CoreGraphics

public enum HitTarget: Equatable, Sendable {
    case gear
    case previousButton
    case nextButton
    case link(seq: Int)
    case drag
}

/// 目前可見的一則訊息（Core `PlacedItem` 的幾何子集）。`visualLeft` 是帶子座標（0 = 可視區左緣＝控制列右緣）的視覺左緣。
public struct HitItem: Equatable, Sendable {
    public var seq: Int
    public var visualLeft: Double
    public var width: Double
    public var hasLinkSlot: Bool
    public init(seq: Int, visualLeft: Double, width: Double, hasLinkSlot: Bool) {
        self.seq = seq; self.visualLeft = visualLeft; self.width = width; self.hasLinkSlot = hasLinkSlot
    }
}

public struct HitGeometry: Equatable, Sendable {
    public var panelSize: CGSize
    public var labelWidth: Double
    /// 齒輪槽寬度（面板最左側）。預設 0＝沒有齒輪槽（既有直接建構的測試不受影響）。
    public var gearSlotWidth: Double
    public var strip: ControlStripLayout
    public var linkSlotWidth: Double
    /// 迴紋針命中區每側外擴（pt）【假設：4】。
    public var hitSlop: Double
    public init(panelSize: CGSize, labelWidth: Double, gearSlotWidth: Double = 0, strip: ControlStripLayout = ControlStripLayout(),
                linkSlotWidth: Double, hitSlop: Double = HitTesting.defaultHitSlop) {
        self.panelSize = panelSize; self.labelWidth = labelWidth; self.gearSlotWidth = gearSlotWidth; self.strip = strip
        self.linkSlotWidth = linkSlotWidth; self.hitSlop = hitSlop
    }

    /// 控制列左側已被占用的寬度（單一偏移）＝ 齒輪槽 + 標籤。
    public var leftInset: Double { gearSlotWidth + labelWidth }
}

/// 命中測試（純函式）。優先序：齒輪／控制列按鈕 > 迴紋針 > 拖曳。
/// 點為面板座標（x 向右、0 = 面板左緣；y 只用來判斷是否在面板內，迴紋針命中區為整條帶高）。
public enum HitTesting {
    public static let defaultHitSlop = 4.0

    public static func target(at point: CGPoint, in g: HitGeometry, items: [HitItem]) -> HitTarget {
        let w = Double(g.panelSize.width), h = Double(g.panelSize.height)
        let x = Double(point.x), y = Double(point.y)
        guard x >= 0, x < w, y >= 0, y < h else { return .drag }
        // 0. 齒輪槽（面板最左側）：半開區間 [0, gearSlotWidth)，整條高度。
        if x < g.gearSlotWidth { return .gear }
        // 1. 控制列（標籤右側）：按鈕範圍優先；位置指示本身不是按鈕（拖曳）。
        let inset = g.leftInset
        if g.strip.stripRange(leftInset: inset).contains(x) {
            if g.strip.previousButtonRange(leftInset: inset).contains(x) { return .previousButton }
            if g.strip.nextButtonRange(leftInset: inset).contains(x) { return .nextButton }
            return .drag
        }
        // 2. 標籤（控制列左側）：不是連結（被遮住者無效）。
        let tapeLeft = g.strip.tapeLeft(leftInset: inset)
        guard x >= tapeLeft else { return .drag }
        // 3. 可見帶子 [控制列右緣, 面板右緣) 內的迴紋針命中區（依陣列順序，先符合者為準）。
        guard g.linkSlotWidth > 0 else { return .drag }
        for item in items where item.hasLinkSlot {
            let right = tapeLeft + item.visualLeft + item.width
            let zone = (right - g.linkSlotWidth - g.hitSlop)..<(right + g.hitSlop)
            if zone.contains(x) { return .link(seq: item.seq) }
        }
        return .drag
    }
}
