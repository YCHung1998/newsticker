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
    private let stripLayer = CALayer()
    private let previousText = CATextLayer()
    private let indicatorText = CATextLayer()
    private let nextText = CATextLayer()
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
    /// 滑鼠事件分派（命中測試、mouse-up 觸發）；動作由 App 層接上。
    public let router: NavigationInputRouter
    /// 指標進出面板（追蹤區事件）；由 App 層接到 `TickerDriver.setPointerInside`。
    public var onPointerInside: ((Bool) -> Void)?
    public private(set) var frameCallbacks = 0

    public init(config: ShellConfig) {
        self.config = config
        self.bitmap = ItemBitmapRenderer(fontSize: config.fontSize, padding: config.itemPadding,
                                         heightPt: config.panelSize.height, textureLimitPx: config.textureLimitPx,
                                         linkSlotWidth: CGFloat(config.linkSlotWidth))
        self.router = NavigationInputRouter(geometry: config.hitGeometry)
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
        // 帶子裁切在控制列之外：右緣 = 標籤寬 + 可視寬度 = 面板寬 − 控制列寬。
        clipLayer.frame = CGRect(x: lw - slant, y: 0, width: CGFloat(config.tapeViewportWidth) + slant, height: h)
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

        // 控制列（最上層、純色底，與訊息樣式無關）：`<`、`(n/N)`、`>`。
        let pw = Double(w), st = config.strip
        stripLayer.frame = CGRect(x: pw - st.controlStripWidth, y: 0, width: st.controlStripWidth, height: Double(h))
        stripLayer.backgroundColor = CGColor(gray: 0.15, alpha: 1)                              // 【假設】配色
        layer?.addSublayer(stripLayer)
        func place(_ t: CATextLayer, _ r: Range<Double>, _ text: String, size: CGFloat) {
            t.string = text
            t.font = CTFontCreateWithName("PingFangTC-Semibold" as CFString, size, nil)
            t.fontSize = size
            t.foregroundColor = CGColor(gray: 1, alpha: 1)
            t.alignmentMode = .center
            t.contentsScale = 2
            t.frame = CGRect(x: r.lowerBound, y: (Double(h) - 20) / 2, width: r.upperBound - r.lowerBound, height: 20)
            layer?.addSublayer(t)
        }
        place(previousText, st.previousButtonRange(panelWidth: pw), "<", size: 16)
        place(indicatorText, st.indicatorRange(panelWidth: pw), "", size: 13)
        place(nextText, st.nextButtonRange(panelWidth: pw), ">", size: 16)
        setControlStrip(ControlStripState.from(position: nil))
    }

    public func setControlStrip(_ state: ControlStripState) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        indicatorText.string = state.text
        previousText.opacity = state.previousEnabled ? 1 : 0.3
        nextText.opacity = state.nextEnabled ? 1 : 0.3
        CATransaction.commit()
    }

    /// 診斷與測試用：各圖層的版面與狀態。
    public struct LayoutSnapshot {
        public var clipFrame, stripFrame, previousFrame, indicatorFrame, nextFrame: CGRect
        public var previousOpacity, nextOpacity: Float
        public var indicatorText: String
    }
    public var layoutSnapshot: LayoutSnapshot {
        LayoutSnapshot(clipFrame: clipLayer.frame, stripFrame: stripLayer.frame, previousFrame: previousText.frame,
                       indicatorFrame: indicatorText.frame, nextFrame: nextText.frame,
                       previousOpacity: previousText.opacity, nextOpacity: nextText.opacity,
                       indicatorText: (indicatorText.string as? String) ?? "")
    }
    public var layerSeqs: [Int] { layers.keys.sorted() }
    /// scrollLayer 底下實際的訊息圖層數（測試用；與 `layers` 字典相等才表示沒有孤兒圖層）。
    public var containerCount: Int { scrollLayer.sublayers?.count ?? 0 }

    // MARK: TickerRenderer

    public func add(_ item: PlacedItem) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard track.add(seq: item.seq, tapeX: item.tapeX, width: item.width) else { return }    // 冪等
        let seq = item.seq
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

    // MARK: 滑鼠：按鈕與迴紋針＝動作（mouse-up 觸發）；其餘＝拖曳；右鍵＝同一份選單；進出＝暫停捲動

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func kind(_ e: NSEvent) -> PointerButton {
        switch e.type {
        case .leftMouseDown, .leftMouseUp: return .left
        case .rightMouseDown, .rightMouseUp: return .right
        default: return .other
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        router.mouseDown(at: p, button: kind(event), performDrag: { [weak self] in self?.window?.performDrag(with: event) })
    }

    public override func mouseUp(with event: NSEvent) {
        router.mouseUp(at: convert(event.locationInWindow, from: nil), button: kind(event))
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) { pointerChanged(true) }
    public override func mouseExited(with event: NSEvent) { pointerChanged(false) }
    public func pointerChanged(_ inside: Bool) { onPointerInside?(inside) }
}
