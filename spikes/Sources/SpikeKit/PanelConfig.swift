import AppKit

public enum LevelChoice: String, CaseIterable {
    case floating, statusBar
    public var level: NSWindow.Level { self == .floating ? .floating : .statusBar }
}

/// 面板設定的純資料部分。dry-run 只解析並輸出這份「將會套用的生效值」，不建立任何視窗。
public struct PanelConfig {
    public var level: LevelChoice = .floating
    public var joinAllApps = false
    public var stationary = true
    public var nonactivatingAtInit = true
    public var hud = false
    public var size = CGSize(width: 620, height: 42) // 【假設】約 620×42

    public init() {}

    public var collectionBehavior: NSWindow.CollectionBehavior {
        var b: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if stationary { b.insert(.stationary) }
        if joinAllApps { b.insert(.canJoinAllApplications) }
        return b
    }

    /// styleMask 在 init 時的值。
    public var initialStyleMask: NSWindow.StyleMask {
        var m: NSWindow.StyleMask = [.borderless]
        if nonactivatingAtInit { m.insert(.nonactivatingPanel) }
        if hud { m.insert(.hudWindow) }
        return m
    }
    /// styleMask 最終（含事後設定）。
    public var finalStyleMask: NSWindow.StyleMask {
        var m = initialStyleMask
        m.insert(.nonactivatingPanel)
        return m
    }

    public static func behaviorNames(_ b: NSWindow.CollectionBehavior) -> [String] {
        let table: [(String, NSWindow.CollectionBehavior)] = [
            ("canJoinAllApplications", .canJoinAllApplications),
            ("canJoinAllSpaces", .canJoinAllSpaces),
            ("fullScreenAuxiliary", .fullScreenAuxiliary),
            ("fullScreenPrimary", .fullScreenPrimary),
            ("ignoresCycle", .ignoresCycle),
            ("moveToActiveSpace", .moveToActiveSpace),
            ("stationary", .stationary),
        ]
        return table.filter { b.contains($0.1) }.map { $0.0 }.sorted()
    }

    public static func styleNames(_ m: NSWindow.StyleMask) -> [String] {
        var n: [String] = []
        if !m.contains(.titled) { n.append("borderless") }
        if m.contains(.nonactivatingPanel) { n.append("nonactivatingPanel") }
        if m.contains(.hudWindow) { n.append("hudWindow") }
        if m.contains(.titled) { n.append("titled") }
        return n.sorted()
    }

    /// `config.expected` 事件欄位：依參數推得、尚未接觸任何視窗。
    public func expectedFields() -> [(String, String)] {
        [
            ("level", level.rawValue),
            ("level.raw", String(level.level.rawValue)),
            ("behavior", PanelConfig.behaviorNames(collectionBehavior).joined(separator: ",")),
            ("styleMask.init", PanelConfig.styleNames(initialStyleMask).joined(separator: ",")),
            ("styleMask.final", PanelConfig.styleNames(finalStyleMask).joined(separator: ",")),
            ("hidesOnDeactivate", "false"),
            ("canBecomeKey", "false"),
            ("canBecomeMain", "false"),
            ("size", "\(Int(size.width))x\(Int(size.height))"),
        ]
    }

    public static func fromArgs(_ a: Args) throws -> PanelConfig {
        var c = PanelConfig()
        c.level = LevelChoice(rawValue: try a.choice("level", "floating", allowed: ["floating", "statusBar"]))!
        c.joinAllApps = try a.onOff("join-all-apps", false)
        c.stationary = try a.onOff("stationary", true)
        c.nonactivatingAtInit = try a.choice("nonactivating", "init", allowed: ["init", "after"]) == "init"
        c.hud = try a.choice("style", "plain", allowed: ["plain", "hud"]) == "hud"
        return c
    }
    public static let argValueKeys: Set<String> = ["level", "join-all-apps", "stationary", "nonactivating", "style"]
}

public final class SpikePanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

public func makeSpikePanel(_ c: PanelConfig, content: NSView? = nil, label: String = "") -> SpikePanel {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let vf = screen.visibleFrame
    let rect = NSRect(x: vf.midX - c.size.width / 2, y: vf.maxY - c.size.height - 8,
                      width: c.size.width, height: c.size.height)
    let p = SpikePanel(contentRect: rect, styleMask: c.initialStyleMask, backing: .buffered, defer: false)
    if !c.nonactivatingAtInit { p.styleMask.insert(.nonactivatingPanel) } // S2 對照：建立後才設定
    p.hidesOnDeactivate = false
    p.isOpaque = false
    p.hasShadow = false
    p.backgroundColor = .clear
    p.level = c.level.level
    p.collectionBehavior = c.collectionBehavior
    let v = content ?? NSView(frame: NSRect(origin: .zero, size: c.size))
    v.frame = NSRect(origin: .zero, size: c.size)
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.55, alpha: 1).cgColor // 高對比純色
    if !label.isEmpty {
        let t = NSTextField(labelWithString: label)
        t.textColor = .white
        t.font = .boldSystemFont(ofSize: 13)
        t.frame = NSRect(x: 8, y: 10, width: c.size.width - 16, height: 22)
        v.addSubview(t)
    }
    p.contentView = v
    return p
}

/// 從真實面板讀回的生效值（`config.effective`），欄位與 expectedFields 對齊。
public func effectiveFields(_ p: NSPanel) -> [(String, String)] {
    [
        ("level.raw", String(p.level.rawValue)),
        ("behavior", PanelConfig.behaviorNames(p.collectionBehavior).joined(separator: ",")),
        ("styleMask", PanelConfig.styleNames(p.styleMask).joined(separator: ",")),
        ("hidesOnDeactivate", String(p.hidesOnDeactivate)),
        ("canBecomeKey", String(p.canBecomeKey)),
        ("canBecomeMain", String(p.canBecomeMain)),
        ("isOpaque", String(p.isOpaque)),
        ("alphaValue", String(format: "%.2f", p.alphaValue)),
        ("frame", NSStringFromRect(p.frame)),
    ]
}

/// 選單列上只有「Quit」的狀態項目（不需任何權限）。
public final class QuitStatusItem: NSObject {
    private let item: NSStatusItem
    public init(title: String) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = title
        super.init()
        let m = NSMenu()
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        q.target = self
        m.addItem(q)
        item.menu = m
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
