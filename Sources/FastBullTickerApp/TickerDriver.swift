import Foundation
import FastBullTickerCore

/// 渲染介面（task 4.1）：消費 Core `TickerScheduler` 的輸出，不重新實作排程。
/// 兩種實作（displayLink／CABasicAnimation）可共用同一組測試替身。
@MainActor
public protocol TickerRenderer: AnyObject {
    /// 加入一則已排定 `tapeX`／`width` 的訊息。**對同一 `seq` 冪等**（向後 seek 時會重送仍在帶子上的訊息）。
    func add(_ item: PlacedItem)
    /// 設定目前捲動位移（`visualX = tapeX − offset`）。
    func setScrollOffset(_ offset: Double)
    /// 控制列狀態（位置指示文字與兩個按鈕的啟用）；只在狀態改變時呼叫。
    func setControlStrip(_ state: ControlStripState)
    /// Core `rebase()` 的位移同步：所有訊息座標 −delta。
    func applyRebase(delta: Double)
    /// 暫停／恢復逐幀工作（隱藏、被遮蔽時暫停）。
    func setPaused(_ paused: Bool)
    /// 移除帶子上所有訊息圖層與座標模型（切換來源時）。預設不做事，讓既有的測試替身不必改。
    func removeAll()
}

public extension TickerRenderer {
    func removeAll() {}
}

/// 紋理切塊（純函式）：把總寬 `totalPx` 切成每塊不超過 `limit` 的寬度，總和等於原寬。
public enum Tiling {
    public static func tileWidths(totalPx: Int, limit: Int) -> [Int] {
        precondition(limit > 0)
        guard totalPx > 0 else { return [] }
        var out: [Int] = []
        var rest = totalPx
        while rest > 0 { let w = min(limit, rest); out.append(w); rest -= w }
        return out
    }
}

/// 帶子上訊息的座標模型（純邏輯，無 AppKit）：渲染器用它管理 layer 的生命週期與 rebase。
public struct TrackModel: Equatable {
    public struct Entry: Equatable { public var seq: Int; public var tapeX: Double; public var width: Double }
    public private(set) var entries: [Entry] = []
    public init() {}

    public func contains(seq: Int) -> Bool { entries.contains { $0.seq == seq } }

    /// 以 Core 的 `seq` 為鍵。已存在者略過（回傳 false），座標不被覆蓋。
    @discardableResult
    public mutating func add(seq: Int, tapeX: Double, width: Double) -> Bool {
        guard !contains(seq: seq) else { return false }
        entries.append(Entry(seq: seq, tapeX: tapeX, width: width))
        return true
    }

    /// 移除已完全捲出左緣（右緣 < offset − margin）者，回傳被移除的 seq。
    public mutating func prune(offset: Double, margin: Double = 100) -> [Int] {
        let gone = entries.filter { $0.tapeX + $0.width < offset - margin }.map(\.seq)
        if !gone.isEmpty { entries.removeAll { gone.contains($0.seq) } }
        return gone
    }

    public mutating func rebase(delta: Double) {
        for i in entries.indices { entries[i].tapeX -= delta }
    }

    /// 某訊息在給定捲動位移下的視覺 x。
    public func visualX(seq: Int, offset: Double) -> Double? {
        entries.first { $0.seq == seq }.map { $0.tapeX - offset }
    }
}

/// 把 Core `TickerScheduler` 接到 `TickerRenderer`：逐步補料、同步位移、處理 rebase、隱藏／遮蔽凍結。
/// 逐幀回呼（displayLink）與補料計時器（`.common` mode）都呼叫 `step()`；`step()` 可重入且冪等。
@MainActor
public final class TickerDriver {
    public private(set) var scheduler: TickerScheduler
    private let renderer: TickerRenderer
    public private(set) var userHidden = false
    public private(set) var occluded = false
    public private(set) var messagesReceived = 0
    public private(set) var itemsPlaced = 0
    public private(set) var rebaseCount = 0
    public private(set) var lastEvents: [SchedulerEvent] = []

    public private(set) var controlState = ControlStripState.from(position: nil)

    public init(scheduler: TickerScheduler, renderer: TickerRenderer) {
        self.scheduler = scheduler; self.renderer = renderer
    }

    /// 套用執行期可變設定（速度、可視寬度、訊息量、時間顯示、量測函式）。已排入的訊息不動。
    public func reconfigure(_ tunables: SchedulerTunables, measurer: @escaping TextMeasurer, boldMeasurer: BoldAwareMeasurer? = nil) {
        scheduler.reconfigure(tunables, measurer: measurer, boldMeasurer: boldMeasurer)
    }

    /// 切換來源：清掉排程器與畫面上舊來源的一切（時間軸與序號不歸零）。
    public func reset() {
        scheduler.reset()
        renderer.removeAll()
        lastEvents = []
        refreshControlStrip()
    }

    public var mode: TickerMode { scheduler.mode }
    public var isFrozen: Bool { userHidden || occluded }

    public func receive(_ message: Message) {
        messagesReceived += 1
        let ev = scheduler.receive(message)
        if !ev.isEmpty { lastEvents = ev }
    }

    public func step() {
        let placed = scheduler.tick()
        for p in placed { renderer.add(p) }
        itemsPlaced += placed.count
        if scheduler.shouldRebase {
            let delta = scheduler.rebase()
            renderer.applyRebase(delta: delta)
            rebaseCount += 1
        }
        renderer.setScrollOffset(scheduler.scrollOffset)
        refreshControlStrip()
    }

    // MARK: 導覽（task 7.1）

    /// `<` `>`：交給 Core `seek`。成功時先把與新視窗重疊的訊息逐一送給渲染器（冪等，已存在者略過；
    /// 向後 seek 時左側圖層可能已被 prune，要重建），再同步位移與控制列。
    @discardableResult
    public func seek(_ direction: SeekDirection) -> SeekOutcome {
        let outcome = scheduler.seek(direction)
        if case .moved(_, let newly) = outcome {
            if newly != nil { itemsPlaced += 1 }
            let off = scheduler.scrollOffset, right = off + scheduler.config.viewportWidth
            for p in scheduler.placed where p.tapeX + p.width > off && p.tapeX < right { renderer.add(p) }
            renderer.setScrollOffset(off)
            refreshControlStrip()
        }
        return outcome
    }

    /// 指標進出面板（追蹤區事件）。
    public func setPointerInside(_ inside: Bool) { scheduler.setPointerInside(inside) }

    /// 以 `NSEvent.mouseLocation` 與 `panel.frame` 核對指標狀態（保險：exit 事件遺失也不會永久凍結）。
    public func reconcilePointer(mouse: CGPoint, panelFrame: CGRect, panelVisible: Bool, clickThrough: Bool) {
        let inside = PointerHover.reconciled(tracked: scheduler.isPointerInside, mouse: mouse, panelFrame: panelFrame,
                                             panelVisible: panelVisible, clickThrough: clickThrough)
        scheduler.setPointerInside(inside)
    }

    /// 目前與可見帶子 `[0, viewportWidth)` 有交集的訊息（命中測試用；`visualLeft` 為帶子座標）。
    public func hitItems() -> [HitItem] {
        let off = scheduler.scrollOffset, vw = scheduler.config.viewportWidth
        return scheduler.placed.compactMap { p in
            let left = p.tapeX - off
            guard left + p.width > 0, left < vw else { return nil }
            return HitItem(seq: p.seq, visualLeft: left, width: p.width, hasLinkSlot: p.hasLinkSlot)
        }
    }

    public func placedItem(seq: Int) -> PlacedItem? { scheduler.placed.last { $0.seq == seq } }

    private func refreshControlStrip() {
        let s = ControlStripState.from(position: scheduler.readingPosition)
        if s != controlState { controlState = s; renderer.setControlStrip(s) }
    }

    public func setUserHidden(_ v: Bool) { userHidden = v; applyFreeze() }
    public func setOccluded(_ v: Bool) { occluded = v; applyFreeze() }

    private func applyFreeze() {
        if isFrozen {
            scheduler.hide(); renderer.setPaused(true)
        } else {
            scheduler.show(); renderer.setPaused(false)
        }
    }
}
