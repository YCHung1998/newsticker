import AppKit
import FastBullTickerCore

/// 被 spike 決定影響的平台設定值，集中於此（design.md 決定 1）。
///
/// 【暫定（待 spike 決定確認後調整）】2026-10-24：`spikes/RESULTS.md` 決定章節尚未經使用者確認，
/// 以下 level／collectionBehavior／渲染／計時器皆為設計文件預設值，**不代表已通過 S1–S5**。
/// 決定確認後只需替換 `ShellConfig.provisional` 的欄位，其他程式不動。
public struct ShellConfig: Sendable {
    public enum RendererKind: String, Sendable { case displayLink, basicAnimation }
    public enum FeedTimerKind: String, Sendable { case commonModeTimer, dispatchSourceTimer }

    // MARK: 受 spike 影響（暫定）
    /// 暫定 `.statusBar`（S1）。不得為 `.screenSaver`。
    public var level: NSWindow.Level
    /// 暫定 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`；`canJoinAllApplications` 先不加（S1）。
    public var collectionBehavior: NSWindow.CollectionBehavior
    /// 暫定方案 A：`NSView.displayLink`（S4）。
    public var renderer: RendererKind
    /// 暫定 `.common` mode 的 Timer（S3）。
    public var feedTimer: FeedTimerKind
    /// 長句切塊的紋理上限（px，設計文件記憶值，待 S4 實測）。
    public var textureLimitPx: Int
    /// displayLink 幀率上限（暫定 60；S4 若決定 30fps 只改此處）。
    public var maxFrameRate: Float

    // MARK: 不受 spike 影響的外觀與行為
    /// 初始尺寸 648×42：寬度由 `panelWidth(...)` 推導（齒輪槽 + 標籤 + 控制列 + 帶子可視寬 370），不寫死（settings-gear 決定 1）。
    public var panelSize: CGSize
    /// 左側標籤寬度（pt）【假設，來自使用者提供的參考截圖】。
    public var labelWidth: CGFloat
    /// 每則訊息左右留白（pt）。
    public var itemPadding: CGFloat
    /// 透明度範圍：下限 30%【假設，規格區間 20–30%】；預設 0.9【假設】。
    public var alphaRange: ClosedRange<Double>
    public var defaultAlpha: Double
    /// 位置存檔 debounce 秒數【假設，規格區間 0.3–1 秒】。
    public var persistDebounce: TimeInterval
    /// 補料計時器間隔（秒）。
    public var feedInterval: TimeInterval
    public var screenMargin: CGFloat
    /// 「不可見」須持續超過此秒數才凍結（遮蔽防抖，吸收切換 Space 轉場的狀態翻動）【假設】。
    public var occludedConfirmDelay: TimeInterval
    /// 控制列版面（`<`、`(n/N)`、`>`）：24 + 52 + 24 = 100pt【假設，待使用者看實物】。
    public var strip = ControlStripLayout()
    /// 連結欄位寬度（pt）【假設：26】。
    public var linkSlotWidth: Double = 26
    /// 迴紋針命中區每側外擴（pt）【假設：4】。
    public var hitSlop: Double = HitTesting.defaultHitSlop
    /// 齒輪槽寬度（pt）【假設：28】，位於面板最左側，不受 `showLabel` 影響（settings-gear）。
    public var gearSlotWidth: Double = 28

    /// 帶子可視寬度的設計值（使用者於 nav-layout-tweaks 確認的 370pt）。
    public static let designTapeViewport: Double = 370

    /// 面板寬度 = 齒輪槽 + 標籤 + 控制列 + 帶子可視寬度（純函式）。
    public static func panelWidth(gearSlotWidth: Double, labelWidth: Double, strip: ControlStripLayout, tapeViewport: Double) -> Double {
        gearSlotWidth + labelWidth + strip.controlStripWidth + tapeViewport
    }

    public static let provisional = ShellConfig(
        level: .statusBar,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
        renderer: .displayLink,
        feedTimer: .commonModeTimer,
        textureLimitPx: 16_384,
        maxFrameRate: 60,
        panelSize: CGSize(width: panelWidth(gearSlotWidth: 28, labelWidth: 150, strip: ControlStripLayout(), tapeViewport: designTapeViewport), height: 42),
        labelWidth: 150,
        itemPadding: 10,
        alphaRange: 0.3...1.0,
        defaultAlpha: 0.9,
        persistDebounce: 0.5,
        feedInterval: 0.1,
        screenMargin: 8,
        occludedConfirmDelay: 1.0
    )

    public var controlStripWidth: Double { strip.controlStripWidth }

    /// 控制列左側已被占用的寬度（單一偏移）＝ 齒輪槽 + （`showLabel` 時的標籤寬）。
    public func leftInset(showLabel: Bool) -> Double { gearSlotWidth + (showLabel ? Double(labelWidth) : 0) }

    /// 帶子可視寬度＝面板寬 − 齒輪槽 − （`showLabel` 時的標籤寬）− 控制列寬（預設 648 − 28 − 150 − 100 = 370；由 `strip` 推導，不重複寫死）。
    public func tapeViewport(showLabel: Bool) -> Double {
        strip.tapeViewportWidth(panelWidth: Double(panelSize.width), labelWidth: leftInset(showLabel: showLabel))
    }
    /// 標籤顯示時的可視寬度（預設樣式）。
    public var tapeViewportWidth: Double { tapeViewport(showLabel: true) }

    /// 命中測試用的幾何（與 `TickerView` 的圖層版面同源）；標籤隱藏時標籤寬為 0。
    public func makeHitGeometry(showLabel: Bool) -> HitGeometry {
        HitGeometry(panelSize: panelSize, labelWidth: showLabel ? Double(labelWidth) : 0, gearSlotWidth: gearSlotWidth, strip: strip, linkSlotWidth: linkSlotWidth, hitSlop: hitSlop)
    }
    public var hitGeometry: HitGeometry { makeHitGeometry(showLabel: true) }

    /// 依本設定與樣式建立 Core 的排程設定。時間以本機時區顯示。
    public func schedulerConfig(style: TickerStyle = .default, timeZone: TimeZone = .current) -> SchedulerConfig {
        let viewport = tapeViewport(showLabel: style.showLabel)
        var c = SchedulerConfig()
        c.speed = style.scrollSpeed
        c.viewportWidth = viewport
        c.maxItemWidth = max(viewport, 600)
        c.replayCount = style.replayCount
        c.showTime = style.showTime
        c.seekHoldSeconds = style.seekHoldSeconds
        c.linkSlotWidth = linkSlotWidth
        c.timeZone = timeZone
        return c
    }

    public func clampAlpha(_ a: Double) -> Double { min(max(a, alphaRange.lowerBound), alphaRange.upperBound) }
}

/// 從真實（或測試中未顯示的）面板讀回的生效值，供日誌與測試比對。
public struct PanelSettings: Equatable, Sendable {
    public var levelRaw: Int
    public var behavior: [String]
    public var styleMask: [String]
    public var hidesOnDeactivate: Bool
    public var canBecomeKey: Bool
    public var canBecomeMain: Bool
    public var isOpaque: Bool
    public var hasShadow: Bool
    public var alpha: Double
    public var frame: String

    public var summary: String {
        "level=\(levelRaw) behavior=[\(behavior.joined(separator: ","))] styleMask=[\(styleMask.joined(separator: ","))] "
        + "hidesOnDeactivate=\(hidesOnDeactivate) canBecomeKey=\(canBecomeKey) canBecomeMain=\(canBecomeMain) "
        + "isOpaque=\(isOpaque) hasShadow=\(hasShadow) alpha=\(String(format: "%.2f", alpha)) frame=\(frame)"
    }

    public static func behaviorNames(_ b: NSWindow.CollectionBehavior) -> [String] {
        let table: [(String, NSWindow.CollectionBehavior)] = [
            ("canJoinAllApplications", .canJoinAllApplications), ("canJoinAllSpaces", .canJoinAllSpaces),
            ("fullScreenAuxiliary", .fullScreenAuxiliary), ("fullScreenPrimary", .fullScreenPrimary),
            ("ignoresCycle", .ignoresCycle), ("moveToActiveSpace", .moveToActiveSpace), ("stationary", .stationary),
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

    @MainActor public init(panel: NSPanel) {
        levelRaw = panel.level.rawValue
        behavior = Self.behaviorNames(panel.collectionBehavior)
        styleMask = Self.styleNames(panel.styleMask)
        hidesOnDeactivate = panel.hidesOnDeactivate
        canBecomeKey = panel.canBecomeKey
        canBecomeMain = panel.canBecomeMain
        isOpaque = panel.isOpaque
        hasShadow = panel.hasShadow
        alpha = Double(panel.alphaValue)
        frame = NSStringFromRect(panel.frame)
    }
}
