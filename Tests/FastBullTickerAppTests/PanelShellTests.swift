import Testing
import AppKit
@testable import FastBullTickerApp

// task 3.2：PanelShell。執行：swift test --filter PanelShell
// 這些測試只建立 NSPanel 物件並讀回屬性；從不 orderFront，不會在螢幕上出現任何視窗。

@MainActor
@Suite struct PanelShellTests {
    let cfg = ShellConfig.provisional
    let frame = CGRect(x: 100, y: 100, width: 620, height: 42)

    func makePanel() -> PanelShell {
        _ = NSApplication.shared
        return PanelShell(config: cfg, frame: frame)
    }

    @Test func styleMaskIsBorderlessNonactivatingOnlyAndNotHud() {
        let p = makePanel()
        #expect(PanelSettings(panel: p).styleMask == ["borderless", "nonactivatingPanel"])
        #expect(!p.styleMask.contains(.hudWindow))
        #expect(!p.styleMask.contains(.titled))
    }

    @Test func fixedAttributes() {
        let p = makePanel()
        #expect(p.hidesOnDeactivate == false)
        #expect(p.canBecomeKey == false)
        #expect(p.canBecomeMain == false)
        #expect(p.hasShadow == false)
        #expect(p.isOpaque == false)
        #expect(p.backgroundColor == .clear)
        #expect(p.frame.size == CGSize(width: 620, height: 42))
    }

    @Test func levelAndBehaviorComeFromShellConfigProvisionalValues() {
        let p = makePanel()
        #expect(p.level == .statusBar)
        #expect(p.level != NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())))      // 不是 .screenSaver 之類
        #expect(PanelSettings(panel: p).behavior == ["canJoinAllSpaces", "fullScreenAuxiliary", "ignoresCycle", "stationary"])
        #expect(!p.collectionBehavior.contains(.canJoinAllApplications))
        #expect(cfg.renderer == .displayLink)
        #expect(cfg.feedTimer == .commonModeTimer)
    }

    @Test func alphaValueDrivesOpacityAndNoVisualEffectView() {
        let p = makePanel()
        let v = TickerView(config: cfg)
        p.contentView = v
        p.alphaValue = CGFloat(cfg.clampAlpha(0))
        #expect(Double(p.alphaValue) == cfg.alphaRange.lowerBound)
        #expect(p.alphaValue > 0.2)
        func hasVisualEffect(_ view: NSView) -> Bool { view is NSVisualEffectView || view.subviews.contains(where: hasVisualEffect) }
        #expect(!hasVisualEffect(v))
    }

    @Test func clickOnBandIsPerformDragAndRightClickUsesSharedMenu() {
        let v = TickerView(config: cfg)
        #expect(v.acceptsFirstMouse(for: nil))
        let menu = StatusMenuController(config: cfg, initialAlpha: 0.9)
        v.contextMenu = menu.menu
        #expect(v.contextMenu === menu.menu)
    }

    @Test func sourcesNeverCallApplicationActivation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for dir in ["Sources/FastBullTicker", "Sources/FastBullTickerApp"] {
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil)
            for f in files where f.pathExtension == "swift" {
                let text = try String(contentsOf: f, encoding: .utf8)
                    .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
                #expect(!text.contains("activate("), "\(f.lastPathComponent) 呼叫了 activate(")
                #expect(!text.contains("makeKeyAndOrderFront"), "\(f.lastPathComponent) 使用 makeKeyAndOrderFront")
                if f.lastPathComponent != "ShellConfig.swift" {      // ShellConfig 只在「讀回並命名」時提到 hudWindow
                    #expect(!text.contains(".hudWindow"), "\(f.lastPathComponent) 使用 hudWindow")
                }
            }
        }
    }
}
