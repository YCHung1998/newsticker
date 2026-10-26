import Testing
import AppKit
import QuartzCore
@testable import FastBullTickerApp
import FastBullTickerCore

/// 帶子最右側的結束 ✕ 圖層（change quit-controls）：hover 才顯示、疊加不改版面、點穿時隱藏。離屏，不開視窗。
@MainActor
@Suite struct QuitViewTests {
    let cfg = ShellConfig.provisional

    @Test func configSlotIsTwentyEightAndFeedsTheHitGeometry() {
        #expect(cfg.quitSlotWidth == 28)
        #expect(cfg.hitGeometry.quitSlotWidth == 28 && cfg.makeHitGeometry(showLabel: false).quitSlotWidth == 28)
        let v = TickerView(config: cfg)
        #expect(HitTesting.target(at: CGPoint(x: cfg.panelSize.width - 5, y: 20), in: v.router.geometry, items: []) == .quit)
    }

    @Test func hiddenUntilThePointerEntersAndHiddenAgainOnExit() {
        let v = TickerView(config: cfg)
        #expect(!v.isQuitVisible && v.quitHidden)
        v.pointerChanged(true)
        #expect(v.isQuitVisible && !v.quitHidden)
        v.pointerChanged(false)
        #expect(!v.isQuitVisible && v.quitHidden)
    }

    @Test func slotIsTheRightmostStripFullHeight() {
        let v = TickerView(config: cfg)
        #expect(v.quitFrame == CGRect(x: cfg.panelSize.width - 28, y: 0, width: 28, height: cfg.panelSize.height))
    }

    @Test func showingDoesNotChangeLayoutOrPanelSize() {
        let v = TickerView(config: cfg)
        let before = v.layoutSnapshot
        let size = v.frame.size
        v.pointerChanged(true)
        let after = v.layoutSnapshot
        #expect(after.clipFrame == before.clipFrame && after.stripFrame == before.stripFrame && after.labelFrame == before.labelFrame)
        #expect(after.gearFrame == before.gearFrame && after.scrollOriginX == before.scrollOriginX)
        #expect(v.frame.size == size && cfg.tapeViewportWidth == 370)
    }

    @Test func clickThroughHidesItEvenWhenThePointerIsInsideAndRestoresAfter() {
        let v = TickerView(config: cfg)
        v.pointerChanged(true)
        v.router.isEnabled = false                 // 點穿模式
        #expect(!v.isQuitVisible && v.quitHidden)
        v.router.isEnabled = true
        #expect(v.isQuitVisible && !v.quitHidden)
    }

    @Test func clickThroughNeverShowsItOnEntry() {
        let v = TickerView(config: cfg)
        v.router.isEnabled = false
        v.pointerChanged(true)
        #expect(v.quitHidden)
    }

    @Test func quitLayersSitOnTopOfEverything() {
        let v = TickerView(config: cfg)
        let subs = v.layer?.sublayers ?? []
        #expect(subs.count >= 3)
        #expect(Array(subs.suffix(2)).allSatisfy { $0.frame == v.quitFrame }, "✕ 的底與符號是最上面兩層（蓋住標籤與帶子）")
    }

    @Test func glyphIsDrawnWhenVisible() throws {
        let v = TickerView(config: cfg)
        func render() throws -> CGImage {
            let scale: CGFloat = 2
            let ctx = try #require(CGContext(data: nil, width: Int(cfg.panelSize.width * scale), height: Int(cfg.panelSize.height * scale), bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.scaleBy(x: scale, y: scale)
            v.layer!.render(in: ctx)
            return try #require(ctx.makeImage())
        }
        func brightPixels(_ img: CGImage) -> Int {
            let x0 = Int((cfg.panelSize.width - 28) * 2)
            guard let d = img.dataProvider?.data, let p = CFDataGetBytePtr(d) else { return -1 }
            var n = 0
            for y in 0..<img.height { for x in x0..<img.width {
                let o = y * img.bytesPerRow + x * 4
                if p[o] > 200 && p[o + 1] > 200 && p[o + 2] > 200 { n += 1 }
            } }
            return n
        }
        let hidden = brightPixels(try render())
        v.pointerChanged(true)
        let shown = brightPixels(try render())
        #expect(shown > hidden + 20, "顯示時右緣多出白色的 ✕ 筆畫（隱藏 \(hidden) → 顯示 \(shown)）")
        if let dir = ProcessInfo.processInfo.environment["QUIT_SNAPSHOT_DIR"] {
            let rep = NSBitmapImageRep(cgImage: try render())
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("quit-hover-offscreen.png"))
        }
    }
}
