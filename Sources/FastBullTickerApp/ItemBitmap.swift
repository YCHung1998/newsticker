import Foundation
import CoreText
import CoreGraphics
import FastBullTickerCore

/// 顯示字串中「時間」的偵測（量測與繪製共用，避免寬度不一致）。
public enum ItemText {
    /// 開頭若是 `dd:dd:dd`（Core 的 `HH:mm:ss`）加一個空白前綴，回傳 8（粗體字元數）；否則 0。
    public static func boldPrefixLength(of s: String) -> Int {
        let u = Array(s.utf8)
        guard u.count >= 8 else { return 0 }
        func digit(_ i: Int) -> Bool { (0x30...0x39).contains(u[i]) }
        guard digit(0), digit(1), u[2] == 0x3A, digit(3), digit(4), u[5] == 0x3A, digit(6), digit(7) else { return 0 }
        return 8
    }
}

/// 訊息預渲染（task 4.1）：CoreText 量測與繪製成 bitmap（可切塊）。量測與繪製共用同一組參數，
/// 因此 Core `layoutItem` 算出的 `width` 與實際 bitmap 寬度一致。
public struct ItemBitmapRenderer: Sendable {
    public var fontSize: CGFloat
    public var padding: CGFloat
    public var heightPt: CGFloat
    public var textureLimitPx: Int
    /// 連結欄位寬度（pt）；只有 `hasLinkSlot` 的訊息才在其最右側繪製迴紋針。
    public var linkSlotWidth: CGFloat
    /// 【假設】字型 PingFang TC（繁中 macOS 內建）；找不到時 CoreText 會 fallback。
    static let fontName = "PingFangTC-Regular"
    /// 時間粗體用的字重【假設：Semibold，需人工目視】。
    static let boldFontName = "PingFangTC-Semibold"

    public init(fontSize: CGFloat, padding: CGFloat, heightPt: CGFloat, textureLimitPx: Int, linkSlotWidth: CGFloat = 0) {
        self.fontSize = fontSize; self.padding = padding; self.heightPt = heightPt; self.textureLimitPx = textureLimitPx
        self.linkSlotWidth = linkSlotWidth
    }

    func font() -> CTFont { CTFontCreateWithName(Self.fontName as CFString, fontSize, nil) }
    func boldFont() -> CTFont { CTFontCreateWithName(Self.boldFontName as CFString, fontSize, nil) }

    /// 量測與繪製共用的屬性字串：前 8 個字元（時間）粗體，其餘一般。
    func attributedString(_ text: String) -> NSAttributedString {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        let out = NSMutableAttributedString(string: text, attributes: [fontKey: font(), colorKey: true])
        let n = ItemText.boldPrefixLength(of: text)
        if n > 0 { out.addAttribute(fontKey, value: boldFont(), range: NSRange(location: 0, length: n)) }   // 時間為 ASCII，UTF-16 長度即字元數
        return out
    }

    func line(_ text: String) -> CTLine { CTLineCreateWithAttributedString(attributedString(text)) }

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
            if item.hasLinkSlot, linkSlotWidth > 0 { Self.drawPaperclip(in: ctx, slot: CGRect(x: item.width - linkSlotWidth, y: 0, width: linkSlotWidth, height: heightPt), color: fg) }
            if let img = ctx.makeImage() { tiles.append(img) }
            x0 += w
        }
        return tiles
    }

    /// 迴紋針圖示（自繪 CGPath，不依賴 SF Symbols；【假設】外觀，需人工目視）。畫在欄位正中，顏色同文字。
    static func drawPaperclip(in ctx: CGContext, slot: CGRect, color: CGFloat) {
        let cx = slot.midX, cy = slot.midY
        let p = CGMutablePath()
        // 兩層 U 形：外圈（半徑 4）與內圈（半徑 2），傾斜 30 度。
        p.move(to: CGPoint(x: -2, y: -3.5))
        p.addLine(to: CGPoint(x: -2, y: 3.5))
        p.addArc(center: CGPoint(x: 0, y: 3.5), radius: 2, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: 2, y: -5))
        p.addArc(center: CGPoint(x: 0, y: -5), radius: 2, startAngle: 0, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: -4, y: 5.5))
        p.addArc(center: CGPoint(x: 0, y: 5.5), radius: 4, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: 4, y: -3))
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: .pi / 8)
        ctx.addPath(p)
        ctx.setStrokeColor(CGColor(red: color, green: color, blue: color, alpha: 1))
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
