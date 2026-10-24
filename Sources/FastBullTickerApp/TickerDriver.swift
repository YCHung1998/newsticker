import Foundation
import FastBullTickerCore

/// 渲染介面（task 4.1）：消費 Core `TickerScheduler` 的輸出，不重新實作排程。
/// 兩種實作（displayLink／CABasicAnimation）可共用同一組測試替身。
@MainActor
public protocol TickerRenderer: AnyObject {
    /// 加入一則已排定 `tapeX`／`width` 的訊息。
    func add(_ item: PlacedItem)
    /// 設定目前捲動位移（`visualX = tapeX − offset`）。
    func setScrollOffset(_ offset: Double)
    /// Core `rebase()` 的位移同步：所有訊息座標 −delta。
    func applyRebase(delta: Double)
    /// 暫停／恢復逐幀工作（隱藏、被遮蔽時暫停）。
    func setPaused(_ paused: Bool)
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
    private var nextSeq = 0
    public init() {}

    @discardableResult
    public mutating func add(tapeX: Double, width: Double) -> Int {
        nextSeq += 1
        entries.append(Entry(seq: nextSeq, tapeX: tapeX, width: width))
        return nextSeq
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

    public init(scheduler: TickerScheduler, renderer: TickerRenderer) {
        self.scheduler = scheduler; self.renderer = renderer
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
