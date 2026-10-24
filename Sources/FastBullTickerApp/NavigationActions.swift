import Foundation
import FastBullTickerCore

/// 導覽與連結動作（task 8.1）：把箭頭接到 `TickerDriver.seek`、迴紋針接到 `LinkOpening`＋opener。
/// 不碰任何視窗，可做 headless 煙霧測試；只記錄結果（不記完整網址）。
@MainActor
public final class NavigationActions {
    private let driver: TickerDriver
    private let opener: URLOpener
    private let log: AppLog
    public private(set) var seekOutcomes: [SeekOutcome] = []
    public private(set) var linkResults: [LinkOpenResult] = []

    public init(driver: TickerDriver, opener: URLOpener, log: AppLog) {
        self.driver = driver; self.opener = opener; self.log = log
    }

    public func previous() { seek(.previous) }
    public func next() { seek(.next) }

    private func seek(_ d: SeekDirection) {
        let outcome = driver.seek(d)
        seekOutcomes.append(outcome)
        log.write("nav: seek \(d == .previous ? "previous" : "next") -> \(Self.describe(outcome)) reading=\(driver.controlState.text)")
    }

    /// 開啟 `seq` 那一則的連結：先過 `LinkPolicy`，通過才呼叫 opener，恰一次、失敗不重試。
    @discardableResult
    public func openLink(seq: Int) -> LinkOpenResult {
        let item = driver.placedItem(seq: seq)
        let result = LinkOpening.open(item?.url, using: opener)
        linkResults.append(result)
        log.write("nav: link seq=\(seq) id=\(item?.id ?? "?") -> \(result)")
        return result
    }

    public func bind(to router: NavigationInputRouter) {
        router.onPrevious = { [weak self] in self?.previous() }
        router.onNext = { [weak self] in self?.next() }
        router.onLink = { [weak self] seq in self?.openLink(seq: seq) }
    }

    static func describe(_ o: SeekOutcome) -> String {
        switch o {
        case .moved(let t, let n): return "moved(seq=\(t.seq) index=\(t.listIndex)\(n != nil ? " forcePlaced" : ""))"
        case .atListStart: return "atListStart"
        case .previousNotRetained: return "previousNotRetained"
        case .noReadingItem: return "noReadingItem"
        case .noMaterial: return "noMaterial"
        case .hidden: return "hidden"
        }
    }
}
