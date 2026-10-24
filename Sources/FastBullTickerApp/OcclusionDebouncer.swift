import Foundation

/// 遮蔽狀態防抖（純邏輯，只用 Foundation）。
///
/// 切換 Space 的轉場期間，系統可能讓視窗的 `occlusionState` 短暫翻動；若每次翻動都凍結／解凍，
/// 可能造成閃爍【假設，待使用者日誌佐證】。規則：
/// - 「變成不可見」須**持續超過 `confirmDelay`** 才決定凍結（`.confirmedOccluded`）；期間又變回可見則取消（`.cancelled`）。
/// - 「變回可見」若已凍結則**立即**解凍（`.thawed`）。
/// - 已在等待或已確認不可見時，重複的「不可見」通知不重設計時。
/// 使用者手動隱藏不經過這裡（`TickerDriver.setUserHidden` 維持立即）。
@MainActor
public final class OcclusionDebouncer {
    public enum Decision: Equatable, Sendable { case confirmedOccluded, cancelled, thawed }
    /// 排程注入點：延遲 `delay` 秒後執行 `work`，回傳取消函式。測試以假時鐘取代。
    public typealias Schedule = (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void

    public let confirmDelay: TimeInterval
    public private(set) var isOccluded = false
    public private(set) var isPending = false
    private let schedule: Schedule
    private let onDecision: (Decision) -> Void
    private var cancelPending: (() -> Void)?
    private var generation = 0

    public init(confirmDelay: TimeInterval, schedule: Schedule? = nil,
                onDecision: @escaping (Decision) -> Void) {
        self.confirmDelay = confirmDelay; self.schedule = schedule ?? Self.mainQueueSchedule; self.onDecision = onDecision
    }

    /// 回報一次原始遮蔽狀態變化。
    public func note(visible: Bool) {
        if visible {
            if isPending {
                cancelPending?(); cancelPending = nil; isPending = false; generation += 1
                onDecision(.cancelled)
            } else if isOccluded {
                isOccluded = false
                onDecision(.thawed)
            }
        } else if !isPending && !isOccluded {
            isPending = true
            generation += 1
            let g = generation
            cancelPending = schedule(confirmDelay) { [weak self] in
                guard let self, self.isPending, self.generation == g else { return }
                self.isPending = false; self.cancelPending = nil; self.isOccluded = true
                self.onDecision(.confirmedOccluded)
            }
        }
    }

    public static let mainQueueSchedule: Schedule = { delay, work in
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
