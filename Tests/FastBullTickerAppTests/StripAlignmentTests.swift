import Testing
import AppKit
import QuartzCore
@testable import FastBullTickerApp
import FastBullTickerCore

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// 控制列符號對齊（nav-layout-tweaks）：離屏渲染（不開視窗）→ 以像素「墨跡外框」量測 `<`、`(n/N)`、`>` 的垂直中心。
// 標準：三者兩兩相差 ≤ 1 device px（@2x，即 0.5pt），且各自相對控制列高度的中心偏差 ≤ 1 device px。
// 版面無關：以 `layoutSnapshot.stripFrame.minX` 為控制列左緣，再依 `ControlStripLayout` 寬度切三段。
struct InkBox: Equatable { var minRow: Int; var maxRow: Int; var minCol: Int; var maxCol: Int
    /// 垂直中心（device px，y 向下，含邊緣像素：(min + max + 1) / 2）。
    var centerY: Double { Double(minRow + maxRow + 1) / 2 }
    var centerX: Double { Double(minCol + maxCol + 1) / 2 }
}

@MainActor
enum StripRender {
    static let scale = 2

    /// 離屏渲染整個面板 → (RGBA bytes, width, height)。
    static func bitmap(of view: TickerView) throws -> (px: [UInt8], w: Int, h: Int) {
        let cfg = view.config
        let w = Int(cfg.panelSize.width) * scale, h = Int(cfg.panelSize.height) * scale
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        view.layer!.render(in: ctx)
        let data = try #require(ctx.data)
        return (Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4)), w, h)
    }

    /// 在 x ∈ [x0, x1)（pt）內，與控制列背景色差 > `threshold`（0–255 的最大通道差）的像素外框。
    static func ink(_ b: (px: [UInt8], w: Int, h: Int), xRange: Range<Double>, background bg: [UInt8], threshold: Int = 64) -> InkBox? {
        let c0 = Int((xRange.lowerBound * Double(scale)).rounded()), c1 = Int((xRange.upperBound * Double(scale)).rounded())
        var box: InkBox?
        for row in 0..<b.h {
            for col in c0..<c1 {
                let i = (row * b.w + col) * 4
                let d = max(abs(Int(b.px[i]) - Int(bg[0])), abs(Int(b.px[i + 1]) - Int(bg[1])), abs(Int(b.px[i + 2]) - Int(bg[2])))
                guard d > threshold else { continue }
                if var x = box { x.minRow = min(x.minRow, row); x.maxRow = max(x.maxRow, row); x.minCol = min(x.minCol, col); x.maxCol = max(x.maxCol, col); box = x }
                else { box = InkBox(minRow: row, maxRow: row, minCol: col, maxCol: col) }
            }
        }
        return box
    }

    /// 控制列背景色（取控制列內、按鈕左上角附近的一個點）。
    static func stripBackground(_ b: (px: [UInt8], w: Int, h: Int), stripLeftPt: Double) -> [UInt8] {
        let i = (2 * b.w + Int(stripLeftPt * Double(scale)) + 4) * 4
        return [b.px[i], b.px[i + 1], b.px[i + 2]]
    }
}

@MainActor
@Suite struct StripAlignmentTests {
    struct Measured { var prev, ind, next: InkBox; var stripH: Int }

    fileprivate static func measure(style: TickerStyle = .default, text: String = "(4/10)", config: ShellConfig = .provisional) throws -> Measured {
        let view = TickerView(config: config, style: style)
        view.setControlStrip(ControlStripState(text: text, previousEnabled: true, nextEnabled: true))
        let b = try StripRender.bitmap(of: view)
        let left = Double(view.layoutSnapshot.previousFrame.minX)      // 版面無關：以 `<` 按鈕圖層左緣為控制列左緣
        let st = config.strip
        let bg = StripRender.stripBackground(b, stripLeftPt: left)
        let prev = try #require(StripRender.ink(b, xRange: left..<(left + st.buttonWidth), background: bg), "找不到 < 的墨跡")
        let ind = try #require(StripRender.ink(b, xRange: (left + st.buttonWidth)..<(left + st.buttonWidth + st.indicatorWidth), background: bg), "找不到 (n/N) 的墨跡")
        let next = try #require(StripRender.ink(b, xRange: (left + st.buttonWidth + st.indicatorWidth)..<(left + st.controlStripWidth), background: bg), "找不到 > 的墨跡")
        return Measured(prev: prev, ind: ind, next: next, stripH: b.h)
    }

    static func report(_ m: Measured) -> String {
        "centerY(px) <=\(m.prev.centerY) ind=\(m.ind.centerY) >=\(m.next.centerY) stripMid=\(Double(m.stripH) / 2) "
        + "rows <[\(m.prev.minRow),\(m.prev.maxRow)] ind[\(m.ind.minRow),\(m.ind.maxRow)] >[\(m.next.minRow),\(m.next.maxRow)]"
    }

    @Test func threeGlyphsShareOneVerticalCenter() throws {
        let m = try Self.measure()
        let mid = Double(m.stripH) / 2
        #expect(abs(m.prev.centerY - m.ind.centerY) <= 1, Comment(rawValue: Self.report(m)))
        #expect(abs(m.next.centerY - m.ind.centerY) <= 1, Comment(rawValue: Self.report(m)))
        #expect(abs(m.prev.centerY - m.next.centerY) <= 1, Comment(rawValue: Self.report(m)))
        for (name, c) in [("<", m.prev.centerY), ("(n/N)", m.ind.centerY), (">", m.next.centerY)] as [(String, Double)] {
            #expect(abs(c - mid) <= 1, Comment(rawValue: "\(name) 相對控制列垂直置中偏差 \(c - mid) px；\(Self.report(m))"))
        }
    }

    /// 把實測數字印出（供回報與證據 log 使用；不是斷言）。
    @Test func printMeasuredNumbers() throws {
        for (label, style) in [("showLabel", TickerStyle.default), ("noLabel+r21", { var s = TickerStyle.default; s.showLabel = false; s.cornerRadius = 21; return s }())] {
            for t in ["(4/10)", "(1/1)", "(10/10)", "(2/30)"] {
                let m = try Self.measure(style: style, text: t)
                print("ALIGN-REPORT [\(label)] \(t): \(Self.report(m))")
            }
        }
    }

    @Test func alignmentHoldsForOtherTexts() throws {
        for t in ["(1/1)", "(10/10)", "(2/30)"] {
            let m = try Self.measure(text: t)
            let mid = Double(m.stripH) / 2
            #expect(abs(m.prev.centerY - m.ind.centerY) <= 1 && abs(m.next.centerY - m.ind.centerY) <= 1 && abs(m.ind.centerY - mid) <= 1,
                    Comment(rawValue: "\(t): \(Self.report(m))"))
        }
    }

    @Test func alignmentHoldsWithoutLabelAndWithRoundedCorners() throws {
        var s = TickerStyle.default; s.showLabel = false; s.cornerRadius = 21
        let m = try Self.measure(style: s)
        let mid = Double(m.stripH) / 2
        #expect(abs(m.prev.centerY - m.ind.centerY) <= 1 && abs(m.next.centerY - m.ind.centerY) <= 1 && abs(m.ind.centerY - mid) <= 1,
                Comment(rawValue: Self.report(m)))
    }
}
