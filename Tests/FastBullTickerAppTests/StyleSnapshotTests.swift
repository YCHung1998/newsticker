import Testing
import AppKit
import QuartzCore
@testable import FastBullTickerApp
import FastBullTickerCore

// ticker-style-settings 4.1：離屏渲染（CALayer.render，不開視窗）。設定環境變數 S2_SNAPSHOT_DIR 時把各樣式組合存成 PNG
// 供人眼檢查（Tests/evidence/）；沒設定就只做像素斷言。注意：這不是實機畫面（字體平滑、透明度、視窗合成都不在內）。
// 執行：S2_SNAPSHOT_DIR=Tests/evidence swift test --filter StyleSnapshotTests

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

@MainActor
@Suite struct StyleSnapshotTests {
    private let scale: CGFloat = 2

    /// 先以預設樣式跑到畫面上同時有即時與重播訊息，再套用樣式（顏色等就地重繪），必要時再跑一段讓新字級的訊息出現，最後畫成影像。
    private func render(_ style: TickerStyle, extraSeconds: Double = 0, name: String? = nil) throws -> CGImage {
        let rig = StyleRig()
        rig.snapshot(); rig.driver.step(); rig.live("900", text: "即時：布蘭特原油突然拉升逾 2%")
        // 跑到即時訊息的左緣進到帶子左側附近（畫面上看得到一整則即時訊息，且右側還有重播訊息的尾巴或空隙）
        _ = rig.run(until: {
            let liveSeqs = Set(rig.visibleLive)
            return rig.driver.hitItems().contains { liveSeqs.contains($0.seq) && $0.visualLeft >= 0 && $0.visualLeft < 40 }
        }, max: 400)
        rig.applier.apply(style, source: "snapshot")
        if extraSeconds > 0 { rig.run(seconds: extraSeconds) }
        let w = Int(rig.cfg.panelSize.width * scale), h = Int(rig.cfg.panelSize.height * scale)
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // 灰色格底，讓圓角外的透明處看得出來
        ctx.setFillColor(CGColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        rig.view.layer!.render(in: ctx)
        let img = try #require(ctx.makeImage())
        if let dir = ProcessInfo.processInfo.environment["S2_SNAPSHOT_DIR"], let name {
            let png = try #require(NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("s2-\(name).png"))
        }
        return img
    }

    private func px(_ img: CGImage, _ x: Double, _ y: Double) -> (r: Int, g: Int, b: Int) { rgbBytes(img, x: Int(x * Double(scale)), y: Int(y * Double(scale))) }

    @Test func defaultStyle() throws {
        let img = try render(.default, name: "default")
        // settings-gear：標籤右移齒輪槽寬 28pt，原本量測的 (2, 2) 現在是齒輪槽；標籤紅改在 (30, 2) 量測（x 平移 28，語意不變）。
        #expect(px(img, 30, 2) == (227, 49, 43), "標籤左上角：直角，標籤紅（Generic RGB (0.85, 0.10, 0.13) 轉成 sRGB 位元組）")
        #expect(px(img, 2, 2) == (51, 51, 51), "最左側是齒輪槽（與控制列同色 gray 0.15）")
        #expect(img.width == 1296, "面板寬 648 @2x")
    }

    @Test func largeFont() throws {
        var s = TickerStyle.default; s.fontSize = 24
        _ = try render(s, extraSeconds: 10, name: "font24")
    }

    @Test func cornerRadius21LeavesCornersTransparentToTheBackdrop() throws {
        var s = TickerStyle.default; s.cornerRadius = 21
        let img = try render(s, name: "corner21")
        let corner = px(img, 0.5, 0.5), edgeMid = px(img, 0.5, 21)
        let back = CGColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1).converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
        #expect(corner == (Int((back[0] * 255).rounded()), Int((back[1] * 255).rounded()), Int((back[2] * 255).rounded())), "圓角外露出底色 \(corner)")
        #expect(edgeMid != corner, "左緣中央仍是面板內容 \(edgeMid)")
    }

    @Test func yellowLiveBackgroundWithBlackText() throws {
        var s = TickerStyle.default; s.liveBackground = RGBColor(hex: "#FFE45C")!; s.liveText = RGBColor(hex: "#000000")!
        let img = try render(s, name: "live-yellow")
        let yellowish = countPixels(img, near: (255, 231, 110), tol: 12)
        #expect(yellowish > 5_000, "畫面上有大片黃底 \(yellowish)")
    }

    @Test func labelHidden() throws {
        var s = TickerStyle.default; s.showLabel = false
        let img = try render(s, extraSeconds: 6, name: "no-label")
        #expect(countPixels(img, near: (227, 49, 43), tol: 6) == 0, "沒有標籤紅")
    }

    @Test func customLabelAndEverythingTogether() throws {
        var s = TickerStyle.default
        s.cornerRadius = 12; s.fontSize = 20; s.labelText = "快訊"; s.labelBackground = RGBColor(hex: "#1E7B3C")!
        s.liveBackground = RGBColor(hex: "#FFE45C")!; s.replayBackground = RGBColor(hex: "#102030")!; s.showTime = false
        _ = try render(s, extraSeconds: 14, name: "combo")
    }
}
