import Foundation

/// 指數退避純函式：1 → 2 → 4 … 上限 60 秒，加對稱 jitter。
/// 時鐘與亂數皆由呼叫端注入（`randomUnit` 為 [0,1) 的亂數），本型別不讀任何全域狀態。
/// 暫定值（2026-10-24 【假設】）：base 1 秒、上限 60 秒、jitter ±20%、運行超過 60 秒才重置。
public struct BackoffPolicy: Equatable, Sendable {
    public var base: TimeInterval
    public var maxDelay: TimeInterval
    /// 比例，0.2 = ±20%。
    public var jitter: Double
    /// helper 連續運行「超過」此秒數才重置退避。
    public var stableAfter: TimeInterval

    public init(base: TimeInterval = 1, maxDelay: TimeInterval = 60, jitter: Double = 0.2, stableAfter: TimeInterval = 60) {
        self.base = base; self.maxDelay = maxDelay; self.jitter = jitter; self.stableAfter = stableAfter
    }

    /// 第 `attempt`（0 起算）次重啟前的等待秒數；不含 jitter 的標稱值上限為 `maxDelay`。
    public func nominalDelay(attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt, 0), 32)   // 避免溢位；2^32 遠大於上限
        return min(base * pow(2, Double(exponent)), maxDelay)
    }

    /// 含 jitter：`randomUnit` 0 → 標稱 × (1 - jitter)，趨近 1 → 標稱 × (1 + jitter)。
    public func delay(attempt: Int, randomUnit: Double) -> TimeInterval {
        let r = min(max(randomUnit, 0), 1)
        return nominalDelay(attempt: attempt) * (1 + jitter * (2 * r - 1))
    }
}

/// 退避狀態：記錄連續失敗次數。
public struct BackoffState: Equatable, Sendable {
    public private(set) var attempt = 0
    public init() {}

    /// helper 結束時呼叫；若本次運行超過 `stableAfter` 則先重置。
    public mutating func processEnded(ranFor: TimeInterval, policy: BackoffPolicy) {
        if ranFor > policy.stableAfter { attempt = 0 }
    }

    /// 取得下一次重啟前的等待秒數並遞增失敗次數。
    public mutating func nextDelay(policy: BackoffPolicy, randomUnit: Double) -> TimeInterval {
        let d = policy.delay(attempt: attempt, randomUnit: randomUnit)
        attempt += 1
        return d
    }
}
