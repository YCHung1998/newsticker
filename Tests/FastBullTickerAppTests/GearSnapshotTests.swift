import Testing
import AppKit
import QuartzCore
@testable import FastBullTickerApp
import FastBullTickerCore

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// settings-gear task 2：離屏渲染（不開視窗）量測齒輪墨跡，並可輸出 PNG（GA_SNAPSHOT_DIR）。
// 注意：離屏 CALayer.render 不等於螢幕上的實機合成結果。執行：swift test --filter GearSnapshot
@MainActor
@Suite struct GearSnapshotTests {
    private static func inkCount(_ b: (px: [UInt8], w: Int, h: Int), xRange: Range<Double>, background bg: [UInt8], threshold: Int = 64) -> Int {
        let c0 = Int(xRange.lowerBound * Double(StripRender.scale)), c1 = Int(xRange.upperBound * Double(StripRender.scale))
        var n = 0
        for row in 0..<b.h { for col in c0..<c1 {
            let i = (row * b.w + col) * 4
            if max(abs(Int(b.px[i]) - Int(bg[0])), abs(Int(b.px[i + 1]) - Int(bg[1])), abs(Int(b.px[i + 2]) - Int(bg[2]))) > threshold { n += 1 }
        } }
        return n
    }
    /// 齒輪槽內、齒輪之外的一個點（pt (26, 21)）的顏色＝槽底色。
    private static func slotBackground(_ b: (px: [UInt8], w: Int, h: Int)) -> [UInt8] {
        let i = (b.h / 2 * b.w + 26 * StripRender.scale) * 4
        return [b.px[i], b.px[i + 1], b.px[i + 2]]
    }

    private static func render(style: TickerStyle = .default, text: String = "(4/10)") throws -> (view: TickerView, bmp: (px: [UInt8], w: Int, h: Int)) {
        let view = TickerView(config: .provisional, style: style)
        view.setControlStrip(ControlStripState(text: text, previousEnabled: true, nextEnabled: true))
        return (view, try StripRender.bitmap(of: view))
    }

    @Test func gearInkIsCenteredInTheSlot() throws {
        let (_, b) = try Self.render()
        let bg = Self.slotBackground(b)
        let g = try #require(StripRender.ink(b, xRange: 0..<28, background: bg), "找不到齒輪墨跡")
        let slotCenterX = 28.0 / 2 * Double(StripRender.scale), slotCenterY = Double(b.h) / 2
        #expect(abs(g.centerX - slotCenterX) <= 1, Comment(rawValue: "centerX \(g.centerX) vs \(slotCenterX)；cols \(g.minCol)...\(g.maxCol)"))
        #expect(abs(g.centerY - slotCenterY) <= 1, Comment(rawValue: "centerY \(g.centerY) vs \(slotCenterY)；rows \(g.minRow)...\(g.maxRow)"))
        #expect(g.minCol > 0 && g.maxCol < 28 * StripRender.scale - 1, "整個齒輪在槽內")
    }

    @Test func gearVerticalCenterMatchesTheChevrons() throws {
        let (v, b) = try Self.render()
        let bg = Self.slotBackground(b)
        let gear = try #require(StripRender.ink(b, xRange: 0..<28, background: bg))
        let left = Double(v.layoutSnapshot.previousFrame.minX)
        let stripBg = StripRender.stripBackground(b, stripLeftPt: left)
        let prev = try #require(StripRender.ink(b, xRange: left..<(left + 24), background: stripBg))
        let next = try #require(StripRender.ink(b, xRange: (left + 76)..<(left + 100), background: stripBg))
        for (n, c) in [("<", prev.centerY), (">", next.centerY)] as [(String, Double)] {
            #expect(abs(gear.centerY - c) <= 1, Comment(rawValue: "gear \(gear.centerY) vs \(n) \(c)"))
        }
    }

    @Test func maxCornerRadiusDoesNotClipTheGear() throws {
        var rounded = TickerStyle.default; rounded.cornerRadius = 21
        let (_, a) = try Self.render()
        let (_, b) = try Self.render(style: rounded)
        let bgA = Self.slotBackground(a), bgB = Self.slotBackground(b)
        let na = Self.inkCount(a, xRange: 0..<28, background: bgA), nb = Self.inkCount(b, xRange: 0..<28, background: bgB)
        #expect(na > 50 && na == nb, "圓角 0／21 的墨跡像素數 \(na)／\(nb)")
    }

    @Test func gearStaysAtTheLeftWhenLabelIsHidden() throws {
        var s = TickerStyle.default; s.showLabel = false
        let (v, b) = try Self.render(style: s)
        let bg = Self.slotBackground(b)
        let g = try #require(StripRender.ink(b, xRange: 0..<28, background: bg))
        #expect(g.maxCol < 28 * StripRender.scale)
        let left = Double(v.layoutSnapshot.previousFrame.minX)
        #expect(left == 28)
        let stripBg = StripRender.stripBackground(b, stripLeftPt: left)
        let prev = try #require(StripRender.ink(b, xRange: left..<(left + 24), background: stripBg))
        #expect(prev.minCol >= 28 * StripRender.scale)
    }

    @Test func hoverChangesTheRenderedBrightness() throws {
        let view = TickerView(config: .provisional)
        let idle = try StripRender.bitmap(of: view)
        view.pointerMoved(to: CGPoint(x: 14, y: 21))
        let hov = try StripRender.bitmap(of: view)
        let bg = Self.slotBackground(idle)
        func sum(_ b: (px: [UInt8], w: Int, h: Int)) -> Int {
            var s = 0
            for row in 0..<b.h { for col in 0..<(28 * StripRender.scale) { s += Int(b.px[(row * b.w + col) * 4]) } }
            return s
        }
        #expect(sum(hov) > sum(idle), "hover 時齒輪較亮（bg \(bg)）")
    }

    /// 輸出 PNG 供人眼檢查（只有設定 GA_SNAPSHOT_DIR 才寫檔）。含訊息的整條面板。
    @Test func writesPanelPNGsWhenAsked() throws {
        var results: [(String, TickerStyle, Bool)] = [("ga-gear-default", .default, false), ("ga-gear-hover", .default, true)]
        var noLabel = TickerStyle.default; noLabel.showLabel = false
        results.append(("ga-gear-nolabel", noLabel, false))
        var round = TickerStyle.default; round.cornerRadius = 21
        results.append(("ga-gear-round21", round, false))
        for (name, style, hover) in results {
            let cfg = ShellConfig.provisional
            let view = TickerView(config: cfg, style: style)
            let clock = ManualClock()
            let sched = TickerScheduler(config: cfg.schedulerConfig(style: style, timeZone: TimeZone(secondsFromGMT: 0)!),
                                        clock: { clock.t }, measurer: view.itemMeasurer)
            let driver = TickerDriver(scheduler: sched, renderer: view)
            let base: Int64 = 1_761_292_800_000
            let texts = ["Fed 官員表示仍需觀察通膨數據", "黃金突破 4,000 美元/盎司", "日經指數收盤上漲，半導體類股領漲", "WTI 原油上漲 1.2%"]
            driver.receive(.snapshot((0..<10).map { i in
                Item(source: "t", id: "\(10 - i)", publishedAtMs: base - Int64(i) * 180_000, text: texts[i % texts.count], url: "https://example.com/\(i)")
            }))
            driver.step()
            for _ in 0..<40 { clock.t += 0.25; driver.step() }
            if hover { view.pointerMoved(to: CGPoint(x: 14, y: 21)) }
            let b = try StripRender.bitmap(of: view)
            #expect(b.w == Int(cfg.panelSize.width) * StripRender.scale)
            if let dir = ProcessInfo.processInfo.environment["GA_SNAPSHOT_DIR"] {
                let ctxData = Data(b.px)
                let provider = try #require(CGDataProvider(data: ctxData as CFData))
                let img = try #require(CGImage(width: b.w, height: b.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: b.w * 4,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                let png = try #require(NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }
}
