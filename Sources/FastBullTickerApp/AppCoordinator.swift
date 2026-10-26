import Foundation
import FastBullTickerCore

/// 簡單日誌：寫檔（可選）與 stderr。thread-safe。
public final class AppLog: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL?
    private let toStderr: Bool
    private var lines: [String] = []
    public init(fileURL: URL?, toStderr: Bool = true) {
        self.fileURL = fileURL; self.toStderr = toStderr
        if let u = fileURL { try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true) }
    }
    public static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let p = environment["FASTBULL_TICKER_LOG"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FastBullTicker/app.log")
    }
    public var recorded: [String] { lock.withLock { lines } }
    public func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        lock.withLock {
            lines.append(message)
            if toStderr { FileHandle.standardError.write(Data(line.utf8)) }
            if let u = fileURL {
                if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
                else { try? Data(line.utf8).write(to: u) }
            }
        }
    }
}

/// 串接 `FeedClient` 事件到 `TickerDriver`（task 4.2）。不碰任何視窗，可做 headless 煙霧測試。
@MainActor
public final class AppCoordinator {
    public let driver: TickerDriver
    public let log: AppLog
    public private(set) var snapshots = 0
    public private(set) var itemBatches = 0
    public private(set) var statuses = 0
    public private(set) var badLines = 0
    public private(set) var helperStarts = 0
    public private(set) var fatal: FeedFatalError?
    public private(set) var modesSeen: [TickerMode] = []
    /// 收到的訊息總數與其中帶 `url` 者（診斷用，不記錄網址本身）。
    public private(set) var itemsReceived = 0
    public private(set) var itemsWithURL = 0
    private var lastReadingText = ""
    /// 切換來源後、下一次 helper `started` 之前：丟棄舊 helper 送來的訊息（change source-switcher）。
    public private(set) var isSwitchingSource = false
    public private(set) var droppedDuringSwitch = 0

    public init(driver: TickerDriver, log: AppLog) {
        self.driver = driver; self.log = log
        modesSeen = [driver.mode]
    }

    /// 開始切換來源：之後到下一個 `.started` 為止的訊息都屬於舊 helper，丟棄。
    public func beginSourceSwitch() { isSwitchingSource = true }

    /// 在主執行緒呼叫。
    public func handle(_ event: FeedEvent) {
        switch event {
        case .message(let m):
            if isSwitchingSource {
                droppedDuringSwitch += 1
                log.write("feed: dropped message from previous source")
                return
            }
            switch m {
            case .snapshot(let items):
                snapshots += 1; count(items)
                log.write("feed: snapshot items=\(items.count) withUrl=\(items.filter { $0.url != nil }.count)")
            case .items(let items):
                itemBatches += 1; count(items)
                log.write("feed: items count=\(items.count) withUrl=\(items.filter { $0.url != nil }.count)")
            case .status(let s): statuses += 1; log.write("feed: status \(s.state.rawValue) \(s.message)")
            }
            driver.receive(m)
            noteMode()
        case .badLine(let e): badLines += 1; log.write("feed: badLine \(e.reason.rawValue)")
        case .oversizeLine(let n): log.write("feed: oversizeLine \(n)")
        case .started(let g, let pid): isSwitchingSource = false; helperStarts += 1; log.write("feed: helper started gen=\(g) pid=\(pid)")
        case .exited(let g, let st, let d): log.write("feed: helper exited gen=\(g) status=\(st) restartIn=\(d)")
        case .stuck(let g): log.write("feed: helper stuck gen=\(g)")
        case .fatal(let e): fatal = e; log.write("feed: FATAL \(e)")
        case .reclaimedStaleHelper(let p): log.write("feed: reclaimed stale helper pid=\(p)")
        }
    }

    private func count(_ items: [Item]) {
        itemsReceived += items.count
        itemsWithURL += items.filter { $0.url != nil }.count
    }

    /// 每次 `step()` 後呼叫，記錄模式變化與閱讀位置 `(n/N)` 的變化。
    public func noteMode() {
        let reading = driver.controlState.text
        if reading != lastReadingText {
            lastReadingText = reading
            log.write("reading: \(reading.isEmpty ? "(none)" : reading)")
        }
        if modesSeen.last != driver.mode {
            modesSeen.append(driver.mode)
            log.write("mode -> \(driver.mode.rawValue)")
        }
    }

    public var statsLine: String {
        "stats: mode=\(driver.mode.rawValue) frozen=\(driver.isFrozen) snapshots=\(snapshots) itemBatches=\(itemBatches) "
        + "statuses=\(statuses) withUrl=\(itemsWithURL)/\(itemsReceived) badLines=\(badLines) placed=\(driver.itemsPlaced) liveQueue=\(driver.scheduler.liveQueueCount) rebases=\(driver.rebaseCount)"
    }

    /// 建立 FeedClient 的事件回呼：跳回主佇列後交給 `handle`（保持事件順序）。
    public nonisolated static func bridge(to coordinator: AppCoordinator) -> @Sendable (FeedEvent) -> Void {
        { event in
            DispatchQueue.main.async { MainActor.assumeIsolated { coordinator.handle(event) } }
        }
    }
}
