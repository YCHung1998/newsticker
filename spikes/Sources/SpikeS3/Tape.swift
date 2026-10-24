import Foundation
import SpikeKit

/// 假帶子的純模型：以單調時間推算捲動量，不依賴任何繪圖。
/// gap = 內容尾端 - 已捲動量 - 可視寬度；gap < 0 代表可視區已出現空白。
final class TapeModel {
    let speed: Double       // px/s
    let viewWidth: Double
    let interval: Double    // 補料週期（秒）
    let targetGap: Double   // 補料後希望維持的尾端空位
    var t0: Double
    var contentEnd: Double
    var nextIndex = 0

    init(speed: Double, viewWidth: Double, interval: Double, targetGap: Double, t0: Double) {
        self.speed = speed; self.viewWidth = viewWidth; self.interval = interval
        self.targetGap = targetGap; self.t0 = t0
        contentEnd = viewWidth + targetGap
    }
    func gap(at now: Double) -> Double { contentEnd - speed * (now - t0) - viewWidth }
    var messageWidth: Double { speed * interval }

    /// 補料直到 gap >= targetGap；回傳新增的 (index, x)。
    func refill(now: Double) -> [(Int, Double)] {
        var out: [(Int, Double)] = []
        while gap(at: now) < targetGap {
            out.append((nextIndex, contentEnd))
            contentEnd += messageWidth
            nextIndex += 1
        }
        return out
    }
}

enum TimerKind: String { case `default`, common, dispatch }

/// 三種補料計時器。每次觸發記錄 slot（最近的預定格）、預定／實際時間、補料前後的 gap。
final class Refiller {
    let kind: TimerKind
    let tape: TapeModel
    let log: EventLog
    var onAppend: (([(Int, Double)]) -> Void)?
    private var timer: Timer?
    private var source: DispatchSourceTimer?

    init(kind: TimerKind, tape: TapeModel, log: EventLog) { self.kind = kind; self.tape = tape; self.log = log }

    func start() {
        let iv = tape.interval
        tape.t0 = EventLog.uptime() // 預定時間以此刻為基準，避免把啟動延遲算進誤差
        switch kind {
        case .default, .common:
            let t = Timer(fire: Date(timeIntervalSinceNow: iv), interval: iv, repeats: true) { [weak self] _ in self?.fire() }
            RunLoop.main.add(t, forMode: kind == .default ? .default : .common)
            timer = t
        case .dispatch:
            let s = DispatchSource.makeTimerSource(queue: .main)
            s.schedule(deadline: .now() + iv, repeating: iv, leeway: .milliseconds(1))
            s.setEventHandler { [weak self] in self?.fire() }
            s.resume()
            source = s
        }
        log.write("refiller.start", [("timer", kind.rawValue), ("interval", String(iv)), ("t0", EventLog.f3(tape.t0))])
    }

    func stop() { timer?.invalidate(); source?.cancel() }

    private func fire() {
        let now = EventLog.uptime()
        let slot = max(1, Int(((now - tape.t0) / tape.interval).rounded()))
        let scheduled = tape.t0 + Double(slot) * tape.interval
        let before = tape.gap(at: now)
        let added = tape.refill(now: now)
        onAppend?(added)
        log.write("refill", [
            ("timer", kind.rawValue), ("slot", String(slot)), ("scheduled", EventLog.f3(scheduled)),
            ("actual", EventLog.f3(now)), ("gap_before", EventLog.f3(before)),
            ("gap_after", EventLog.f3(tape.gap(at: now))), ("appended", String(added.count)),
        ])
    }
}
