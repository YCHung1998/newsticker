import Foundation

public enum TickerStyle: String, Sendable { case live, replay }
public enum TickerMode: String, Sendable { case replay, live }

public struct SchedulerConfig: Sendable {
    public var speed: Double = 60
    public var gap: Double = 48
    public var viewportWidth: Double = 620
    public var maxItemWidth: Double = 600
    public var liveQueueLimit: Int = 30
    public var replayCount: Int = 10
    public var historyLimit: Int = 200
    public var timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    public var rebaseThreshold: Double = 500_000
    public init() {}
}

public struct PlacedItem: Equatable, Sendable {
    public var source: String
    public var id: String
    public var style: TickerStyle
    public var timeString: String
    public var text: String
    public var truncated: Bool
    public var tapeX: Double
    public var width: Double
}

public enum SchedulerEvent: Equatable, Sendable {
    case liveQueueOverflow(dropped: Int)
    case itemsBeforeSnapshotIgnored(count: Int)
    case duplicatesSkipped(count: Int)
}

/// 跑馬燈排程器：tape 座標、REPLAY／LIVE 狀態機、供料器、隱藏凍結、rebase。純值型別，無計時器、無渲染。
///
/// - `visualX = tapeX − scrollOffset(tapeTime)`，`scrollOffset = baseOffset + speed × tapeTime`。
/// - Core 不擁有計時器：呼叫端定期呼叫 `tick()`（pull 模式）。
public struct TickerScheduler {
    public let config: SchedulerConfig
    private let clock: () -> Double
    private let measurer: TextMeasurer

    public private(set) var mode: TickerMode = .replay
    public private(set) var tapeTime: Double = 0
    public private(set) var isHidden = false
    public private(set) var baseOffset: Double = 0
    /// 目前保留在帶子上的訊息（依排入順序）。只有 `rebase()` 會移除已捲出者。
    public private(set) var placed: [PlacedItem] = []
    /// 因即時佇列上限被丟棄的累計數量。
    public private(set) var totalDropped = 0

    private var lastClock: Double
    private var hasBaseline = false
    private var history: [Item] = []        // 新到舊，已去重
    private var liveQueue: [Item] = []      // 舊到新
    private var replayCursor = 0
    private var tailEnd: Double?            // 最後一則的 tapeX + width（pruning 後仍保留）

    /// 單次 tick 最多補幾則（防止 width + gap 為 0 的退化設定造成無窮迴圈）。
    private static let maxPlacementsPerTick = 10_000

    public init(config: SchedulerConfig, clock: @escaping () -> Double, measurer: @escaping TextMeasurer) {
        precondition(config.speed >= 0 && config.gap >= 0 && config.viewportWidth > 0)
        precondition(config.replayCount > 0 && config.liveQueueLimit > 0 && config.historyLimit >= config.replayCount)
        self.config = config
        self.clock = clock
        self.measurer = measurer
        self.lastClock = clock()
    }

    // MARK: 查詢（純函數）

    public var liveQueueCount: Int { liveQueue.count }
    /// 重播取用的最新 N 則（新到舊）。
    public var latestItems: [Item] { Array(history.prefix(config.replayCount)) }
    public var scrollOffset: Double { scrollOffset(atTapeTime: tapeTime) }
    public func scrollOffset(atTapeTime t: Double) -> Double { baseOffset + config.speed * t }
    public func visualX(of item: PlacedItem, atTapeTime t: Double? = nil) -> Double {
        item.tapeX - scrollOffset(atTapeTime: t ?? tapeTime)
    }
    public var shouldRebase: Bool { Self.shouldRebase(scrollOffset: scrollOffset, threshold: config.rebaseThreshold) }
    /// 建議 rebase 的閾值判斷（純函數）。
    public static func shouldRebase(scrollOffset: Double, threshold: Double) -> Bool { abs(scrollOffset) >= threshold }

    // MARK: 輸入

    public mutating func receive(_ message: Message) -> [SchedulerEvent] {
        switch message {
        case .status:
            return []
        case .snapshot(let items):
            // 啟動 snapshot 與中途 snapshot 同一路徑：只取代歷史（重設基準），不碰佇列、帶子、模式。
            history = []
            for item in items { upsertHistory(item) }
            hasBaseline = true
            return []
        case .items(let items):
            guard hasBaseline else { return [.itemsBeforeSnapshotIgnored(count: items.count)] }
            var events: [SchedulerEvent] = []
            var duplicates = 0
            for item in items {
                if history.contains(where: { $0.source == item.source && $0.id == item.id }) {
                    upsertHistory(item)      // 同鍵以後到者為準，但不再次進即時佇列
                    duplicates += 1
                } else {
                    upsertHistory(item)
                    liveQueue.append(item)
                    mode = .live
                }
            }
            if duplicates > 0 { events.append(.duplicatesSkipped(count: duplicates)) }
            if liveQueue.count > config.liveQueueLimit {
                let drop = liveQueue.count - config.liveQueueLimit
                liveQueue.removeFirst(drop)
                totalDropped += drop
                events.append(.liveQueueOverflow(dropped: drop))
            }
            return events
        }
    }

    /// 依 `published_at_ms` 新到舊插入；同毫秒時後到者在前。同鍵先移除舊的。
    private mutating func upsertHistory(_ item: Item) {
        history.removeAll { $0.source == item.source && $0.id == item.id }
        let idx = history.firstIndex { $0.publishedAtMs <= item.publishedAtMs } ?? history.endIndex
        history.insert(item, at: idx)
        if history.count > config.historyLimit { history.removeLast(history.count - config.historyLimit) }
    }

    // MARK: 時間與可見性

    /// 讀時鐘並推進 tape 時間（隱藏時不推進）。回撥視為 0 增量並以新值重新起算。
    private mutating func advance() {
        let now = clock()
        let delta = max(0, now - lastClock)
        lastClock = now
        if !isHidden { tapeTime += delta }
    }

    public mutating func hide() {
        guard !isHidden else { return }
        advance()                // 先把隱藏前的時間記進 tape 時間
        isHidden = true
    }

    public mutating func show() {
        guard isHidden else { return }
        lastClock = clock()      // 隱藏的實際時長不計入
        isHidden = false
    }

    // MARK: 供料器

    /// 讀時鐘、推進 tape 時間、在尾端有空位時補料。回傳本次新排入的訊息。
    public mutating func tick() -> [PlacedItem] {
        advance()
        guard !isHidden else { return [] }
        var out: [PlacedItem] = []
        while out.count < Self.maxPlacementsPerTick {
            let rightEdge = scrollOffset + config.viewportWidth
            let startX: Double
            if let tail = tailEnd, tail > scrollOffset {
                startX = tail + config.gap
                if startX > rightEdge { break }
            } else {
                startX = rightEdge          // 空帶子，或尾端已完全離開
            }
            guard let (item, style) = pullNext() else { break }
            let layout = layoutItem(item, timeZone: config.timeZone, maxWidth: config.maxItemWidth, measurer: measurer)
            let p = PlacedItem(source: item.source, id: item.id, style: style, timeString: layout.timeString,
                               text: layout.text, truncated: layout.truncated, tapeX: startX, width: layout.width)
            placed.append(p)
            tailEnd = startX + layout.width
            out.append(p)
        }
        return out
    }

    /// 模式只決定從哪裡取料。「佇列播完」＝供料器補料時即時佇列已空（集中在這一處）。
    private mutating func pullNext() -> (Item, TickerStyle)? {
        if mode == .live && liveQueue.isEmpty {
            mode = .replay
            replayCursor = 0                  // 從最新一則開始
        }
        switch mode {
        case .live:
            return (liveQueue.removeFirst(), .live)
        case .replay:
            let latest = latestItems
            guard !latest.isEmpty else { return nil }
            let item = latest[replayCursor % latest.count]
            replayCursor = (replayCursor % latest.count) + 1
            return (item, .replay)
        }
    }

    // MARK: rebase

    /// 對所有已排入訊息的 `tapeX` 與 `baseOffset` 施加同一位移（目前 `scrollOffset`），使視覺位置不變、
    /// 座標絕對值變小；移除已完全捲出左緣的訊息（保留尾端以維持間距）。回傳 `delta` 供渲染端同步座標。
    @discardableResult
    public mutating func rebase() -> Double {
        let delta = scrollOffset
        baseOffset -= delta
        for i in placed.indices { placed[i].tapeX -= delta }
        if let t = tailEnd { tailEnd = t - delta }
        // scrollOffset 此刻為 0：右緣 <= 0 者已完全離開；至少保留最後一則。
        if placed.count > 1 {
            let keepFrom = placed.firstIndex { $0.tapeX + $0.width > 0 } ?? (placed.count - 1)
            if keepFrom > 0 { placed.removeFirst(keepFrom) }
        }
        return delta
    }
}
