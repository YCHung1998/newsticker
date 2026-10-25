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
    /// `seek` 成功後捲動保持的秒數（0 = 不保持）【假設：1；原 8，使用者第二輪回饋改】。
    public var seekHoldSeconds: Double = 1
    /// 閱讀位置內縮：右緣必須大於此值才算「閱讀中」。須小於任何訊息的 `width`【假設：24pt】。
    public var readingInset: Double = 24
    /// 連結欄位寬度；只套用於有 `url` 的訊息。0 = 不保留欄位（實際值由 App 層設定）。
    public var linkSlotWidth: Double = 0
    /// rebase 後至少保留的已排入訊息數，使 `<` 仍可回溯【假設：64】。
    public var retainPlacedCount: Int = 64
    /// false 時顯示字串只有 `text`（不含時間字串）；預設 true，行為與加入此欄位之前完全相同。
    public var showTime: Bool = true
    public init() {}
}

/// 執行期可變更的欄位（`TickerScheduler.reconfigure`）。刻意只含七個欄位（settings-gear 增加 `seekHoldSeconds`）：
/// `gap`、`liveQueueLimit`、`historyLimit`、`rebaseThreshold` 等維持建構時的值，縮小風險面。
public struct SchedulerTunables: Sendable, Equatable {
    public var speed: Double
    public var viewportWidth: Double
    public var maxItemWidth: Double
    public var replayCount: Int
    public var showTime: Bool
    public var timeZone: TimeZone
    /// seek 成功後捲動保持的秒數（`>= 0`）。只影響之後的成功 seek；進行中的保持不變。
    public var seekHoldSeconds: Double

    public init(speed: Double, viewportWidth: Double, maxItemWidth: Double, replayCount: Int, showTime: Bool, timeZone: TimeZone,
                seekHoldSeconds: Double) {
        self.speed = speed; self.viewportWidth = viewportWidth; self.maxItemWidth = maxItemWidth
        self.replayCount = replayCount; self.showTime = showTime; self.timeZone = timeZone
        self.seekHoldSeconds = seekHoldSeconds
    }

    /// 取目前設定的七個欄位（呼叫端改幾個欄位再傳回 `reconfigure`）。
    public init(config: SchedulerConfig) {
        self.init(speed: config.speed, viewportWidth: config.viewportWidth, maxItemWidth: config.maxItemWidth,
                  replayCount: config.replayCount, showTime: config.showTime, timeZone: config.timeZone,
                  seekHoldSeconds: config.seekHoldSeconds)
    }
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
    /// 原樣取自 `Item.url`。
    public var url: String? = nil
    /// 排入序號：排程器內從 1 起單調遞增，唯一識別一次「排入」。
    public var seq: Int = 0
    /// 所屬清單（一輪重播，或一個即時批次）與在清單內的序號（從 1 起）。排入後不變。
    public var listID: Int = 0
    public var listIndex: Int = 0
    /// `width` 是否含最右側的連結欄位。
    public var hasLinkSlot: Bool = false

    public init(source: String, id: String, style: TickerStyle, timeString: String, text: String, truncated: Bool,
                tapeX: Double, width: Double, url: String? = nil, seq: Int = 0, listID: Int = 0, listIndex: Int = 0,
                hasLinkSlot: Bool = false) {
        self.source = source; self.id = id; self.style = style; self.timeString = timeString; self.text = text
        self.truncated = truncated; self.tapeX = tapeX; self.width = width; self.url = url; self.seq = seq
        self.listID = listID; self.listIndex = listIndex; self.hasLinkSlot = hasLinkSlot
    }
}

public struct ReadingPosition: Equatable, Sendable {
    public var item: PlacedItem
    /// `min(item.listIndex, total)`。
    public var index: Int
    public var total: Int

    public init(item: PlacedItem, index: Int, total: Int) { self.item = item; self.index = index; self.total = total }
}

public enum SeekDirection: Sendable { case previous, next }

public enum SeekOutcome: Equatable, Sendable {
    /// 成功對齊；`newlyPlaced` 非 nil 表示 `.next` 強制排入了一則。
    case moved(target: PlacedItem, newlyPlaced: PlacedItem?)
    case atListStart, previousNotRetained, noReadingItem, noMaterial, hidden
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
    /// 只有 `reconfigure` 會改變（且只改 `SchedulerTunables` 的六個欄位）。
    public private(set) var config: SchedulerConfig
    private let clock: () -> Double
    private var measurer: TextMeasurer

    public private(set) var mode: TickerMode = .replay
    public private(set) var tapeTime: Double = 0
    public private(set) var isHidden = false
    public private(set) var baseOffset: Double = 0
    /// 目前保留在帶子上的訊息（依排入順序）。只有 `rebase()` 會移除已捲出者。
    public private(set) var placed: [PlacedItem] = []
    /// 因即時佇列上限被丟棄的累計數量。
    public private(set) var totalDropped = 0
    /// 捲動保持剩餘秒數（seek 成功後設為 `seekHoldSeconds`，由注入時鐘消耗）。
    public private(set) var holdRemaining: Double = 0
    public private(set) var isPointerInside = false

    private var lastClock: Double
    private var hasBaseline = false
    private var history: [Item] = []        // 新到舊，已去重
    private var liveQueue: [Item] = []      // 舊到新
    private var replayCursor = 0
    private var tailEnd: Double?            // 最後一則的 tapeX + width（pruning 後仍保留）
    private var nextSeq = 1
    private var nextListID = 1
    private var replayListID: Int?          // 目前這一輪重播（游標回到起點、或離開 LIVE 後重設）
    private var openLiveListID: Int?        // 進行中的即時批次（供料器回到 REPLAY 時關閉）
    private var openLivePlaced = 0
    private var closedTotals: [Int: Int] = [:]   // 已固定總數的清單（重播一輪於開始時固定；即時批次於關閉時固定）

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

    /// 某清單目前的總數。進行中的即時批次＝已排入數＋佇列中尚未排入數（LIVE 追加使其增加）；其餘為固定值。
    /// 清單隨其訊息一起被 rebase 清理後回傳 nil。
    public func listTotal(of listID: Int) -> Int? {
        if listID == openLiveListID { return openLivePlaced + liveQueue.count }
        return closedTotals[listID]
    }

    /// 閱讀中那一則：依排入順序第一則「右緣 > readingInset 且左緣 < viewportWidth」者。純函數，不讀時鐘。
    public var readingItem: PlacedItem? {
        let off = scrollOffset
        // placed 依 tapeX 遞增且互不重疊 → 右緣單調，二分搜尋第一則右緣 > inset 者。
        var lo = 0, hi = placed.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if placed[mid].tapeX + placed[mid].width - off > config.readingInset { hi = mid } else { lo = mid + 1 }
        }
        guard lo < placed.count, placed[lo].tapeX - off < config.viewportWidth else { return nil }
        return placed[lo]
    }

    public var readingPosition: ReadingPosition? {
        guard let item = readingItem else { return nil }
        let total = max(listTotal(of: item.listID) ?? item.listIndex, 1)
        return ReadingPosition(item: item, index: min(item.listIndex, total), total: total)
    }

    // MARK: 執行期重新設定

    /// 套用 `SchedulerTunables`（不重建排程器）。前置條件同建構時：`speed ≥ 0`、`viewportWidth > 0`、`1 ≤ replayCount ≤ historyLimit`、`seekHoldSeconds ≥ 0`（呼叫端先夾制）。
    /// `seekHoldSeconds` 只更新設定、不動進行中的 `holdRemaining`（下一次成功 `seek` 才使用新值）。
    /// - 速度改變保持視覺連續：先以舊速度結算到現在，再調整 `baseOffset`，使 `scrollOffset` 在呼叫前後相同。
    /// - 已排入訊息的 `tapeX`／`width`／`seq`／文字完全不動；`viewportWidth`／`maxItemWidth`／`showTime`／`timeZone`／measurer
    ///   只影響之後排入者；`replayCount` 只影響之後的重播取料（游標取模，進行中的一輪不重排）。
    /// - 隱藏、保持、指標停留、即時佇列、歷史、模式不受影響；隱藏中呼叫合法且不解除凍結。
    public mutating func reconfigure(_ t: SchedulerTunables, measurer newMeasurer: @escaping TextMeasurer) {
        precondition(t.speed >= 0 && t.viewportWidth > 0 && t.seekHoldSeconds >= 0)
        precondition(t.replayCount > 0 && t.replayCount <= config.historyLimit)
        advance()                                             // 呼叫之前流逝的時間屬於舊速度（隱藏／停留時不推進）
        baseOffset += (config.speed - t.speed) * tapeTime     // scrollOffset = baseOffset + speed × tapeTime 前後相同
        config.speed = t.speed
        config.viewportWidth = t.viewportWidth
        config.maxItemWidth = t.maxItemWidth
        config.replayCount = t.replayCount
        config.showTime = t.showTime
        config.timeZone = t.timeZone
        config.seekHoldSeconds = t.seekHoldSeconds
        measurer = newMeasurer
    }

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
        // 隱藏與指標停留各自獨立，任一成立整段都不推進、也不消耗保持。
        guard !isHidden, !isPointerInside else { return }
        let consumed = min(holdRemaining, delta)
        holdRemaining -= consumed
        tapeTime += delta - consumed
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

    /// 指標進出面板。先以時鐘推進（切換前的時間要算進去），再切換狀態；重複設定同一值冪等。
    public mutating func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        advance()
        isPointerInside = inside
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
            guard let pulled = pullNext() else { break }
            out.append(place(pulled, startX: startX))
        }
        return out
    }

    /// 排入一則：`tick()` 與 `seek(.next)` 的強制排入共用，保證 `tapeX`、`seq`、清單資訊的算法只有一份。
    private mutating func place(_ pulled: Pulled, startX: Double) -> PlacedItem {
        let item = pulled.item
        let layout = layoutItem(item, timeZone: config.timeZone, maxWidth: config.maxItemWidth,
                                linkSlotWidth: config.linkSlotWidth, showTime: config.showTime, measurer: measurer)
        let p = PlacedItem(source: item.source, id: item.id, style: pulled.style, timeString: layout.timeString,
                           text: layout.text, truncated: layout.truncated, tapeX: startX, width: layout.width,
                           url: item.url, seq: nextSeq, listID: pulled.listID, listIndex: pulled.listIndex,
                           hasLinkSlot: layout.hasLinkSlot)
        nextSeq += 1
        placed.append(p)
        tailEnd = startX + layout.width
        return p
    }

    private struct Pulled { var item: Item; var style: TickerStyle; var listID: Int; var listIndex: Int }

    /// 模式只決定從哪裡取料。「佇列播完」＝供料器補料時即時佇列已空（集中在這一處）。
    private mutating func pullNext() -> Pulled? {
        if mode == .live && liveQueue.isEmpty {
            mode = .replay
            replayCursor = 0                  // 從最新一則開始
            replayListID = nil                // 新的一輪
            if let id = openLiveListID { closedTotals[id] = openLivePlaced; openLiveListID = nil }
        }
        switch mode {
        case .live:
            if openLiveListID == nil {
                openLiveListID = nextListID; nextListID += 1; openLivePlaced = 0
            }
            openLivePlaced += 1
            return Pulled(item: liveQueue.removeFirst(), style: .live, listID: openLiveListID!, listIndex: openLivePlaced)
        case .replay:
            let latest = latestItems
            guard !latest.isEmpty else { return nil }
            let idx = replayCursor % latest.count
            if idx == 0 || replayListID == nil {       // 游標回到起點 = 新的一輪；總數於開始時固定
                replayListID = nextListID; nextListID += 1
                closedTotals[replayListID!] = latest.count
            }
            replayCursor = idx + 1
            return Pulled(item: latest[idx], style: .replay, listID: replayListID!, listIndex: idx + 1)
        }
    }

    // MARK: seek

    /// 把閱讀中那一則的前一則／下一則對齊到視窗左緣（只改 `baseOffset`，不動任何 `tapeX`），並啟動捲動保持。
    /// `.next` 若下一則尚未排入，立即強制排入供料器下一次會取的那一則（`tapeX` = 尾端 + gap，與正常補料相同）。
    /// 不動作的結果不改變 `baseOffset` 與保持計時。
    public mutating func seek(_ direction: SeekDirection) -> SeekOutcome {
        guard !isHidden else { return .hidden }
        advance()
        guard let r = readingItem else { return .noReadingItem }
        let target: PlacedItem
        var newly: PlacedItem?
        switch direction {
        case .previous:
            if r.listIndex <= 1 { return .atListStart }
            guard let t = placed.last(where: { $0.seq == r.seq - 1 && $0.listID == r.listID }) else { return .previousNotRetained }
            target = t
        case .next:
            if let t = placed.last(where: { $0.seq == r.seq + 1 }) {
                target = t
            } else {
                guard let pulled = pullNext() else { return .noMaterial }
                let p = place(pulled, startX: (tailEnd ?? 0) + config.gap)
                target = p; newly = p
            }
        }
        baseOffset = target.tapeX - config.speed * tapeTime
        holdRemaining = config.seekHoldSeconds
        return .moved(target: target, newlyPlaced: newly)
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
            var keepFrom = placed.firstIndex { $0.tapeX + $0.width > 0 } ?? (placed.count - 1)
            keepFrom = min(keepFrom, max(0, placed.count - config.retainPlacedCount))   // 另外保留最近 N 則供 `<` 回溯
            if keepFrom > 0 { placed.removeFirst(keepFrom) }
        }
        let alive = Set(placed.map(\.listID))
        closedTotals = closedTotals.filter { alive.contains($0.key) || $0.key == replayListID }
        return delta
    }
}
