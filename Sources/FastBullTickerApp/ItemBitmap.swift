import Foundation
import CoreText
import CoreGraphics
import FastBullTickerCore

/// 訊息預渲染（task 4.1）：CoreText 量測與繪製成 bitmap（可切塊）。量測與繪製共用同一組參數，
/// 因此 Core `layoutItem` 算出的 `width` 與實際 bitmap 寬度一致。
public struct ItemBitmapRenderer: Sendable {
    public var fontSize: CGFloat
    public var padding: CGFloat
    public var heightPt: CGFloat
    public var textureLimitPx: Int
    /// 【假設】字型 PingFang TC（繁中 macOS 內建）；找不到時 CoreText 會 fallback。
    static let fontName = "PingFangTC-Regular"

    public init(fontSize: CGFloat, padding: CGFloat, heightPt: CGFloat, textureLimitPx: Int) {
        self.fontSize = fontSize; self.padding = padding; self.heightPt = heightPt; self.textureLimitPx = textureLimitPx
    }

    func font() -> CTFont { CTFontCreateWithName(Self.fontName as CFString, fontSize, nil) }

    func line(_ text: String) -> CTLine {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    /// 給 Core 的量測函式：文字寬度（向上取整）加左右留白。
    public var measurer: TextMeasurer {
        let r = self
        return { s in Double(CGFloat(CTLineGetTypographicBounds(r.line(s), nil, nil, nil)).rounded(.up) + 2 * r.padding) }
    }

    /// 切塊寬度（px）：總和 = `ceil(width × scale)`，每塊 ≤ 紋理上限。
    public func tilePlan(width: Double, scale: CGFloat) -> [Int] {
        Tiling.tileWidths(totalPx: Int((CGFloat(width) * scale).rounded(.up)), limit: textureLimitPx)
    }

    /// 渲染一則訊息。live＝白底黑字、replay＝黑底白字。
    public func render(_ item: PlacedItem, scale: CGFloat) -> [CGImage] {
        let ln = line(item.timeString + " " + item.text)
        var asc: CGFloat = 0, desc: CGFloat = 0
        _ = CTLineGetTypographicBounds(ln, &asc, &desc, nil)
        let hPx = Int((heightPt * scale).rounded(.up))
        let live = item.style == .live
        let bg: CGFloat = live ? 1 : 0, fg: CGFloat = live ? 0 : 1
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var x0 = 0
        var tiles: [CGImage] = []
        for w in tilePlan(width: item.width, scale: scale) {
            guard let ctx = CGContext(data: nil, width: w, height: hPx, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(CGColor(red: bg, green: bg, blue: bg, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: hPx))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -CGFloat(x0) / scale, y: 0)
            ctx.setFillColor(CGColor(red: fg, green: fg, blue: fg, alpha: 1))
            ctx.textPosition = CGPoint(x: padding, y: (heightPt - (asc + desc)) / 2 + desc)
            CTLineDraw(ln, ctx)
            if let img = ctx.makeImage() { tiles.append(img) }
            x0 += w
        }
        return tiles
    }
}
