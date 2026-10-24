import AppKit
import CoreText

/// 控制列的符號繪製（nav-layout-tweaks design.md 決定 2、3）。
/// 目的：`<`、`(n/N)`、`>` 的垂直中心以「墨跡外框」對齊控制列中線，而不是依賴字型度量（CATextLayer 把文字貼在 frame 頂端，
/// 不同字級的 ascent／descent 使三者視覺上高低不一）。
public enum ControlStripGlyphs {
    /// chevron 外形（pt）【假設，待使用者目視】：寬 6、高 12、線寬 1.8、圓頭圓角。
    public static let chevronSize = CGSize(width: 6, height: 12)
    public static let chevronLineWidth: CGFloat = 1.8
    /// 位置指示字型【假設】：系統等寬數字 13pt semibold（半形 ASCII，括號字距不像 PingFang 那樣偏寬）。
    public static let indicatorFontSize: CGFloat = 13

    /// chevron 路徑，座標為 `bounds` 內（中心 = `bounds` 中心，所以兩個方向都與按鈕區垂直置中）。
    public static func chevronPath(pointingLeft: Bool, in bounds: CGRect) -> CGPath {
        let cx = bounds.midX, cy = bounds.midY
        let hw = chevronSize.width / 2, hh = chevronSize.height / 2
        let tipX = pointingLeft ? cx - hw : cx + hw, backX = pointingLeft ? cx + hw : cx - hw
        let p = CGMutablePath()
        p.move(to: CGPoint(x: backX, y: cy + hh))
        p.addLine(to: CGPoint(x: tipX, y: cy))
        p.addLine(to: CGPoint(x: backX, y: cy - hh))
        return p
    }

    /// 位置指示位圖（白字、透明底，尺寸 `size`pt @ `scale`）：文字的墨跡外框置於位圖正中央。空字串回傳 nil。
    public static func indicatorImage(text: String, size: CGSize, scale: CGFloat) -> CGImage? {
        guard !text.isEmpty else { return nil }
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let font = NSFont.monospacedDigitSystemFont(ofSize: indicatorFontSize, weight: .semibold)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        let ink = CTLineGetImageBounds(line, ctx)               // 相對文字原點的墨跡外框（pt）
        ctx.textPosition = CGPoint(x: size.width / 2 - ink.midX, y: size.height / 2 - ink.midY)
        CTLineDraw(line, ctx)
        return ctx.makeImage()
    }
}
