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
    /// 目前生效的樣式（`apply(style:)` 更新）。
    public private(set) var style: TickerStyle
    /// 目前（之後排入的訊息使用的）預渲染器。
    private var bitmap: ItemBitmapRenderer
    /// 字級改變前排入的訊息要沿用舊字級重繪／重建（寬度是以舊字級量測的）：`seq <= upToSeq` 者使用該渲染器。
    private var eras: [(upToSeq: Int, renderer: ItemBitmapRenderer)] = []
    private var maxSeqAdded = 0
    private var placedBySeq: [Int: PlacedItem] = [:]
    /// 累計就地重繪的訊息圖層數（診斷與測試用）。
    public private(set) var redrawCount = 0
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
    /// 斜切造成的左緣突出量（pt）。標籤隱藏時為 0。
    private let labelSlant: CGFloat = 12
    private var slant: CGFloat { style.showLabel ? labelSlant : 0 }
    private var labelW: CGFloat { style.showLabel ? config.labelWidth : 0 }

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

    public init(config: ShellConfig, style: TickerStyle = .default) {
        self.config = config
        self.style = style
        self.bitmap = ItemBitmapRenderer(style: style, config: config)
        self.router = NavigationInputRouter(geometry: config.makeHitGeometry(showLabel: style.showLabel))
        super.init(frame: NSRect(origin: .zero, size: config.panelSize))
        wantsLayer = true
        buildLayers()
        applyStaticStyle()
        layoutStyleLayers()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public var itemMeasurer: TextMeasurer { bitmap.measurer }
    public var layerCount: Int { layers.count }
    public var isLinkPaused: Bool { link?.isPaused ?? true }

    private func buildLayers() {
        let h = config.panelSize.height, w = config.panelSize.width
        clipLayer.masksToBounds = true
        scrollLayer.anchorPoint = .zero
        clipLayer.addSublayer(scrollLayer)
        layer?.addSublayer(clipLayer)

        layer?.addSublayer(labelLayer)      // 紅色斜切標籤【假設】；路徑、顏色、顯示與否見 `layoutStyleLayers`

        labelText.font = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 15, nil)
        labelText.fontSize = 15
        labelText.alignmentMode = .center
        labelText.truncationMode = .end
        labelText.contentsScale = 2
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

    /// 與樣式無關的顏色之外，會隨樣式改變的圖層屬性（顏色、圓角、標籤文字）。
    private func applyStaticStyle() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = style.tapeBackground.cgColor                        // 純色底（訊息間空隙）
        layer?.cornerRadius = CGFloat(min(max(style.cornerRadius, 0), Double(config.panelSize.height) / 2))
        layer?.masksToBounds = true                                                  // 圓角裁切標籤、訊息與控制列
        labelLayer.fillColor = style.labelBackground.cgColor
        labelText.foregroundColor = style.labelColor.cgColor
        labelText.string = style.labelText
        CATransaction.commit()
    }

    /// 隨 `showLabel` 改變的版面：標籤顯示／隱藏、帶子裁切範圍、捲動圖層原點。已排入訊息的 `tapeX` 不變。
    private func layoutStyleLayers() {
        let h = config.panelSize.height, lw = labelW
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let showLabel = style.showLabel
        labelLayer.isHidden = !showLabel
        labelText.isHidden = !showLabel
        if showLabel {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: lw - labelSlant, y: 0))
            path.addLine(to: CGPoint(x: lw, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.closeSubpath()
            labelLayer.path = path
            labelLayer.frame = CGRect(x: 0, y: 0, width: lw, height: h)
            labelText.frame = CGRect(x: 0, y: (h - 20) / 2, width: lw - labelSlant, height: 20)
        }
        // 帶子裁切在控制列之外：右緣 = 標籤寬 + 可視寬度 = 面板寬 − 控制列寬。
        clipLayer.frame = CGRect(x: lw - slant, y: 0, width: CGFloat(config.tapeViewport(showLabel: showLabel)) + slant, height: h)
        scrollLayer.frame = CGRect(x: slant, y: 0, width: 1, height: h)
        scrollLayer.position = CGPoint(x: slant - offset, y: 0)
        CATransaction.commit()
    }

    /// `apply(style:)` 的結果（日誌與測試用）。
    public struct StyleApplyReport: Equatable {
        public var redrawnItems = 0
        public var redrawMillis = 0.0
        public var fontChanged = false
        public var labelLayoutChanged = false
        public var colorsChanged = false
    }

    /// 套用新樣式（主執行緒）：標籤、空隙底色、圓角立即生效；顏色變更時已排入訊息的 bitmap 就地重繪（位置與寬度不變）；
    /// 字級變更只影響之後排入的訊息（舊訊息沿用舊字級）。不重建面板、不動 `tapeX`。
    @discardableResult
    public func apply(style new: TickerStyle) -> StyleApplyReport {
        var report = StyleApplyReport()
        let old = style
        guard new != old else { return report }
        style = new
        report.colorsChanged = ItemColors(style: new) != ItemColors(style: old)
        report.fontChanged = new.fontSize != old.fontSize
        report.labelLayoutChanged = new.showLabel != old.showLabel

        if report.fontChanged { eras.append((upToSeq: maxSeqAdded, renderer: bitmap)) }
        bitmap = ItemBitmapRenderer(style: new, config: config)
        let colors = ItemColors(style: new)
        for i in eras.indices { eras[i].renderer.colors = colors }                  // 顏色對全部訊息生效

        applyStaticStyle()
        if report.labelLayoutChanged {
            layoutStyleLayers()
            router.geometry = config.makeHitGeometry(showLabel: new.showLabel)
        }
        if report.colorsChanged {
            let t0 = DispatchTime.now().uptimeNanoseconds
            for (seq, container) in layers { if let item = placedBySeq[seq] { redraw(container, item: item) } }
            report.redrawnItems = layers.count
            report.redrawMillis = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            redrawCount += report.redrawnItems
        }
        return report
    }

    private func renderer(for seq: Int) -> ItemBitmapRenderer { eras.first { seq <= $0.upToSeq }?.renderer ?? bitmap }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// 把某則訊息的 bitmap 圖塊（重新）填入 `container`（沿用排入當時的字級）。
    private func redraw(_ container: CALayer, item: PlacedItem) {
        let scale = backingScale
        CATransaction.begin(); CATransaction.setDisableActions(true)
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        var x = 0.0
        for tile in renderer(for: item.seq).render(item, scale: scale) {
            let t = CALayer()
            t.contents = tile
            t.contentsScale = scale
            t.anchorPoint = .zero
            t.frame = CGRect(x: x, y: 0, width: Double(tile.width) / scale, height: Double(tile.height) / scale)
            container.addSublayer(t)
            x += Double(tile.width) / scale
        }
        CATransaction.commit()
    }

    /// 診斷與測試用：某則已排入訊息目前圖塊的第一塊 bitmap（驗證重繪與字級沿用）。
    public func firstTile(seq: Int) -> CGImage? { layers[seq]?.sublayers?.first?.contents as! CGImage? }

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
        // ticker-style-settings 4.1：樣式相關的圖層狀態
        public var labelString: String
        public var labelHidden: Bool
        public var labelFill: CGColor?
        public var labelTextColor: CGColor?
        public var tapeColor: CGColor?
        public var cornerRadius: CGFloat
        public var masksToBounds: Bool
        public var scrollOriginX: CGFloat
    }
    public var layoutSnapshot: LayoutSnapshot {
        LayoutSnapshot(clipFrame: clipLayer.frame, stripFrame: stripLayer.frame, previousFrame: previousText.frame,
                       indicatorFrame: indicatorText.frame, nextFrame: nextText.frame,
                       previousOpacity: previousText.opacity, nextOpacity: nextText.opacity,
                       indicatorText: (indicatorText.string as? String) ?? "",
                       labelString: (labelText.string as? String) ?? "", labelHidden: labelText.isHidden && labelLayer.isHidden,
                       labelFill: labelLayer.fillColor, labelTextColor: labelText.foregroundColor, tapeColor: layer?.backgroundColor,
                       cornerRadius: layer?.cornerRadius ?? -1, masksToBounds: layer?.masksToBounds ?? false,
                       scrollOriginX: scrollLayer.frame.origin.x)
    }
    /// 測試用：某則訊息圖層目前的 `tapeX`（圖層位置）。
    public func layerTapeX(seq: Int) -> Double? { layers[seq].map { Double($0.frame.origin.x) } }
    public var layerSeqs: [Int] { layers.keys.sorted() }
    /// scrollLayer 底下實際的訊息圖層數（測試用；與 `layers` 字典相等才表示沒有孤兒圖層）。
    public var containerCount: Int { scrollLayer.sublayers?.count ?? 0 }

    // MARK: TickerRenderer

    public func add(_ item: PlacedItem) {
        guard track.add(seq: item.seq, tapeX: item.tapeX, width: item.width) else { return }    // 冪等
        let seq = item.seq
        maxSeqAdded = max(maxSeqAdded, seq)
        placedBySeq[seq] = item
        let container = CALayer()
        container.anchorPoint = .zero
        container.frame = CGRect(x: item.tapeX, y: 0, width: item.width, height: config.panelSize.height)
        redraw(container, item: item)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrollLayer.addSublayer(container)
        CATransaction.commit()
        layers[seq] = container
    }

    public func setScrollOffset(_ x: Double) {
        offset = x
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrollLayer.position = CGPoint(x: slant - x, y: 0)
        for seq in track.prune(offset: x) { layers.removeValue(forKey: seq)?.removeFromSuperlayer(); placedBySeq.removeValue(forKey: seq) }
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
