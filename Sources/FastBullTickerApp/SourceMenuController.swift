import AppKit

/// 「來源」子選單的 `NSMenu` 呈現層（change source-switcher）。項目由 `SourceMenuModel` 產生；
/// 選單展開前（`menuNeedsUpdate`）重新向 `provider` 要一次，所以手動編輯 `sources.json` 之後再展開就看得到。
/// 不建立視窗、不使用 `NSAlert`、不啟用 App。
@MainActor
public final class SourceMenuController: NSObject, NSMenuDelegate {
    public let menu = NSMenu(title: "來源")
    /// 目前的項目；未接上 App 時顯示一行停用的提示。
    public var provider: () -> [SourceMenuItem] = {
        [SourceMenuItem(kind: .notice, title: "找不到抓取程式，無法切換來源", checked: false, enabled: false)]
    }
    public var onSelect: (String) -> Void = { _ in }
    public var onOpenFile: () -> Void = {}
    public private(set) var items: [SourceMenuItem] = []

    public override init() {
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuild()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    public func rebuild() {
        items = provider()
        menu.removeAllItems()
        for it in items {
            switch it.kind {
            case .separator:
                menu.addItem(.separator())
            case .notice:
                let m = NSMenuItem(title: it.title, action: nil, keyEquivalent: "")
                m.isEnabled = false
                menu.addItem(m)
            case .source, .openFile:
                let m = NSMenuItem(title: it.title, action: #selector(clicked(_:)), keyEquivalent: "")
                m.target = self
                m.state = it.checked ? .on : .off
                m.isEnabled = it.enabled
                m.tag = menu.items.count
                menu.addItem(m)
            }
        }
    }

    @objc private func clicked(_ sender: NSMenuItem) {
        guard sender.isEnabled, sender.tag < items.count else { return }
        switch items[sender.tag].kind {
        case .source(let id): onSelect(id)
        case .openFile: onOpenFile()
        case .separator, .notice: break
        }
    }
}
