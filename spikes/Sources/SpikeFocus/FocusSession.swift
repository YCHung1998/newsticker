import AppKit
import SwiftUI
import SpikeKit

/// 面板內容視圖：記錄 mouseDown/mouseUp 是否送達，並以 performDrag(with:) 拖曳（S2/S5）。
final class DragView: NSView {
    var log: EventLog?
    var usePerformDrag = true
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        log?.write("mouse.down", [("x", String(Int(event.locationInWindow.x))), ("y", String(Int(event.locationInWindow.y)))])
        guard usePerformDrag else { return }
        log?.write("performDrag.begin")
        window?.performDrag(with: event)
        log?.write("performDrag.returned")
    }
    override func mouseUp(with event: NSEvent) { log?.write("mouse.up") }
}

struct FocusOptions {
    var menu = "statusitem"          // statusitem | menubarextra
    var performDrag = true
    var targetBundle = "com.apple.TextEdit"
    var positionFile = "out/s5-position.json"
    var restore = false
    var sampleInterval = 0.5
    var duration = 0.0
}

enum FocusShared { static var session: FocusSession? }

final class FocusSession: NSObject, NSMenuDelegate {
    let log: EventLog
    let cfg: PanelConfig
    let opt: FocusOptions
    var panel: SpikePanel!
    private var statusItem: NSStatusItem?
    private var moveWork: DispatchWorkItem?
    private var sampleTimer: Timer?

    init(log: EventLog, cfg: PanelConfig, opt: FocusOptions) {
        self.log = log; self.cfg = cfg; self.opt = opt
        super.init()
    }

    func start(installStatusItem: Bool) {
        let v = DragView(frame: NSRect(origin: .zero, size: cfg.size))
        v.log = log
        v.usePerformDrag = opt.performDrag
        panel = makeSpikePanel(cfg, content: v,
                               label: "S2/S5 menu=\(opt.menu) nonactivating=\(cfg.nonactivatingAtInit ? "init" : "after") style=\(cfg.hud ? "hud" : "plain")")
        if opt.restore { restorePosition() }
        panel.orderFrontRegardless()
        log.write("config.effective", effectiveFields(panel) + [("mouseDownCanMoveWindow", String(v.mouseDownCanMoveWindow))])

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.log.write("didActivate", [("bundle", a?.bundleIdentifier ?? "nil"), ("pid", String(a?.processIdentifier ?? -1)),
                                            ("name", a?.localizedName ?? "nil")])
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.schedulePositionSave()
        }
        sampleTimer = Timer(timeInterval: opt.sampleInterval, repeats: true) { [weak self] _ in
            let a = NSWorkspace.shared.frontmostApplication
            self?.log.write("frontmost", [("bundle", a?.bundleIdentifier ?? "nil"), ("pid", String(a?.processIdentifier ?? -1))])
        }
        RunLoop.main.add(sampleTimer!, forMode: .common) // 選單展開期間也要持續取樣
        if installStatusItem { buildStatusItem() }
        if opt.duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + opt.duration) { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: S5(c) didMove 存位置（debounce 0.3 秒）
    private func schedulePositionSave() {
        moveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.savePosition() }
        moveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }
    private func savePosition() {
        let o = panel.frame.origin
        let obj: [String: Double] = ["x": Double(o.x), "y": Double(o.y)]
        if let d = try? JSONSerialization.data(withJSONObject: obj) {
            let url = URL(fileURLWithPath: opt.positionFile)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: url)
        }
        log.write("position.saved", [("x", String(format: "%.1f", o.x)), ("y", String(format: "%.1f", o.y))])
    }
    private func restorePosition() {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: opt.positionFile)),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Double],
              let x = o["x"], let y = o["y"] else {
            log.write("position.restore.none"); return
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        log.write("position.restored", [("x", String(format: "%.1f", panel.frame.origin.x)), ("y", String(format: "%.1f", panel.frame.origin.y))])
    }

    // MARK: 選單（NSStatusItem + NSMenu，含內嵌滑桿）
    func setAlpha(_ v: Double) {
        panel.alphaValue = CGFloat(v)
        log.write("slider", [("value", String(format: "%.2f", v))])
    }
    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "S2"
        let menu = NSMenu()
        menu.delegate = self
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        let s = NSSlider(value: 1, minValue: 0.2, maxValue: 1, target: self, action: #selector(sliderChanged(_:)))
        s.isContinuous = true
        s.frame = NSRect(x: 12, y: 4, width: 176, height: 20)
        box.addSubview(s)
        let si = NSMenuItem(); si.view = box
        menu.addItem(si)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""); q.target = self
        menu.addItem(q)
        item.menu = menu
        statusItem = item
    }
    @objc private func sliderChanged(_ s: NSSlider) { setAlpha(s.doubleValue) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func menuWillOpen(_ menu: NSMenu) { log.write("menu.open") }
    func menuDidClose(_ menu: NSMenu) { log.write("menu.close") }
}

// MARK: MenuBarExtra(.window) 對照版本
final class MBEDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusShared.session?.start(installStatusItem: false)
    }
}

struct MBEApp: App {
    @NSApplicationDelegateAdaptor(MBEDelegate.self) var delegate
    @State private var alpha = 1.0
    var body: some Scene {
        MenuBarExtra("S2", systemImage: "circle") {
            VStack(spacing: 8) {
                Slider(value: $alpha, in: 0.2...1)
                    .onChange(of: alpha) { _, v in FocusShared.session?.setAlpha(v) }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding()
            .frame(width: 200)
        }
        .menuBarExtraStyle(.window)
    }
}
