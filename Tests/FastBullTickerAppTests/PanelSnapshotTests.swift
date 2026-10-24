import Testing
import AppKit
import QuartzCore
@testable import FastBullTickerApp
import FastBullTickerCore

// 離屏渲染（不開視窗）：把 TickerView 的圖層樹畫成 PNG 供人眼檢查外觀（粗體時間、迴紋針、控制列）。
// 只有設定環境變數 N3_SNAPSHOT_DIR 時才輸出；沒設定就略過寫檔（測試仍檢查繪出的影像非空）。
// 注意：這是離屏 CALayer.render，不等於螢幕上的實際合成結果（字體平滑、透明度、Space 行為都不在內）。
@MainActor
@Suite struct PanelSnapshotTests {
    @Test func offscreenPanelRendersAndOptionallyWritesPNG() throws {
        let cfg = ShellConfig.provisional
        let view = TickerView(config: cfg)
        let clock = ManualClock()
        let sched = TickerScheduler(config: cfg.schedulerConfig(timeZone: TimeZone(secondsFromGMT: 0)!),
                                    clock: { clock.t }, measurer: view.itemMeasurer)
        let driver = TickerDriver(scheduler: sched, renderer: view)
        let base: Int64 = 1_761_292_800_000
        let texts = ["Fed 官員表示仍需觀察通膨數據", "黃金突破 4,000 美元/盎司", "日經指數收盤上漲，半導體類股領漲", "WTI 原油上漲 1.2%", "比特幣站上 11 萬美元"]
        driver.receive(.snapshot((0..<10).map { i in
            Item(source: "t", id: "\(10 - i)", publishedAtMs: base - Int64(i) * 180_000, text: texts[i % texts.count],
                 url: i % 3 == 2 ? nil : "https://example.com/demo/\(10 - i)")
        }))
        driver.step()
        var n = 0
        // 走到「有連結的訊息其迴紋針完整出現在控制列左側」的畫面。
        func linkVisible() -> Bool {
            driver.hitItems().contains { $0.hasLinkSlot && cfg.labelWidth + $0.visualLeft + $0.width < 500 && $0.visualLeft > 0 }
        }
        while !(linkVisible() && (driver.scheduler.readingPosition?.index ?? 0) >= 3) && n < 800 { clock.t += 0.25; driver.step(); n += 1 }
        #expect(view.layerCount > 0)
        let scale: CGFloat = 2
        let w = Int(cfg.panelSize.width * scale), h = Int(cfg.panelSize.height * scale)
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: scale, y: scale)
        view.layer!.render(in: ctx)
        let img = try #require(ctx.makeImage())
        #expect(img.width == w)
        if let dir = ProcessInfo.processInfo.environment["N3_SNAPSHOT_DIR"] {
            let rep = NSBitmapImageRep(cgImage: img)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("n3-panel-offscreen.png"))
        }
    }
}
