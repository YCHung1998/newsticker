// S1 全螢幕可見性實驗。組合以命令列參數切換；--dry-run 只解析並輸出生效值，不建立任何視窗。
import AppKit
import SpikeKit

let args: Args
let cfg: PanelConfig
do {
    args = try Args(valueKeys: PanelConfig.argValueKeys.union(["duration", "log-file", "log-dir"]), flagKeys: ["dry-run"])
    cfg = try PanelConfig.fromArgs(args)
    if cfg.hud || !cfg.nonactivatingAtInit { throw ArgError("--style/--nonactivating 不屬於 S1（請用 spike-focus）") }
} catch { failUsage("\(error)") }

let log = EventLog(name: "s1", logFile: args.string("log-file"), logDir: args.string("log-dir"))
log.write("start", [("tool", "spike-s1"), ("pid", String(getpid())), ("dry-run", String(args.has("dry-run")))] + SysInfo.swVers())
log.write("config.requested", [
    ("level", cfg.level.rawValue), ("join-all-apps", cfg.joinAllApps ? "on" : "off"), ("stationary", cfg.stationary ? "on" : "off"),
])
log.write("config.expected", cfg.expectedFields())

if args.has("dry-run") {
    log.write("dryrun.done", [("window-created", "false"), ("log", log.path)])
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 永不呼叫 NSApp.activate
let status = QuitStatusItem(title: "S1")
let label = "S1 level=\(cfg.level.rawValue) joinAllApps=\(cfg.joinAllApps ? "on" : "off") stationary=\(cfg.stationary ? "on" : "off")"
let panel = makeSpikePanel(cfg, label: label)
panel.orderFrontRegardless()
log.write("config.effective", effectiveFields(panel))
log.write("screens", [("count", String(NSScreen.screens.count)), ("spacesSeparate", String(NSScreen.screensHaveSeparateSpaces))])

let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    log.write("space.changed", [("visible", String(panel.isVisible)), ("onActiveSpace", String(panel.isOnActiveSpace))])
}
ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    log.write("wake", [("visible", String(panel.isVisible)), ("onActiveSpace", String(panel.isOnActiveSpace))])
}
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    log.write("screens", [("count", String(NSScreen.screens.count)), ("spacesSeparate", String(NSScreen.screensHaveSeparateSpaces))])
}
// 每 5 秒記一次可見狀態（isVisible/isOnActiveSpace 為輔助資料；判定仍以人眼／截圖為準）。
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    log.write("tick", [("visible", String(panel.isVisible)), ("onActiveSpace", String(panel.isOnActiveSpace)),
                       ("occluded", String(!panel.occlusionState.contains(.visible)))])
}
if let d = try? args.double("duration", 0), d > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + d) { NSApplication.shared.terminate(nil) }
}
_ = status
app.run()
