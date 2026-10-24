import AppKit

/// 選單列項目與面板右鍵共用的同一份 `NSMenu`（task 3.3）。
/// 點穿狀態只存在記憶體（不經 `PersistenceStore`），因此每次啟動為關。
@MainActor
public final class StatusMenuController: NSObject {
    public enum Kind: String, Sendable { case opacity, toggleVisibility, clickThrough, quit }
    public struct ItemInfo: Equatable, Sendable { public var kind: Kind; public var title: String; public var checked: Bool }

    public let config: ShellConfig
    public let menu = NSMenu(title: "FastBullTicker")
    public private(set) var alpha: Double
    public private(set) var isHidden = false
    public private(set) var clickThrough = false          // 不持久化：啟動恆為 false

    public var onAlphaChanged: ((Double) -> Void)?
    public var onVisibilityChanged: ((Bool) -> Void)?     // 參數＝是否隱藏
    public var onClickThroughChanged: ((Bool) -> Void)?
    public var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let slider = NSSlider()
    private let hideItem = NSMenuItem()
    private let clickItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private let opacityItem = NSMenuItem()

    public init(config: ShellConfig, initialAlpha: Double) {
        self.config = config
        self.alpha = config.clampAlpha(initialAlpha)
        super.init()
        buildMenu()
    }

    static func hideTitle(hidden: Bool) -> String { hidden ? "顯示帶子" : "隱藏帶子" }

    private func buildMenu() {
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        let label = NSTextField(labelWithString: "透明度")
        label.frame = NSRect(x: 14, y: 6, width: 50, height: 18)
        slider.minValue = config.alphaRange.lowerBound
        slider.maxValue = config.alphaRange.upperBound
        slider.doubleValue = alpha
        slider.isContinuous = true
        slider.target = self; slider.action = #selector(sliderChanged(_:))
        slider.frame = NSRect(x: 66, y: 5, width: 140, height: 20)
        box.addSubview(label); box.addSubview(slider)
        opacityItem.view = box
        menu.addItem(opacityItem)

        hideItem.title = Self.hideTitle(hidden: false)
        hideItem.target = self; hideItem.action = #selector(toggleHidden)
        menu.addItem(hideItem)

        clickItem.title = "點穿模式"
        clickItem.target = self; clickItem.action = #selector(toggleClickThrough)
        menu.addItem(clickItem)

        menu.addItem(.separator())
        quitItem.title = "結束"
        quitItem.target = self; quitItem.action = #selector(quit)
        menu.addItem(quitItem)
    }

    /// 項目清單（測試與日誌用）。
    public var items: [ItemInfo] {
        [ItemInfo(kind: .opacity, title: "透明度", checked: false),
         ItemInfo(kind: .toggleVisibility, title: hideItem.title, checked: false),
         ItemInfo(kind: .clickThrough, title: clickItem.title, checked: clickThrough),
         ItemInfo(kind: .quit, title: quitItem.title, checked: false)]
    }
    public var sliderRange: ClosedRange<Double> { slider.minValue...slider.maxValue }

    /// 在選單列建立圖示（需要 NSApplication；測試不呼叫）。
    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "newspaper", accessibilityDescription: "FastBullTicker") {
            item.button?.image = img
        } else {
            item.button?.title = "快訊"
        }
        item.menu = menu
        statusItem = item
    }

    // MARK: 動作（可由測試直接呼叫）

    public func setAlpha(_ a: Double) {
        alpha = config.clampAlpha(a)
        slider.doubleValue = alpha
        onAlphaChanged?(alpha)
    }
    public func setHidden(_ h: Bool) {
        isHidden = h
        hideItem.title = Self.hideTitle(hidden: h)
        onVisibilityChanged?(h)
    }
    public func setClickThrough(_ c: Bool) {
        clickThrough = c
        clickItem.state = c ? .on : .off
        onClickThroughChanged?(c)
    }

    @objc private func sliderChanged(_ s: NSSlider) { setAlpha(s.doubleValue) }
    @objc private func toggleHidden() { setHidden(!isHidden) }
    @objc private func toggleClickThrough() { setClickThrough(!clickThrough) }
    @objc private func quit() { onQuit?() }
}
