// S4 渲染 A/B：A = NSView.displayLink 逐幀設位置；B = 單一線性 CABasicAnimation。
// --dry-run / --bitmap-width-test：不建立視窗，只輸出設定與 400 字元 CJK 長句的 bitmap 寬度（CoreText/CoreGraphics）。
import AppKit
import QuartzCore
import SpikeKit

let args: Args
let cfg: PanelConfig
var scheme = "A", fpsCap = "none", tile = false
var fontSize = 20.0, speed = 60.0, duration = 0.0, autoHideAt = 0.0, scaleArg = 2.0, tileWidth = 8192.0
var scaleGiven = false, frameObserver = false
do {
    args = try Args(valueKeys: PanelConfig.argValueKeys.union(["scheme", "fps-cap", "tile", "tile-width", "font-size", "speed", "scale",
                                                              "duration", "auto-hide-at", "frame-observer", "log-file", "log-dir"]),
                    flagKeys: ["dry-run", "bitmap-width-test"])
    cfg = try PanelConfig.fromArgs(args)
    scheme = try args.choice("scheme", "A", allowed: ["A", "B"])
    fpsCap = try args.choice("fps-cap", "none", allowed: ["none", "30"])
    tile = try args.onOff("tile", false)
    tileWidth = try args.double("tile-width", 8192)
    fontSize = try args.double("font-size", 20) // 【假設】正式字型大小未定
    speed = try args.double("speed", 60)
    duration = try args.double("duration", 0)
    autoHideAt = try args.double("auto-hide-at", 0)
    scaleGiven = args.string("scale") != nil
    scaleArg = try args.double("scale", 2)
    frameObserver = try args.onOff("frame-observer", false)
    guard fontSize > 0, speed > 0, scaleArg > 0, tileWidth >= 1024 else { throw ArgError("font-size/speed/scale/tile-width out of range") }
} catch { failUsage("\(error)") }

let log = EventLog(name: "render-\(scheme)", logFile: args.string("log-file"), logDir: args.string("log-dir"))
log.write("start", [("tool", "spike-render"), ("pid", String(getpid())), ("dry-run", String(args.has("dry-run") || args.has("bitmap-width-test")))] + SysInfo.swVers())
log.write("config.expected", cfg.expectedFields() + [
    ("scheme", scheme), ("scheme.impl", scheme == "A" ? "NSView.displayLink" : "linear CABasicAnimation"),
    ("fps-cap", fpsCap), ("tile", tile ? "on" : "off"), ("tile-width", String(Int(tileWidth))),
    ("font-size", String(fontSize)), ("font", TextBitmap.fontName(size: CGFloat(fontSize))), ("speed", String(speed)),
    ("scale", scaleGiven ? String(scaleArg) : "screen(default 2 in dry-run)"), ("frame-observer", frameObserver ? "on" : "off"),
])

let tileLimit: Int? = tile ? Int(tileWidth) : nil
func renderAll(scale: CGFloat) -> [TextBitmap.Rendered] {
    var out: [TextBitmap.Rendered] = []
    for (i, m) in FakeMessages.all.enumerated() {
        guard let r = TextBitmap.render(m, fontSize: CGFloat(fontSize), scale: scale, heightPt: 42, tileWidthPx: tileLimit) else {
            log.write("bitmap.error", [("index", String(i))]); continue
        }
        out.append(r)
        log.write("bitmap", [
            ("index", String(i)), ("chars", String(m.count)), ("width_px", String(r.widthPx)), ("height_px", String(r.heightPx)),
            ("exceeds_\(TextBitmap.textureLimitPx)", String(r.widthPx > TextBitmap.textureLimitPx)),
            ("tiles", String(r.tiles.count)), ("max_tile_px", String(r.tiles.map { $0.width }.max() ?? 0)),
            ("right_edge_has_ink", String(r.rightEdgeHasInk)),
        ])
    }
    return out
}

if args.has("dry-run") || args.has("bitmap-width-test") {
    let r = renderAll(scale: CGFloat(scaleArg))
    let mx = r.map { $0.widthPx }.max() ?? 0
    log.write("bitmap.summary", [("max_width_px", String(mx)), ("limit_px", String(TextBitmap.textureLimitPx)),
                                 ("any_exceeds", String(mx > TextBitmap.textureLimitPx)), ("window-created", "false")])
    log.write("dryrun.done", [("window-created", "false"), ("log", log.path)])
    exit(0)
}

// ---- 真實模式（人工輪 5.2）----
final class FrameStats {
    var dts: [Double] = []
    var windowStart = EventLog.uptime()
    func add(_ dt: Double, _ log: EventLog) {
        dts.append(dt)
        if EventLog.uptime() - windowStart >= 10 {
            let n = dts.count
            func c(_ lo: Double, _ hi: Double) -> Int { dts.filter { $0 * 1000 >= lo && $0 * 1000 < hi }.count }
            log.write("frames", [
                ("n", String(n)), ("mean_ms", String(format: "%.2f", dts.reduce(0, +) / Double(max(n, 1)) * 1000)),
                ("max_ms", String(format: "%.2f", (dts.max() ?? 0) * 1000)),
                ("lt12", String(c(0, 12))), ("b12_20", String(c(12, 20))), ("b20_28", String(c(20, 28))),
                ("b28_40", String(c(28, 40))), ("gt40", String(c(40, 1e9))),
            ])
            dts.removeAll(); windowStart = EventLog.uptime()
        }
    }
}

final class RenderController: NSObject {
    var panel: SpikePanel!
    let container = CALayer()
    var link: CADisplayLink?          // A 的驅動，或 B 的幀間隔觀察者
    var lastTs: CFTimeInterval?
    var elapsed = 0.0
    var seqWidth = 0.0
    let stats = FrameStats()
    var statusItem: NSStatusItem!

    func start() {
        let scale = scaleGiven ? CGFloat(scaleArg) : (NSScreen.main?.backingScaleFactor ?? 2)
        log.write("scale", [("value", String(describing: scale))])
        let rendered = renderAll(scale: scale)
        let view = NSView(frame: NSRect(origin: .zero, size: cfg.size))
        panel = makeSpikePanel(cfg, content: view)
        view.layer?.masksToBounds = true
        container.anchorPoint = .zero
        let gapPt = 40.0
        var x = 0.0
        for _ in 0..<2 { // 兩份相同序列接續，供無縫循環（rebase 週期 = seqWidth）
            for r in rendered {
                var tx = x
                for t in r.tiles {
                    let l = CALayer()
                    l.contents = t
                    l.contentsScale = scale
                    l.frame = CGRect(x: tx, y: 0, width: CGFloat(t.width) / scale, height: CGFloat(t.height) / scale)
                    container.addSublayer(l)
                    tx += CGFloat(t.width) / scale
                }
                x += Double(r.widthPx) / Double(scale) + gapPt
            }
            if seqWidth == 0 { seqWidth = x }
        }
        container.frame = CGRect(x: 0, y: 0, width: x, height: cfg.size.height)
        view.layer?.addSublayer(container)
        log.write("tape", [("seq_width_pt", EventLog.f3(seqWidth)), ("total_width_pt", EventLog.f3(x))])

        let range = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        if scheme == "A" {
            link = view.displayLink(target: self, selector: #selector(tick(_:)))
            if fpsCap == "30" { link?.preferredFrameRateRange = range }
            link?.add(to: .main, forMode: .common)
        } else {
            let a = CABasicAnimation(keyPath: "position.x")
            a.fromValue = 0; a.toValue = -seqWidth
            a.duration = seqWidth / speed
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            a.isRemovedOnCompletion = false
            if fpsCap == "30" { a.preferredFrameRateRange = range }
            container.add(a, forKey: "scroll")
            if frameObserver {
                link = view.displayLink(target: self, selector: #selector(tick(_:)))
                link?.add(to: .main, forMode: .common)
            }
        }
        panel.orderFrontRegardless()
        log.write("config.effective", effectiveFields(panel) + [
            ("link.range", link.map { "\($0.preferredFrameRateRange.minimum)-\($0.preferredFrameRateRange.maximum)" } ?? "none"),
        ])
        buildMenu()
        if autoHideAt > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAt) { [weak self] in self?.hideThenShow(seconds: 10) } }
        if duration > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + duration) { NSApplication.shared.terminate(nil) } }
    }

    @objc func tick(_ l: CADisplayLink) {
        let ts = l.timestamp
        if let last = lastTs {
            let dt = ts - last
            stats.add(dt, log)
            if scheme == "A" { elapsed += min(dt, 0.25) }
        }
        lastTs = ts
        if scheme == "A" {
            let x = -(speed * elapsed).truncatingRemainder(dividingBy: seqWidth)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            container.position = CGPoint(x: x, y: 0)
            CATransaction.commit()
        }
    }

    func currentX() -> Double {
        scheme == "A" ? Double(container.position.x) : Double(container.presentation()?.position.x ?? container.position.x)
    }

    func freeze() {
        if scheme == "A" { link?.isPaused = true; lastTs = nil }
        else {
            let t = container.convertTime(CACurrentMediaTime(), from: nil)
            container.speed = 0; container.timeOffset = t
            link?.isPaused = true; lastTs = nil
        }
    }
    func thaw() {
        if scheme == "A" { link?.isPaused = false }
        else {
            let t = container.timeOffset
            container.speed = 1; container.timeOffset = 0; container.beginTime = 0
            container.beginTime = container.convertTime(CACurrentMediaTime(), from: nil) - t
            link?.isPaused = false
        }
    }

    /// 凍結／恢復：記錄隱藏前、顯示後、顯示 0.1 秒後的位置，量化「跳動」。
    @objc func hideThenShow(seconds: Double = 10) {
        let before = currentX()
        log.write("freeze", [("pos_before", EventLog.f3(before))])
        freeze(); panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self else { return }
            let atShow = self.currentX()
            self.panel.orderFrontRegardless(); self.thaw()
            log.write("resume", [("pos_at_show", EventLog.f3(atShow)), ("expected_equal_to_before", EventLog.f3(before))])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let later = self.currentX()
                log.write("resume.after100ms", [("pos", EventLog.f3(later)), ("moved_px", EventLog.f3(before - later)),
                                                    ("expected_px", EventLog.f3(speed * 0.1))])
            }
        }
    }
    @objc func hideMenu() { hideThenShow(seconds: 10) }
    @objc func quit() { NSApplication.shared.terminate(nil) }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "S4:\(scheme)"
        let m = NSMenu()
        let h = NSMenuItem(title: "Hide 10s then show", action: #selector(hideMenu), keyEquivalent: ""); h.target = self
        m.addItem(h)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""); q.target = self
        m.addItem(q)
        statusItem.menu = m
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = RenderController()
controller.start()
app.run()
