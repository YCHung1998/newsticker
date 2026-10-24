import Foundation

/// 可注入的時鐘：`FeedClient` 的所有時間判斷（退避、卡死、喚醒寬限、結束逾時）都經由它，
/// 測試用假時鐘即可不真的等待。
public protocol FeedClock: Sendable {
    /// 單調時間（秒）。
    func now() -> TimeInterval
    /// `delay` 秒後在 `queue` 上執行 `block`。
    func schedule(after delay: TimeInterval, on queue: DispatchQueue, _ block: @escaping @Sendable () -> Void) -> FeedTimer
}

public protocol FeedTimer: Sendable {
    func cancel()
}

/// 正式時鐘：DispatchWorkItem + 單調時間。
public struct SystemFeedClock: FeedClock {
    public init() {}
    public func now() -> TimeInterval { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
    public func schedule(after delay: TimeInterval, on queue: DispatchQueue, _ block: @escaping @Sendable () -> Void) -> FeedTimer {
        let item = DispatchWorkItem(block: block)
        queue.asyncAfter(deadline: .now() + max(delay, 0), execute: item)
        return WorkItemTimer(item: item)
    }
}

private final class WorkItemTimer: FeedTimer, @unchecked Sendable {
    let item: DispatchWorkItem
    init(item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}
