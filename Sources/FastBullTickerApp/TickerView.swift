import AppKit
import QuartzCore
import FastBullTickerCore

/// 面板（task 3.2）。styleMask 只在 init 一次設定；永不成為 key／main；不呼叫任何 App 啟用 API。
@MainActor
public final class PanelShell: NSPanel {
    public let config: ShellConfig

    public init(config: ShellConfig, frame: CGRect) {
        self.config = config
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        level = config.level
        collectionBehavior = config.collectionBehavior
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        alphaValue = CGFloat(config.defaultAlpha)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// 顯示面板：用 `orderFrontRegardless`，不啟用 App。
    public func present() { orderFrontRegardless() }
}

/// 帶子視圖（task 4.1，暫定方案 A：`NSView.displayLink` 逐幀設定 container layer 位置）。
/// 左側標籤＝紅色斜切【假設，來自使用者提供的參考截圖】；背景純色，不使用毛玻璃。
@MainActor
public final class TickerView: NSView, TickerRenderer {
    public let config: ShellConfig
    private let bitmap: ItemBitmapRenderer
    private let clipLayer = CALayer()
    private let scrollLayer = CALayer()
    private let labelLayer = CAShapeLayer()
    private let labelText = CATextLayer()
    private var track = TrackModel()
    private var layers: [Int: CALayer] = [:]
    private var offset: Double = 0
    private var link: CADisplayLink?
    private var paused = false
    /// 斜切造成的左緣突出量（pt）。
    private let slant: CGFloat = 12

    /// 逐幀回呼（由 App 設為 `driver.step`）。
    public var onFrame: (() -> Void)?
    /// 診斷用：displayLink 暫停／恢復時回報（不影響行為）。
    public var onLinkPauseChange: ((Bool) -> Void)?
    /// 右鍵選單（與選單列同一份）。
    public var contextMenu: NSMenu?
    public private(set) var frameCallbacks = 0

    public init(config: ShellConfig) {
        self.config = config
        self.bitmap = ItemBitmapRenderer(fontSize: config.fontSize, padding: config.itemPadding,
                                         heightPt: config.panelSize.height, textureLimitPx: config.textureLimitPx)
        super.init(frame: NSRect(origin: .zero, size: config.panelSize))
        wantsLayer = true
        layer?.backgroundColor = CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)   // 純色底
        buildLayers()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public var itemMeasurer: TextMeasurer { bitmap.measurer }
    public var layerCount: Int { layers.count }
    public var isLinkPaused: Bool { link?.isPaused ?? true }

    private func buildLayers() {
        let h = config.panelSize.height, w = config.panelSize.width, lw = config.labelWidth
        clipLayer.frame = CGRect(x: lw - slant, y: 0, width: w - lw + slant, height: h)
        clipLayer.masksToBounds = true
        scrollLayer.anchorPoint = .zero
        scrollLayer.frame = CGRect(x: slant, y: 0, width: 1, height: h)
        clipLayer.addSublayer(scrollLayer)
        layer?.addSublayer(clipLayer)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: lw - slant, y: 0))
        path.addLine(to: CGPoint(x: lw, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.closeSubpath()
        labelLayer.path = path
        labelLayer.frame = CGRect(x: 0, y: 0, width: lw, height: h)
        labelLayer.fillColor = CGColor(red: 0.85, green: 0.10, blue: 0.13, alpha: 1)      // 紅【假設】
        layer?.addSublayer(labelLayer)

        labelText.string = config.labelText
        labelText.font = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 15, nil)
        labelText.fontSize = 15
        labelText.foregroundColor = CGColor(gray: 1, alpha: 1)
        labelText.alignmentMode = .center
        labelText.contentsScale = 2
        labelText.frame = CGRect(x: 0, y: (h - 20) / 2, width: lw - slant, height: 20)
        layer?.addSublayer(labelText)
    }

    // MARK: TickerRenderer

    public func add(_ item: PlacedItem) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let seq = track.add(tapeX: item.tapeX, width: item.width)
        let container = CALayer()
        container.anchorPoint = .zero
        container.frame = CGRect(x: item.tapeX, y: 0, width: item.width, height: config.panelSize.height)
        var x = 0.0
        for (i, tile) in bitmap.render(item, scale: scale).enumerated() {
            let t = CALayer()
            t.contents = tile
            t.contentsScale = scale
            t.anchorPoint = .zero
            t.frame = CGRect(x: x, y: 0, width: Double(tile.width) / scale, height: Double(tile.height) / scale)
            container.addSublayer(t)
            x += Double(tile.width) / scale
            _ = i
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrollLayer.addSublayer(container)
        CATransaction.commit()
        layers[seq] = container
    }

    public func setScrollOffset(_ x: Double) {
        offset = x
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrollLayer.position = CGPoint(x: slant - x, y: 0)
        for seq in track.prune(offset: x) { layers.removeValue(forKey: seq)?.removeFromSuperlayer() }
        CATransaction.commit()
    }

    public func applyRebase(delta: Double) {
        track.rebase(delta: delta)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for e in track.entries { layers[e.seq]?.position.x = e.tapeX }
        CATransaction.commit()
    }

    public func setPaused(_ paused: Bool) {
        let changed = self.paused != paused
        self.paused = paused
        link?.isPaused = paused
        if changed { onLinkPauseChange?(paused) }
    }

    // MARK: displayLink

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(frameTick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: config.maxFrameRate, preferred: config.maxFrameRate)
        l.isPaused = paused
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func frameTick(_ l: CADisplayLink) {
        frameCallbacks += 1
        onFrame?()
    }

    public func stop() { link?.invalidate(); link = nil }

    // MARK: 滑鼠：點擊＝拖曳；右鍵＝同一份選單

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    public override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
