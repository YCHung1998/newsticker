import Foundation
import CoreGraphics

public enum HitTarget: Equatable, Sendable {
    case previousButton
    case nextButton
    case link(seq: Int)
    case drag
}

/// 目前可見的一則訊息（Core `PlacedItem` 的幾何子集）。`visualLeft` 是帶子座標（0 = 標籤右緣）的視覺左緣。
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
    public var strip: ControlStripLayout
    public var linkSlotWidth: Double
    /// 迴紋針命中區每側外擴（pt）【假設：4】。
    public var hitSlop: Double
    public init(panelSize: CGSize, labelWidth: Double, strip: ControlStripLayout = ControlStripLayout(),
                linkSlotWidth: Double, hitSlop: Double = HitTesting.defaultHitSlop) {
        self.panelSize = panelSize; self.labelWidth = labelWidth; self.strip = strip
        self.linkSlotWidth = linkSlotWidth; self.hitSlop = hitSlop
    }
}

/// 命中測試（純函式）。優先序：控制列按鈕 > 迴紋針 > 拖曳。
/// 點為面板座標（x 向右、0 = 面板左緣；y 只用來判斷是否在面板內，迴紋針命中區為整條帶高）。
public enum HitTesting {
    public static let defaultHitSlop = 4.0

    public static func target(at point: CGPoint, in g: HitGeometry, items: [HitItem]) -> HitTarget {
        let w = Double(g.panelSize.width), h = Double(g.panelSize.height)
        let x = Double(point.x), y = Double(point.y)
        guard x >= 0, x < w, y >= 0, y < h else { return .drag }
        // 1. 控制列：按鈕範圍優先；位置指示本身不是按鈕（拖曳）。
        if g.strip.stripRange(panelWidth: w).contains(x) {
            if g.strip.previousButtonRange(panelWidth: w).contains(x) { return .previousButton }
            if g.strip.nextButtonRange(panelWidth: w).contains(x) { return .nextButton }
            return .drag
        }
        // 2. 標籤：不是連結（被遮住者無效）。
        guard x >= g.labelWidth else { return .drag }
        // 3. 可見帶子 [labelWidth, 控制列左緣) 內的迴紋針命中區（依陣列順序，先符合者為準）。
        guard g.linkSlotWidth > 0 else { return .drag }
        for item in items where item.hasLinkSlot {
            let right = g.labelWidth + item.visualLeft + item.width
            let zone = (right - g.linkSlotWidth - g.hitSlop)..<(right + g.hitSlop)
            if zone.contains(x) { return .link(seq: item.seq) }
        }
        return .drag
    }
}
