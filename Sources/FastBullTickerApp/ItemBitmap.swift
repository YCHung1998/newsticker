import Foundation
import CoreText
import CoreGraphics
import FastBullTickerCore

/// 顯示字串中「時間」的偵測。
/// 只用於**量測**：Core 的 `TextMeasurer` 只收到字串，且 `showTime == true` 時字串一定以 `HH:mm:ss` 開頭，
/// 所以量測端在 `showTime` 為 true 時才用本函式偵測；`showTime == false` 時一律不偵測（本文剛好以 `dd:dd:dd`
/// 開頭也不會被誤判為時間）。**繪製**不偵測，直接用 `PlacedItem.timeString` 的字元數（明確的 `timeBold`）。
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

/// 即時／重播兩組配色（`TickerStyle` 的四個欄位）。
public struct ItemColors: Equatable, Sendable {
    public var liveBackground: RGBColor
    public var liveText: RGBColor
    public var replayBackground: RGBColor
    public var replayText: RGBColor
    public init(liveBackground: RGBColor, liveText: RGBColor, replayBackground: RGBColor, replayText: RGBColor) {
        self.liveBackground = liveBackground; self.liveText = liveText
        self.replayBackground = replayBackground; self.replayText = replayText
    }
    public init(style: TickerStyle) {
        self.init(liveBackground: style.liveBackground, liveText: style.liveText,
                  replayBackground: style.replayBackground, replayText: style.replayText)
    }
    public static let `default` = ItemColors(style: .default)
}

extension RGBColor {
    /// 以 `CGColor(red:green:blue:alpha:)`（Generic RGB 色彩空間）建立——與 app-shell 原型建構標籤紅、空隙底色與黑白 bitmap 的方式相同。
    /// 刻意**不用** sRGB：原型的 Generic RGB (0.85, 0.10, 0.13) 顯示時等於 sRGB 約 (227, 49, 43)，與 sRGB `#D91A21`
    /// (217, 26, 33) 肉眼可辨；為了「不改設定時畫面與原型一致」，色碼以 Generic RGB 解讀（實測數字見 Tests/README.md）。
    var cgColor: CGColor { CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }
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
    /// 配色（`TickerStyle` 提供；預設與原型一致）。
    public var colors: ItemColors
    /// 量測是否把開頭的 `HH:mm:ss` 當時間粗體（對應 `TickerStyle.showTime`）；繪製不看此旗標。
    public var showTime: Bool
    /// 【假設】字型 PingFang TC（繁中 macOS 內建）；找不到時 CoreText 會 fallback。
    static let fontName = "PingFangTC-Regular"
    /// 時間粗體用的字重【假設：Semibold，需人工目視】。
    static let boldFontName = "PingFangTC-Semibold"

    public init(fontSize: CGFloat, padding: CGFloat, heightPt: CGFloat, textureLimitPx: Int, linkSlotWidth: CGFloat = 0,
                colors: ItemColors = .default, showTime: Bool = true) {
        self.fontSize = fontSize; self.padding = padding; self.heightPt = heightPt; self.textureLimitPx = textureLimitPx
        self.linkSlotWidth = linkSlotWidth; self.colors = colors; self.showTime = showTime
    }

    /// 由樣式與 shell 常數建立（字級、配色、是否顯示時間來自 `TickerStyle`）。
    public init(style: TickerStyle, config: ShellConfig) {
        self.init(fontSize: CGFloat(style.fontSize), padding: config.itemPadding, heightPt: config.panelSize.height,
                  textureLimitPx: config.textureLimitPx, linkSlotWidth: CGFloat(config.linkSlotWidth),
                  colors: ItemColors(style: style), showTime: style.showTime)
    }

    func font() -> CTFont { CTFontCreateWithName(Self.fontName as CFString, fontSize, nil) }
    func boldFont() -> CTFont { CTFontCreateWithName(Self.boldFontName as CFString, fontSize, nil) }

    /// 量測與繪製共用的屬性字串：前 `boldLength` 個字元（時間，ASCII，UTF-16 長度即字元數）粗體，其餘一般。
    func attributedString(_ text: String, boldLength n: Int) -> NSAttributedString {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        let out = NSMutableAttributedString(string: text, attributes: [fontKey: font(), colorKey: true])
        if n > 0 { out.addAttribute(fontKey, value: boldFont(), range: NSRange(location: 0, length: n)) }
        return out
    }

    /// 量測用（`showTime` 決定是否偵測開頭時間）。
    func attributedString(_ text: String) -> NSAttributedString { attributedString(text, boldLength: measuredBoldLength(of: text)) }

    func line(_ text: String, boldLength n: Int) -> CTLine { CTLineCreateWithAttributedString(attributedString(text, boldLength: n)) }

    /// 量測端的粗體長度：`showTime` 為 true 才偵測開頭的 `HH:mm:ss`；false 時一律 0。
    func measuredBoldLength(of s: String) -> Int { showTime ? ItemText.boldPrefixLength(of: s) : 0 }

    /// 給 Core 的量測函式：文字寬度（向上取整）加左右留白。
    public var measurer: TextMeasurer {
        let r = self
        return { s in Double(CGFloat(CTLineGetTypographicBounds(r.line(s, boldLength: r.measuredBoldLength(of: s)), nil, nil, nil)).rounded(.up) + 2 * r.padding) }
    }

    /// 切塊寬度（px）：總和 = `ceil(width × scale)`，每塊 ≤ 紋理上限。
    public func tilePlan(width: Double, scale: CGFloat) -> [Int] {
        Tiling.tileWidths(totalPx: Int((CGFloat(width) * scale).rounded(.up)), limit: textureLimitPx)
    }

    /// 渲染一則訊息的顯示字串與時間粗體長度：`timeString` 為空（`showTime == false` 排入的訊息）時只有 `text`、不粗體。
    /// 粗體長度直接取自排入時就決定的 `timeString`（明確資訊，不偵測字串內容）。
    static func displayParts(of item: PlacedItem) -> (text: String, boldLength: Int) {
        item.timeString.isEmpty ? (item.text, 0) : (item.timeString + " " + item.text, item.timeString.utf16.count)
    }

    /// 渲染一則訊息。配色取自 `colors`（預設 live＝白底黑字、replay＝黑底白字）。
    public func render(_ item: PlacedItem, scale: CGFloat) -> [CGImage] {
        let parts = Self.displayParts(of: item)
        let ln = line(parts.text, boldLength: parts.boldLength)
        var asc: CGFloat = 0, desc: CGFloat = 0
        _ = CTLineGetTypographicBounds(ln, &asc, &desc, nil)
        let hPx = Int((heightPt * scale).rounded(.up))
        let live = item.style == .live
        let bg = live ? colors.liveBackground : colors.replayBackground
        let fg = live ? colors.liveText : colors.replayText
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var x0 = 0
        var tiles: [CGImage] = []
        for w in tilePlan(width: item.width, scale: scale) {
            guard let ctx = CGContext(data: nil, width: w, height: hPx, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: hPx))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -CGFloat(x0) / scale, y: 0)
            ctx.setFillColor(fg.cgColor)
            ctx.textPosition = CGPoint(x: padding, y: (heightPt - (asc + desc)) / 2 + desc)
            CTLineDraw(ln, ctx)
            if item.hasLinkSlot, linkSlotWidth > 0 { Self.drawPaperclip(in: ctx, slot: CGRect(x: item.width - linkSlotWidth, y: 0, width: linkSlotWidth, height: heightPt), color: fg) }
            if let img = ctx.makeImage() { tiles.append(img) }
            x0 += w
        }
        return tiles
    }

    /// 迴紋針圖示（自繪 CGPath，不依賴 SF Symbols；【假設】外觀，需人工目視）。畫在欄位正中，顏色同文字。
    static func drawPaperclip(in ctx: CGContext, slot: CGRect, color: RGBColor) {
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
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
