import AppKit

/// 把選單動作接到 `StyleStore` 與 `FileOpener`。不碰任何視窗。
@MainActor
public final class StyleActionRunner {
    private let store: StyleStore
    private let opener: FileOpener
    private let log: AppLog?
    public private(set) var openedFiles: [URL] = []

    public init(store: StyleStore, opener: FileOpener, log: AppLog?) {
        self.store = store; self.opener = opener; self.log = log
    }

    public func run(_ action: StyleMenuAction) {
        switch action {
        case .openFile:
            guard store.ensureFileExists() else {
                log?.write("style: error 無法建立樣式檔，不開啟（\(store.lastWriteError ?? "?")）")
                return
            }
            let ok = opener.open(store.fileURL)
            openedFiles.append(store.fileURL)
            log?.write("style: open file requested ok=\(ok)")
        case .resetToDefault:
            store.resetToDefault()
            log?.write("style: reset to default requested")
        default:
            store.update { StyleMenuModel.apply(action, to: &$0) }
        }
    }
}

/// 「樣式」子選單的 `NSMenu` 呈現層（5.1）。項目由 `StyleMenuModel.entries` 產生；選單展開前（`menuNeedsUpdate`）
/// 依目前生效樣式重建，所以熱重載或手動改檔之後再展開，勾選與滑桿位置都是最新的。
/// 不建立任何視窗、不使用 `NSAlert`、不啟用 App。
@MainActor
public final class StyleMenuController: NSObject, NSMenuDelegate {
    public let menu = NSMenu(title: "樣式")
    /// 目前生效的樣式與「設定檔有誤」狀態。
    public var source: () -> (style: TickerStyle, hasConfigProblem: Bool) = { (.default, false) }
    /// 使用者操作（由 App 接到 `StyleActionRunner.run`）。
    public var onAction: (StyleMenuAction) -> Void = { _ in }

    public private(set) var entries: [StyleMenuModel.Entry] = []
    private var valueLabels: [StyleMenuModel.SliderKind: NSTextField] = [:]
    private var sliders: [NSSlider] = []

    public override init() {
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuild()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    /// 依目前樣式重建全部項目。
    public func rebuild() {
        let s = source()
        entries = StyleMenuModel.entries(for: s.style, hasConfigProblem: s.hasConfigProblem)
        menu.removeAllItems()
        valueLabels = [:]; sliders = []
        for e in entries { menu.addItem(makeItem(e)) }
    }

    private func makeItem(_ e: StyleMenuModel.Entry) -> NSMenuItem {
        switch e.kind {
        case .separator:
            return .separator()
        case .notice:
            let item = NSMenuItem(title: e.title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .submenu:
            let item = NSMenuItem(title: e.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: e.title)
            sub.autoenablesItems = false
            for c in e.children { sub.addItem(makeItem(c)) }
            item.submenu = sub
            return item
        case .toggle, .action:
            let item = NSMenuItem(title: e.title, action: #selector(itemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.action
            item.state = e.checked ? .on : .off
            item.isEnabled = e.enabled
            return item
        case .slider:
            let item = NSMenuItem()
            if let sl = e.slider { item.view = makeSliderView(title: e.title, slider: sl) }
            return item
        }
    }

    private func makeSliderView(title: String, slider sl: StyleMenuModel.Slider) -> NSView {
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 14, y: 6, width: 62, height: 18)
        let slider = NSSlider()
        slider.minValue = sl.range.lowerBound; slider.maxValue = sl.range.upperBound
        slider.doubleValue = sl.value
        slider.isContinuous = true
        slider.target = self; slider.action = #selector(sliderChanged(_:))
        slider.tag = sl.kind == .scrollSpeed ? 0 : 1
        slider.frame = NSRect(x: 78, y: 5, width: 120, height: 20)
        let value = NSTextField(labelWithString: String(Int(sl.value.rounded())))
        value.frame = NSRect(x: 202, y: 6, width: 40, height: 18)
        value.alignment = .right
        box.addSubview(label); box.addSubview(slider); box.addSubview(value)
        valueLabels[sl.kind] = value
        sliders.append(slider)
        return box
    }

    @objc private func itemClicked(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? StyleMenuAction else { return }
        onAction(a)
    }

    @objc private func sliderChanged(_ s: NSSlider) {
        let kind: StyleMenuModel.SliderKind = s.tag == 0 ? .scrollSpeed : .cornerRadius
        valueLabels[kind]?.stringValue = String(Int(s.doubleValue.rounded()))
        onAction(StyleMenuModel.sliderAction(kind, s.doubleValue))
    }

    // MARK: 測試用

    /// 模擬滑桿被拖到某值（走與真實拖動相同的 action）。
    public func simulateSlider(_ kind: StyleMenuModel.SliderKind, to value: Double) {
        guard let s = sliders.first(where: { $0.tag == (kind == .scrollSpeed ? 0 : 1) }) else { return }
        s.doubleValue = value
        sliderChanged(s)
    }
    public func sliderRange(_ kind: StyleMenuModel.SliderKind) -> ClosedRange<Double>? {
        sliders.first(where: { $0.tag == (kind == .scrollSpeed ? 0 : 1) }).map { $0.minValue...$0.maxValue }
    }
    public func valueText(_ kind: StyleMenuModel.SliderKind) -> String? { valueLabels[kind]?.stringValue }
}
