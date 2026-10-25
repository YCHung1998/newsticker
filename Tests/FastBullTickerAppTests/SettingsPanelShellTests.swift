import Testing
import AppKit
@testable import FastBullTickerApp

// settings-gear task 7：設定面板殼與位置。執行：swift test --filter SettingsPanelShell
// 只建立 NSPanel 物件並讀回屬性；從不 orderFront，不會在螢幕上出現任何視窗。座標為 Cocoa（原點左下、y 向上）。

@MainActor
@Suite struct SettingsPanelShellTests {
    let cfg = ShellConfig.provisional

    private func makePanel() -> SettingsPanel {
        _ = NSApplication.shared
        return SettingsPanel(config: cfg, content: SettingsPanelContentView())
    }

    // MARK: 殼的屬性

    @Test func styleMaskIsBorderlessNonactivatingOnly() {
        let p = makePanel()
        #expect(PanelSettings(panel: p).styleMask == ["borderless", "nonactivatingPanel"])
        #expect(!p.styleMask.contains(.titled) && !p.styleMask.contains(.hudWindow))
    }

    @Test func neverBecomesKeyOrMainAndDoesNotHideOnDeactivate() {
        let p = makePanel()
        #expect(p.canBecomeKey == false && p.canBecomeMain == false)
        #expect(p.hidesOnDeactivate == false)
        #expect(p.isOpaque == false && p.backgroundColor == .clear)
        #expect(!p.isVisible, "建構後不顯示；測試從不 orderFront")
    }

    @Test func levelIsOneAboveTheTickerAndBehaviorMatchesIt() {
        let p = makePanel()
        #expect(p.level.rawValue == cfg.level.rawValue + 1)
        #expect(p.collectionBehavior == cfg.collectionBehavior)
        #expect(!p.collectionBehavior.contains(.fullScreenPrimary))
        #expect(p.level != NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())), "不是 screenSaver 一類")
    }

    @Test func contentIsASolidDarkRoundedViewNotAVisualEffectView() throws {
        let content = SettingsPanelContentView()
        let p = SettingsPanel(config: cfg, content: content)
        #expect(p.contentView === content)
        func hasEffect(_ v: NSView) -> Bool { v is NSVisualEffectView || v.subviews.contains(where: hasEffect) }
        #expect(!hasEffect(content), "不用毛玻璃")
        let layer = try #require(content.layer)
        #expect(layer.cornerRadius > 0 && layer.backgroundColor != nil)
        #expect((NSColor(cgColor: layer.backgroundColor!)?.alphaComponent ?? 0) == 1, "深色純色")
    }

    // MARK: 位置（純函式）

    private let vis = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 320, height: 400)

    @Test func placedBelowWithSixPointGapAndLeftEdgeAligned() {
        let ticker = CGRect(x: 100, y: 500, width: 648, height: 42)
        let f = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: ticker, screenVisibleFrame: vis, gap: 6)
        #expect(f == CGRect(x: 100, y: 500 - 6 - 400, width: 320, height: 400))
        #expect(SettingsPanelPlacement.defaultGap == 6)
        #expect(SettingsPanelPlacement.frame(panelSize: size, tickerFrame: ticker, screenVisibleFrame: vis) == f, "預設間距 6")
    }

    @Test func exactlyEnoughRoomBelowStaysBelow() {
        // 下方可用高度 = ticker.minY - vis.minY - gap = 406 - 6... 讓它剛好等於面板高度
        let ticker = CGRect(x: 100, y: 406, width: 648, height: 42)
        let f = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: ticker, screenVisibleFrame: vis, gap: 6)
        #expect(f.minY == 0 && f.maxY == 400)
    }

    @Test func notEnoughRoomBelowGoesAbove() {
        let ticker = CGRect(x: 100, y: 100, width: 648, height: 42)
        let f = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: ticker, screenVisibleFrame: vis, gap: 6)
        #expect(f == CGRect(x: 100, y: 100 + 42 + 6, width: 320, height: 400))
        let justShort = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: CGRect(x: 100, y: 405, width: 648, height: 42), screenVisibleFrame: vis, gap: 6)
        #expect(justShort.minY == CGFloat(405 + 42 + 6), "差 1pt 也改放上方")
    }

    @Test func horizontallyClampedIntoVisibleFrame() {
        let right = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: CGRect(x: 1300, y: 500, width: 648, height: 42), screenVisibleFrame: vis)
        #expect(right.maxX == 1440 && right.minX == 1120)
        let left = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: CGRect(x: -50, y: 500, width: 648, height: 42), screenVisibleFrame: vis)
        #expect(left.minX == 0)
    }

    @Test func worksOnASecondaryScreenWithNonZeroOrigin() {
        let v2 = CGRect(x: -1920, y: 100, width: 1920, height: 1000)
        let f = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: CGRect(x: -300, y: 700, width: 648, height: 42), screenVisibleFrame: v2)
        #expect(f.minX == -1920 + 1920 - 320 && f.maxY == 700 - 6)
        #expect(v2.contains(f.origin) && f.maxX <= v2.maxX)
    }

    @Test func neitherSideFitsPicksTheLargerSideAndClamps() {
        let small = CGRect(x: 0, y: 0, width: 1440, height: 450)
        // 下方 194、上方 202：取上方並夾進可視區
        let up = SettingsPanelPlacement.frame(panelSize: CGSize(width: 320, height: 300), tickerFrame: CGRect(x: 100, y: 200, width: 648, height: 42), screenVisibleFrame: small)
        #expect(up.maxY == 450 && up.minY == 150, "取上方（空間較大）並夾到可視區頂端：\(up)")
        // 下方 244、上方 152：取下方並夾進可視區底端
        let down = SettingsPanelPlacement.frame(panelSize: CGSize(width: 320, height: 300), tickerFrame: CGRect(x: 100, y: 250, width: 648, height: 42), screenVisibleFrame: small)
        #expect(down.minY == 0 && down.maxY == 300, "取下方（空間較大）並夾到可視區底端：\(down)")
        #expect(small.contains(up) && small.contains(down))
    }

    @Test func panelTallerThanTheScreenIsPinnedToItsBottom() {
        let tiny = CGRect(x: 0, y: 0, width: 1440, height: 200)
        let f = SettingsPanelPlacement.frame(panelSize: size, tickerFrame: CGRect(x: 100, y: 100, width: 648, height: 42), screenVisibleFrame: tiny)
        #expect(f.minY == 0, "放不下時不產生 NaN／負溢出，貼齊可視區底端：\(f)")
    }

    // MARK: 面板外判斷（純函式）

    @Test func outsideMeansOutsideBothPanelAndTicker() {
        let panel = CGRect(x: 100, y: 94, width: 320, height: 400)
        let ticker = CGRect(x: 100, y: 500, width: 648, height: 42)
        func out(_ x: Double, _ y: Double) -> Bool { SettingsPanelPlacement.isOutside(CGPoint(x: x, y: y), panelFrame: panel, tickerFrame: ticker) }
        #expect(!out(200, 300), "面板內")
        #expect(!out(200, 520), "跑馬燈內")
        #expect(out(50, 300), "面板左側")
        #expect(out(600, 300), "面板右側、跑馬燈之下")
        #expect(out(200, 50), "面板下方")
        #expect(out(900, 520), "跑馬燈右側")
        #expect(out(200, 495), "面板與跑馬燈之間 6pt 的縫隙算面板外")
        #expect(!out(100, 94) && out(420, 494), "半開區間：左下角含、右上角不含")
    }

    // MARK: 靜態掃描

    @Test func settingsSourcesNeverActivateTheAppOrBecomeKey() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let names = ["SettingsPanel", "SettingsPanelPlacement", "SettingsPanelModel", "SettingsPanelContentView", "SettingsPanelController",
                     "SettingsPanelCoordinator", "SettingsPanelWiring", "GlobalMouseDownMonitor"]
        for n in names {
            let url = root.appendingPathComponent("Sources/FastBullTickerApp/\(n).swift")
            let text = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for bad in ["activate" + "(", "makeKey" + "AndOrderFront", "NSApp." + "activate", "orderFront(", "runModal", "NSAlert"] {
                #expect(!text.contains(bad), "\(n).swift 出現 \(bad)")
            }
            #expect(!text.contains("NSVisualEffectView"), "\(n).swift 使用毛玻璃")
        }
    }
}
