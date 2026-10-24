import Testing
import Foundation
@testable import FastBullTickerCore

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

struct Transcript: Equatable {
    var placements: [String] = []
    var violations: [String] = []
    var rebases = 0, hides = 0, liveArrivals = 0, droppedTotal = 0, overflowEvents = 0
}

/// 以固定種子驅動「有 rebase 的 A」與「無 rebase 的對照 B」，逐步斷言不變量。
func runInvariantScenario(seed: UInt64, steps: Int) -> Transcript {
    var rng = SplitMix64(state: seed)
    let clock = FakeClock()
    var a = makeScheduler(clock), b = makeScheduler(clock)
    var tr = Transcript()
    var nextId = 11
    var arrived = Set<String>()
    var liveSeen: [String] = []
    var cumulativeDelta = 0.0
    var tapeXAtPlacement: [String: Double] = [:]        // key: 序號，值: 排入當下的 B 座標（B 從不 rebase）
    var seq = 0
    var lastB: PlacedItem?
    var hidden = false

    let first = Message.snapshot((1...10).reversed().map { it($0) })
    _ = a.receive(first); _ = b.receive(first)

    for _ in 0..<steps {
        switch rng.int(100) {
        case 0..<55:   // tick（可見時 dt 為 1/16 的倍數、≤ 1 秒）
            let dt = Double(rng.int(17)) / 16
            if !hidden { clock.t += dt }
            let pa = a.tick(), pb = b.tick()
            if pa.map({ "\($0.id)/\($0.style)" }) != pb.map({ "\($0.id)/\($0.style)" }) { tr.violations.append("A/B 排入不一致 @\(seq)") }
            for (x, y) in zip(pa, pb) {
                seq += 1
                tr.placements.append("\(y.id):\(y.style.rawValue):\(y.tapeX)")
                if a.visualX(of: x) != b.visualX(of: y) { tr.violations.append("視覺位置不一致 \(x.id)") }
                if let prev = lastB, y.tapeX - (prev.tapeX + prev.width) != 20 { tr.violations.append("間距 != gap @\(seq)") }
                if let prev = lastB, y.tapeX < prev.tapeX + prev.width { tr.violations.append("重疊 @\(seq)") }
                lastB = y
                tapeXAtPlacement["\(seq)"] = y.tapeX
                if y.style == .live {
                    liveSeen.append(y.id)
                    if !arrived.contains(y.id) { tr.violations.append("live 訊息未曾以 items 抵達 \(y.id)") }
                }
                if hidden { tr.violations.append("隱藏中仍補料") }
            }
        case 55..<70:  // 新的 items（1~3 則，id 遞增 → 舊到新）
            let n = 1 + rng.int(3)
            let ids = Array(nextId..<(nextId + n)); nextId += n
            let msg = Message.items(ids.map { it($0) })
            let ea = a.receive(msg), eb = b.receive(msg)
            if ea != eb { tr.violations.append("A/B 事件不一致") }
            for id in ids { arrived.insert(String(id)) }
            tr.liveArrivals += n
            for case .liveQueueOverflow(let d) in ea { tr.droppedTotal += d; tr.overflowEvents += 1 }
        case 70..<78:  // 隱藏：期間時鐘大跳
            if !hidden { a.hide(); b.hide(); hidden = true; tr.hides += 1 }
            clock.t += Double(rng.int(4000))
        case 78..<86:  // 恢復
            if hidden { a.show(); b.show(); hidden = false }
        case 86..<90:  // 只有 A 做 rebase
            let off = a.scrollOffset
            let d = a.rebase()
            cumulativeDelta += d
            tr.rebases += 1
            if d != off { tr.violations.append("delta != scrollOffset") }
            if a.scrollOffset != 0 { tr.violations.append("rebase 後 scrollOffset != 0") }
        default:       // 重複的 hide/show（冪等）
            if hidden { b.hide(); a.hide() } else { a.show(); b.show() }
        }
        if a.tapeTime != b.tapeTime { tr.violations.append("tapeTime 分歧") }
        // A 的每則 tapeX 必等於 B 同一則的 tapeX − 累計 delta（排入後不變直到 rebase）。
        if let ap = a.placed.last, let bp = b.placed.last, ap.id == bp.id, ap.tapeX != bp.tapeX - cumulativeDelta {
            tr.violations.append("tapeX 與 B−delta 不符 \(ap.id)")
        }
    }
    // 每則即時訊息只以 live 播一次，且順序遞增
    if Set(liveSeen).count != liveSeen.count { tr.violations.append("有即時訊息以 live 播超過一次") }
    if liveSeen != liveSeen.sorted(by: { Int($0)! < Int($1)! }) { tr.violations.append("live 不是由舊到新") }
    // B（從不 rebase）的整條帶子：相鄰間距恆為 gap、無重疊
    for (p, q) in zip(b.placed, b.placed.dropFirst()) where q.tapeX - (p.tapeX + p.width) != 20 { tr.violations.append("B 帶子間距異常") ; break }
    return tr
}

@Suite struct SchedulerInvariantTests {
    @Test func invariantsHoldOverLongRandomRun() {
        let tr = runInvariantScenario(seed: 20261024, steps: 30_000)
        #expect(tr.violations.isEmpty, "不變量違反（前 5 筆）：\(tr.violations.prefix(5))")
        // 場景確實涵蓋了各種事件（避免空轉通過）
        #expect(tr.placements.count > 1000)
        #expect(tr.rebases > 100 && tr.hides > 100 && tr.liveArrivals > 1000)
        #expect(tr.placements.contains { $0.contains(":live:") } && tr.placements.contains { $0.contains(":replay:") })
        #expect(tr.overflowEvents > 0, "場景應觸發至少一次佇列溢出")
    }

    @Test func differentSeedsAlsoHold() {
        for seed: UInt64 in [1, 2, 3, 42, 99999] {
            let tr = runInvariantScenario(seed: seed, steps: 8_000)
            #expect(tr.violations.isEmpty, "seed \(seed): \(tr.violations.prefix(3))")
        }
    }

    @Test func sameSeedIsDeterministic() {
        let t1 = runInvariantScenario(seed: 7, steps: 5_000)
        let t2 = runInvariantScenario(seed: 7, steps: 5_000)
        #expect(t1 == t2)
        let t3 = runInvariantScenario(seed: 8, steps: 5_000)
        #expect(t1 != t3)
    }
}
