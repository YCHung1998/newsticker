// S2（不搶 Focus）／S5（面板補充）實驗程式。--dry-run 只輸出生效值，不建立視窗。
import AppKit
import SpikeKit

let args: Args
let cfg: PanelConfig
var opt = FocusOptions()
do {
    args = try Args(valueKeys: PanelConfig.argValueKeys.union(["menu", "drag", "target-bundle", "position-file", "restore",
                                                              "sample-interval", "duration", "log-file", "log-dir"]),
                    flagKeys: ["dry-run"])
    cfg = try PanelConfig.fromArgs(args)
    opt.menu = try args.choice("menu", "statusitem", allowed: ["statusitem", "menubarextra"])
    opt.performDrag = try args.choice("drag", "performdrag", allowed: ["performdrag", "none"]) == "performdrag"
    opt.targetBundle = args.string("target-bundle") ?? opt.targetBundle
    opt.positionFile = args.string("position-file") ?? opt.positionFile
    opt.restore = try args.onOff("restore", false)
    opt.sampleInterval = try args.double("sample-interval", 0.5)
    guard opt.sampleInterval > 0, opt.sampleInterval <= 1 else { throw ArgError("--sample-interval must be in (0, 1] seconds") }
    opt.duration = try args.double("duration", 0)
} catch { failUsage("\(error)") }

let log = EventLog(name: "focus", logFile: args.string("log-file"), logDir: args.string("log-dir"))
log.write("start", [("tool", "spike-focus"), ("pid", String(getpid())), ("dry-run", String(args.has("dry-run")))] + SysInfo.swVers())
log.write("config.requested", [
    ("menu", opt.menu), ("nonactivating", cfg.nonactivatingAtInit ? "init" : "after"), ("style", cfg.hud ? "hud" : "plain"),
    ("drag", opt.performDrag ? "performdrag" : "none"), ("target-bundle", opt.targetBundle),
    ("restore", opt.restore ? "on" : "off"), ("position-file", opt.positionFile), ("sample-interval", String(opt.sampleInterval)),
])
log.write("config.expected", cfg.expectedFields() + [("menu", opt.menu), ("sample-interval", String(opt.sampleInterval))])
if args.has("dry-run") {
    log.write("dryrun.done", [("window-created", "false"), ("log", log.path)])
    exit(0)
}
log.write("self", [("pid", String(getpid()))])

let session = FocusSession(log: log, cfg: cfg, opt: opt)
FocusShared.session = session
if opt.menu == "menubarextra" {
    MBEApp.main() // SwiftUI 生命週期；面板在 MBEDelegate.applicationDidFinishLaunching 建立
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // 永不呼叫 NSApp.activate
    session.start(installStatusItem: true)
    app.run()
}
