import AppKit

/// 設定面板的視窗殼（settings-gear task 7）：非啟用 `NSPanel`，永不成為 key／main，不呼叫任何 App 啟用 API。
/// 層級比跑馬燈高一級（`config.level + 1`，spec `settings-panel`），`collectionBehavior` 與跑馬燈相同。
/// 顯示用 `orderFrontRegardless`（不啟用 App）；自動測試只讀屬性，從不顯示。
@MainActor
public final class SettingsPanel: NSPanel, SettingsPanelWindowing {
    public let content: SettingsPanelContentView

    public init(config: ShellConfig, content: SettingsPanelContentView) {
        self.content = content
        super.init(contentRect: CGRect(origin: .zero, size: content.contentSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: config.level.rawValue + 1)
        collectionBehavior = config.collectionBehavior
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        contentView = content
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public var panelSize: CGSize { content.contentSize }

    public func show(at frame: CGRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
    public func hide() { orderOut(nil) }
}
