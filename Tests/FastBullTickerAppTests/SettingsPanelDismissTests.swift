import Testing
import AppKit
@testable import FastBullTickerApp

// settings-gear task 9：面板開關與全域滑鼠監看。執行：swift test --filter SettingsPanelDismiss
// 全部使用假視窗與假監看器：**不安裝真實全域監看器、不開真實視窗**。
// 合成的 NSEvent 只丟給 TickerView.mouseDown（沒有視窗、不進事件佇列）。

@MainActor
private final class FakeWindow: SettingsPanelWindowing {
    var panelSize = CGSize(width: 320, height: 400)
    private(set) var frame: CGRect = .zero
    private(set) var isShown = false
    private(set) var showCalls: [CGRect] = [], hideCalls = 0
    func show(at frame: CGRect) { self.frame = frame; isShown = true; showCalls.append(frame) }
    func hide() { isShown = false; hideCalls += 1 }
    func move(to frame: CGRect) { self.frame = frame }
}

@MainActor
private final class FakeMonitor: MouseDownMonitoring {
    private(set) var installCount = 0, removeCount = 0
    private var handler: ((CGPoint) -> Void)?
    var isInstalled: Bool { handler != nil }
    func install(_ handler: @escaping (CGPoint) -> Void) { installCount += 1; self.handler = handler }
    func remove() { removeCount += 1; handler = nil }
    /// 模擬「在其他 App 或桌面上按下滑鼠」（真實監看器只會在這種情況回呼）。
    func mouseDown(at p: CGPoint) { handler?(p) }
}

@MainActor
private final class Rig {
    let window = FakeWindow()
    let monitor = FakeMonitor()
    var willOpen = 0
    var tickerFrame = CGRect(x: 100, y: 500, width: 648, height: 42)
    var visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    lazy var coordinator: SettingsPanelCoordinator = {
        let c = SettingsPanelCoordinator(window: window, monitor: monitor)
        c.tickerFrame = { [unowned self] in tickerFrame }
        c.visibleFrame = { [unowned self] in visible }
        c.onWillOpen = { [unowned self] in willOpen += 1 }
        return c
    }()
    var insidePanel: CGPoint { CGPoint(x: window.frame.midX, y: window.frame.midY) }
}

@MainActor
@Suite struct SettingsPanelDismissTests {
    @Test func toggleOpensBelowTheTickerAndInstallsTheMonitor() {
        let r = Rig()
        r.coordinator.toggle()
        #expect(r.coordinator.isOpen && r.window.isShown && r.willOpen == 1)
        #expect(r.window.frame == SettingsPanelPlacement.frame(panelSize: r.window.panelSize, tickerFrame: r.tickerFrame, screenVisibleFrame: r.visible))
        #expect(r.monitor.installCount == 1 && r.monitor.isInstalled)
    }

    @Test func secondToggleClosesAndRemovesTheMonitor() {
        let r = Rig()
        r.coordinator.toggle(); r.coordinator.toggle()
        #expect(!r.coordinator.isOpen && !r.window.isShown)
        #expect(r.monitor.installCount == 1 && r.monitor.removeCount == 1 && !r.monitor.isInstalled)
    }

    @Test func clickOutsideClosesAndRemovesTheMonitor() {
        let r = Rig()
        r.coordinator.open()
        r.monitor.mouseDown(at: CGPoint(x: 1300, y: 100))
        #expect(!r.coordinator.isOpen && !r.window.isShown && r.monitor.removeCount == 1)
    }

    @Test func clickInsideThePanelKeepsItOpen() {
        let r = Rig()
        r.coordinator.open()
        r.monitor.mouseDown(at: r.insidePanel)
        r.monitor.mouseDown(at: CGPoint(x: r.window.frame.minX, y: r.window.frame.minY))
        #expect(r.coordinator.isOpen && r.window.isShown && r.monitor.removeCount == 0)
    }

    @Test func globalClickOverTheTickerRectDoesNotCloseByItself() {
        // 全域監看器看不到本 App 視窗內的事件；若點在跑馬燈矩形內（例如點穿模式），純函式視為「非面板外」
        let r = Rig()
        r.coordinator.open()
        r.monitor.mouseDown(at: CGPoint(x: r.tickerFrame.midX, y: r.tickerFrame.midY))
        #expect(r.coordinator.isOpen)
    }

    @Test func closeIsIdempotentAndReopeningInstallsExactlyOneMonitorEachTime() {
        let r = Rig()
        r.coordinator.close()                                // 未開時關閉：什麼都不做
        #expect(r.monitor.removeCount == 0 && r.window.hideCalls == 0)
        for _ in 0..<3 { r.coordinator.open(); r.coordinator.open(); r.coordinator.close(); r.coordinator.close() }
        #expect(r.monitor.installCount == 3 && r.monitor.removeCount == 3 && !r.monitor.isInstalled, "不洩漏、不重複安裝")
        #expect(r.window.showCalls.count == 3 && r.window.hideCalls == 3 && r.willOpen == 3)
    }

    @Test func closeButtonCommandClosesThePanel() {
        let r = Rig()
        r.coordinator.open()
        r.coordinator.close()                                // SettingsPanelController.onClose 接到這裡（組裝測試另驗）
        #expect(!r.coordinator.isOpen && !r.monitor.isInstalled)
    }

    @Test func tickerHiddenOrQuitClosesThePanel() {
        let r = Rig()
        r.coordinator.open()
        r.coordinator.tickerWillHide()
        #expect(!r.coordinator.isOpen && !r.monitor.isInstalled)
        r.coordinator.open()
        r.coordinator.shutdown()
        #expect(!r.coordinator.isOpen && !r.monitor.isInstalled && r.monitor.removeCount == 2)
        r.coordinator.tickerWillHide()                       // 未開時呼叫無副作用
        #expect(r.monitor.removeCount == 2)
    }

    @Test func tickerPressOutsideTheGearClosesButGearPressDoesNot() {
        let r = Rig()
        r.coordinator.open()
        r.coordinator.tickerPointerDown(onGear: true)
        #expect(r.coordinator.isOpen, "齒輪上的按下不關閉（避免關了又被 onGear 重開）")
        r.coordinator.tickerPointerDown(onGear: false)
        #expect(!r.coordinator.isOpen && !r.monitor.isInstalled)
    }

    @Test func layoutChangeWhileOpenRepositions() {
        let r = Rig()
        r.coordinator.open()
        r.window.panelSize = CGSize(width: 320, height: 450)
        r.coordinator.contentSizeChanged()
        #expect(r.window.frame == SettingsPanelPlacement.frame(panelSize: CGSize(width: 320, height: 450), tickerFrame: r.tickerFrame, screenVisibleFrame: r.visible))
        r.coordinator.close()
        let shows = r.window.showCalls.count
        r.coordinator.contentSizeChanged()
        #expect(r.window.showCalls.count == shows && !r.window.isShown, "關閉時不重新顯示")
    }

    @Test func opensAboveWhenTheTickerIsNearTheBottom() {
        let r = Rig()
        r.tickerFrame = CGRect(x: 100, y: 20, width: 648, height: 42)
        r.coordinator.open()
        #expect(r.window.frame.minY == CGFloat(20 + 42 + 6))
    }

    // MARK: 與真實 TickerView 路由的整合（合成事件；沒有視窗）

    private func mouseEvent(_ type: NSEvent.EventType, x: Double) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 21), modifierFlags: [], timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func wireTicker(_ r: Rig) -> TickerView {
        _ = NSApplication.shared
        let v = TickerView(config: .provisional)
        v.router.onGear = { [unowned r] in r.coordinator.toggle() }
        v.onTickerPointerDown = { [unowned r] onGear in r.coordinator.tickerPointerDown(onGear: onGear) }
        return v
    }

    @Test func clickingTheGearTogglesExactlyOnceEachTime() {
        let r = Rig(); let v = wireTicker(r)
        v.mouseDown(with: mouseEvent(.leftMouseDown, x: 14)); v.mouseUp(with: mouseEvent(.leftMouseUp, x: 14))
        #expect(r.coordinator.isOpen && r.monitor.installCount == 1)
        v.mouseDown(with: mouseEvent(.leftMouseDown, x: 14)); v.mouseUp(with: mouseEvent(.leftMouseUp, x: 14))
        #expect(!r.coordinator.isOpen && r.monitor.installCount == 1 && r.monitor.removeCount == 1, "再點一次＝關閉，沒有關了又重開")
    }

    @Test func pressingOnTheTapeClosesThePanelButStillReachesTheRouter() {
        let r = Rig(); let v = wireTicker(r)
        var nexts = 0
        v.router.onNext = { nexts += 1 }
        r.coordinator.open()
        let next = Double(v.layoutSnapshot.nextFrame.midX)
        v.mouseDown(with: mouseEvent(.leftMouseDown, x: next))
        #expect(!r.coordinator.isOpen, "點在跑馬燈非齒輪區域視為面板外")
        v.mouseUp(with: mouseEvent(.leftMouseUp, x: next))
        #expect(nexts == 1, "既有導覽行為不被阻擋")
    }

    @Test func rightClickOnTheTickerAlsoCloses() {
        let r = Rig(); let v = wireTicker(r)
        r.coordinator.open()
        v.rightMouseDown(with: mouseEvent(.rightMouseDown, x: 300))
        #expect(!r.coordinator.isOpen)
    }

    // MARK: 真實監看器的設定與靜態守衛

    @Test func realMonitorMaskIsMouseDownOnly() {
        #expect(GlobalMouseDownMonitor.eventMask == [.leftMouseDown, .rightMouseDown])
        #expect(!GlobalMouseDownMonitor.eventMask.contains(.keyDown) && !GlobalMouseDownMonitor.eventMask.contains(.leftMouseUp))
        // 只建構、不安裝：從不呼叫 install
        let m = GlobalMouseDownMonitor()
        #expect(!m.isInstalled)
    }

    @Test func sourcesHaveNoAccessibilityOrEventTapOrKeyboardMonitoring() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources")
        var scanned = 0
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let f = e?.nextObject() as? URL {
            guard f.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: f, encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            scanned += 1
            for bad in ["AXIsProcess" + "Trusted", "CGEvent" + "Tap", "AXUIElement", "addLocalMonitor" + "ForEvents"] {
                #expect(!text.contains(bad), "\(f.lastPathComponent) 出現 \(bad)")
            }
            if f.lastPathComponent != "GlobalMouseDownMonitor.swift" {
                #expect(!text.contains("addGlobalMonitor" + "ForEvents"), "\(f.lastPathComponent) 在監看器以外的檔案建立全域監看")
            } else {
                #expect(text.contains("addGlobalMonitor" + "ForEvents(matching: Self.eventMask"))
                #expect(!text.contains(".keyDown") && !text.contains(".keyUp") && !text.contains(".flagsChanged"))
            }
        }
        #expect(scanned > 20)
    }
}
