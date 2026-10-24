// S3 選單展開期間補料計時器。--dry-run：只輸出生效設定；--headless-selftest：不建立視窗，
// 在 NSEventTrackingRunLoopMode 中模擬「選單追蹤」以檢驗三種計時器行為（模擬，不取代 4.2 人工實測）。
import AppKit
import QuartzCore
import SpikeKit

let args: Args
var kind = TimerKind.default
var interval = 1.5, speed = 60.0, targetGap = 300.0, duration = 0.0, selftestSeconds = 8.0
var selftestMode = "eventTracking"
do {
    args = try Args(valueKeys: ["timer", "interval", "speed", "target-gap", "duration", "selftest-mode", "selftest-seconds",
                                "log-file", "log-dir"], flagKeys: ["dry-run", "headless-selftest"])
    kind = TimerKind(rawValue: try args.choice("timer", "default", allowed: ["default", "common", "dispatch"]))!
    interval = try args.double("interval", 1.5)
    speed = try args.double("speed", 60)
    targetGap = try args.double("target-gap", 300)
    duration = try args.double("duration", 0)
    selftestSeconds = try args.double("selftest-seconds", 8)
    selftestMode = try args.choice("selftest-mode", "eventTracking", allowed: ["default", "eventTracking"])
    guard interval > 0, speed > 0, targetGap > 0 else { throw ArgError("interval/speed/target-gap must be > 0") }
} catch { failUsage("\(error)") }

let log = EventLog(name: "s3", logFile: args.string("log-file"), logDir: args.string("log-dir"))
log.write("start", [("tool", "spike-s3"), ("pid", String(getpid())), ("dry-run", String(args.has("dry-run")))] + SysInfo.swVers())
let modeDesc: [TimerKind: String] = [.default: "RunLoop.main:.default", .common: "RunLoop.main:.common", .dispatch: "DispatchSourceTimer:main-queue"]
log.write("config.expected", [
    ("timer", kind.rawValue), ("registration", modeDesc[kind]!), ("interval", String(interval)), ("speed", String(speed)),
    ("message_width", String(speed * interval)), ("target_gap", String(targetGap)), ("view_width", "620"),
])
if args.has("dry-run") {
    log.write("dryrun.done", [("window-created", "false"), ("log", log.path)])
    exit(0)
}

let tape = TapeModel(speed: speed, viewWidth: 620, interval: interval, targetGap: targetGap, t0: EventLog.uptime())
let refiller = Refiller(kind: kind, tape: tape, log: log)

if args.has("headless-selftest") {
    // 不建立任何視窗：用 NSApplication(.prohibited) 讓 AppKit 註冊 common mode 後，在指定 mode 內跑 run loop。
    NSApplication.shared.setActivationPolicy(.prohibited)
    refiller.start()
    let simulate = selftestMode == "eventTracking"
    let mode = simulate ? CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString) : CFRunLoopMode.defaultMode!
    if simulate { log.write("menu.open", [("t", EventLog.f3(EventLog.uptime())), ("simulated", "true")]) }
    let end = EventLog.uptime() + selftestSeconds
    while EventLog.uptime() < end {
        let r = CFRunLoopRunInMode(mode, 0.05, false)
        if r == .finished { usleep(20_000) }
    }
    if simulate {
        log.write("menu.close", [("t", EventLog.f3(EventLog.uptime())), ("simulated", "true")])
        let drain = EventLog.uptime() + 1.0 // 選單關閉後回到預設 mode，讓被擱置的計時器有機會觸發
        while EventLog.uptime() < drain { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
    }
    refiller.stop()
    log.write("selftest.done", [("mode", selftestMode), ("timer", kind.rawValue), ("window-created", "false")])
    exit(0)
}

// ---- 真實模式（人工輪 4.2）----
final class S3Controller: NSObject, NSMenuDelegate {
    var panel: SpikePanel!
    let container = CALayer()
    var statusItem: NSStatusItem!

    func start() {
        var cfg = PanelConfig(); cfg.level = .floating
        let v = NSView(frame: NSRect(origin: .zero, size: cfg.size))
        panel = makeSpikePanel(cfg, content: v)
        v.layer?.masksToBounds = true
        container.anchorPoint = .zero
        container.frame = CGRect(x: 0, y: 0, width: 1, height: cfg.size.height)
        v.layer?.addSublayer(container)
        tape.t0 = EventLog.uptime()
        tape.contentEnd = 0
        addMessages(tape.refill(now: tape.t0)) // 初始內容：從 x=0 鋪到 viewWidth + targetGap
        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = 0; anim.toValue = -speed * 1e5
        anim.duration = 1e5; anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false; anim.fillMode = .forwards
        container.add(anim, forKey: "scroll")
        refiller.onAppend = { [weak self] in self?.addMessages($0) }
        panel.orderFrontRegardless()
        log.write("config.effective", effectiveFields(panel))
        buildMenu()
        refiller.start()
        if duration > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + duration) { NSApplication.shared.terminate(nil) } }
    }

    func addMessages(_ items: [(Int, Double)]) {
        for (idx, x) in items {
            let l = CALayer()
            l.frame = CGRect(x: x, y: 2, width: tape.messageWidth - 4, height: 38)
            l.backgroundColor = (idx % 2 == 0 ? NSColor.systemBlue : NSColor.systemOrange).cgColor
            let t = CATextLayer()
            t.string = "#\(idx)"; t.fontSize = 14; t.foregroundColor = NSColor.white.cgColor
            t.frame = CGRect(x: 6, y: 8, width: 80, height: 20)
            l.addSublayer(t)
            container.addSublayer(l)
        }
        // 清掉已捲出左側的圖層
        let scrolled = tape.speed * (EventLog.uptime() - tape.t0)
        for s in container.sublayers ?? [] where s.frame.maxX < scrolled - 100 { s.removeFromSuperlayer() }
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "S3:\(kind.rawValue)"
        let menu = NSMenu(); menu.delegate = self
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        let s = NSSlider(value: 1, minValue: 0.2, maxValue: 1, target: self, action: #selector(slid(_:)))
        s.isContinuous = true; s.frame = NSRect(x: 12, y: 4, width: 176, height: 20)
        box.addSubview(s)
        let si = NSMenuItem(); si.view = box; menu.addItem(si)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""); q.target = self
        menu.addItem(q)
        statusItem.menu = menu
    }
    @objc func slid(_ s: NSSlider) {
        panel.alphaValue = CGFloat(s.doubleValue)
        log.write("slider", [("t", EventLog.f3(EventLog.uptime())), ("value", String(format: "%.2f", s.doubleValue))])
    }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    func menuWillOpen(_ menu: NSMenu) { log.write("menu.open", [("t", EventLog.f3(EventLog.uptime()))]) }
    func menuDidClose(_ menu: NSMenu) { log.write("menu.close", [("t", EventLog.f3(EventLog.uptime()))]) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = S3Controller()
controller.start()
app.run()
