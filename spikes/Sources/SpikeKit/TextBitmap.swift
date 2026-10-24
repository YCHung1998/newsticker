import Foundation
import CoreText
import CoreGraphics

/// 預渲染訊息為 bitmap（可切塊）。純 CoreText／CoreGraphics，不需視窗，可在 dry-run 驗證寬度。
public enum TextBitmap {
    public static let textureLimitPx = 16384

    public static func font(size: CGFloat) -> CTFont {
        CTFontCreateWithName("PingFangTC-Regular" as CFString, size, nil)
    }
    public static func fontName(size: CGFloat) -> String {
        CTFontCopyFullName(font(size: size)) as String
    }

    public static func line(_ text: String, fontSize: CGFloat) -> CTLine {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    /// 文字寬度（pt）。
    public static func widthPt(_ text: String, fontSize: CGFloat) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, fontSize: fontSize), nil, nil, nil)).rounded(.up)
    }

    public struct Rendered {
        public let tiles: [CGImage]
        public let widthPx: Int
        public let heightPx: Int
        public let tileWidthPx: Int
        /// 最右側 16 欄像素是否有墨跡（偵測截斷／空白）。
        public let rightEdgeHasInk: Bool
    }

    /// 以 `tileWidthPx`（nil = 不切塊）把整行文字畫成一張或多張 CGImage。
    public static func render(_ text: String, fontSize: CGFloat, scale: CGFloat, heightPt: CGFloat,
                              tileWidthPx: Int?) -> Rendered? {
        let ln = line(text, fontSize: fontSize)
        var asc: CGFloat = 0, desc: CGFloat = 0
        let wPt = CGFloat(CTLineGetTypographicBounds(ln, &asc, &desc, nil)).rounded(.up)
        let totalPx = Int((wPt * scale).rounded(.up))
        let hPx = Int((heightPt * scale).rounded(.up))
        let tileW = tileWidthPx ?? totalPx
        var tiles: [CGImage] = []
        var x0 = 0
        var rightInk = false
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        while x0 < totalPx {
            let w = min(tileW, totalPx - x0)
            guard let ctx = CGContext(data: nil, width: w, height: hPx, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -CGFloat(x0) / scale, y: 0)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.textPosition = CGPoint(x: 0, y: (heightPt - (asc + desc)) / 2 + desc)
            CTLineDraw(ln, ctx)
            if x0 + w >= totalPx, let data = ctx.data {
                let bpr = ctx.bytesPerRow
                let p = data.bindMemory(to: UInt8.self, capacity: bpr * hPx)
                for col in max(0, w - 16)..<w {
                    for row in 0..<hPx where p[row * bpr + col * 4 + 3] != 0 { rightInk = true }
                }
            }
            guard let img = ctx.makeImage() else { return nil }
            tiles.append(img)
            x0 += w
        }
        return Rendered(tiles: tiles, widthPx: totalPx, heightPx: hPx, tileWidthPx: tileW, rightEdgeHasInk: rightInk)
    }
}
