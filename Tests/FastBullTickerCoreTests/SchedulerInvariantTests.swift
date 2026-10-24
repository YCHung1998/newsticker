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
    // ticker-navigation-link 5.1：seek／指標停留相關的涵蓋計數（避免空轉通過）
    var reconfigures = 0
    var seeks = 0, movedSeeks = 0, forcedPlacements = 0, pointerEnters = 0, holdTicks = 0, frozenTicks = 0
}

private func outcomeLabel(_ o: SeekOutcome) -> String {
    switch o {
    case .moved: return "moved"
    case .atListStart: return "atListStart"
    case .previousNotRetained: return "previousNotRetained"
    case .noReadingItem: return "noReadingItem"
    case .noMaterial: return "noMaterial"
    case .hidden: return "hidden"
    }
}

/// 以固定種子驅動「有 rebase 的 A」與「無 rebase 的對照 B」，逐步斷言不變量。
/// 兩者收到完全相同的 tick／items／hide／show／seek／指標進出；只有 A 會 rebase。
/// 斷言 design.md 決定 4 的八條不變量（見各處註解標號）。
func runInvariantScenario(seed: UInt64, steps: Int, withReconfigure: Bool = false) -> Transcript {
    var rng = SplitMix64(state: seed)
    let clock = FakeClock()
    var cfg = SchedulerConfig.test
    cfg.seekHoldSeconds = 2          // 預設 8 秒會讓隨機 seek 幾乎總在保持中；這裡縮短以免帶子長期靜止
    var a = makeScheduler(clock, config: cfg), b = makeScheduler(clock, config: cfg)
    var tr = Transcript()
    var nextId = 11
    var arrived = Set<String>()
    var liveSeen: [String] = []
    var cumulativeDelta = 0.0
    var seq = 0
    var tunableSeeds = SplitMix64(state: seed ^ 0xABCD)   // reconfigure 參數用獨立亂數流，不擾動主亂數流
    var lastB: PlacedItem?
    var hidden = false
    var pointer = false

    func notePlacement(_ x: PlacedItem, _ y: PlacedItem) {
        seq += 1
        tr.placements.append("\(y.id):\(y.style.rawValue):\(y.tapeX)")
        if a.visualX(of: x) != b.visualX(of: y) { tr.violations.append("視覺位置不一致 \(x.id)") }
        if x.seq != y.seq || x.listID != y.listID || x.listIndex != y.listIndex || x.url != y.url {
            tr.violations.append("A/B 清單識別不一致 \(x.id)")
        }
        if y.seq != seq { tr.violations.append("seq 非單調遞增 1 起：\(y.seq) != \(seq)") }      // 6/識別
        if let prev = lastB, y.tapeX - (prev.tapeX + prev.width) != 20 { tr.violations.append("間距 != gap @\(seq)") }   // 2（含強制排入）
        if let prev = lastB, y.tapeX < prev.tapeX + prev.width { tr.violations.append("重疊 @\(seq)") }
        lastB = y
        if y.style == .live {
            liveSeen.append(y.id)
            if !arrived.contains(y.id) { tr.violations.append("live 訊息未曾以 items 抵達 \(y.id)") }
        }
        if hidden { tr.violations.append("隱藏中仍補料／強制排入") }
    }

    let first = Message.snapshot((1...10).reversed().map { it($0) })
    _ = a.receive(first); _ = b.receive(first)

    for _ in 0..<steps {
        switch rng.int(withReconfigure ? 150 : 140) {
        case 0..<55:   // tick（可見時 dt 為 1/16 的倍數、≤ 1 秒）
            let dt = Double(rng.int(17)) / 16
            if !hidden { clock.t += dt }
            let t0 = a.tapeTime, h0 = a.holdRemaining, off0 = a.scrollOffset
            let frozen = hidden || pointer
            let pa = a.tick(), pb = b.tick()
            if pa.map({ "\($0.id)/\($0.style)" }) != pb.map({ "\($0.id)/\($0.style)" }) { tr.violations.append("A/B 排入不一致 @\(seq)") }
            for (x, y) in zip(pa, pb) { notePlacement(x, y) }
            // 4：隱藏與指標停留都不推進時間、不消耗保持；否則 tape 時間增量 + 保持消耗 = 時鐘增量
            let expected = frozen ? 0 : (hidden ? 0 : dt)
            let got = (a.tapeTime - t0) + (h0 - a.holdRemaining)
            if abs(got - expected) > 1e-9 { tr.violations.append("時間會計錯誤 got \(got) expected \(expected)") }
            if frozen { tr.frozenTicks += 1; if a.scrollOffset != off0 || a.holdRemaining != h0 { tr.violations.append("凍結中位置／保持改變") } }
            if !frozen && h0 > 0 { tr.holdTicks += 1 }
            // 3：兩次 seek／rebase 之間，位置是 tape 時間的純函數
            if abs((a.scrollOffset - off0) - a.config.speed * (a.tapeTime - t0)) > 1e-6 { tr.violations.append("scrollOffset 非 tape 時間純函數") }
        case 55..<70:  // 新的 items（1~3 則，id 遞增 → 舊到新）；三分之一機率實際送出，讓場景中仍有重播階段
            guard rng.int(3) == 0 else { break }
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
        case 78..<86:  // 恢復（4：隱藏 1 小時以上恢復後位置不跳動、保持不被消耗）
            if hidden {
                let off = a.scrollOffset, h = a.holdRemaining
                a.show(); b.show(); hidden = false
                if a.scrollOffset != off || a.holdRemaining != h { tr.violations.append("show 後位置／保持跳動") }
            }
        case 86..<90:  // 只有 A 做 rebase
            let off = a.scrollOffset
            let visualBefore = Dictionary(a.placed.suffix(200).map { ($0.seq, a.visualX(of: $0)) }, uniquingKeysWith: { first, _ in first })
            let countBefore = a.placed.count
            let d = a.rebase()
            cumulativeDelta += d
            tr.rebases += 1
            if d != off { tr.violations.append("delta != scrollOffset") }
            if a.scrollOffset != 0 { tr.violations.append("rebase 後 scrollOffset != 0") }
            // 5：視覺位置不變、保留最近 retainPlacedCount 則、清單總數仍可查
            for p in a.placed { if let v = visualBefore[p.seq], abs(a.visualX(of: p) - v) > 1e-6 { tr.violations.append("rebase 改變視覺位置 seq \(p.seq)") ; break } }
            if a.placed.count < min(countBefore, a.config.retainPlacedCount) { tr.violations.append("rebase 保留不足") }
            if a.placed.contains(where: { a.listTotal(of: $0.listID) == nil }) { tr.violations.append("rebase 後清單總數遺失") }
        case 90..<100: // 重複的 hide/show（冪等）
            if hidden { b.hide(); a.hide() } else { a.show(); b.show() }
        case 100..<103: // seek（<、>），連按 1~4 次
            let dir: SeekDirection = rng.int(2) == 0 ? .previous : .next
            for _ in 0...rng.int(4) {
                let tailA = a.placed.suffix(100).map { [$0.tapeX, $0.width] }
                let tailB = b.placed.suffix(100).map { [$0.tapeX, $0.width] }
                let h0 = a.holdRemaining, base0 = a.baseOffset
                let rp = a.readingPosition
                if rp != a.readingPosition { tr.violations.append("readingPosition 非純函數") }      // 7
                let oa = a.seek(dir), ob = b.seek(dir)
                tr.seeks += 1
                if outcomeLabel(oa) != outcomeLabel(ob) {
                    tr.violations.append("seek 結果分歧 A=\(oa) B=\(ob)")
                }
                if case .moved(let ta, let na) = oa, case .moved(let tb, let nb) = ob {
                    tr.movedSeeks += 1
                    if ta.seq != tb.seq || ta.id != tb.id || (na == nil) != (nb == nil) { tr.violations.append("seek 目標分歧") }
                    if let na, let nb { notePlacement(na, nb); tr.forcedPlacements += 1 }
                    if a.readingItem?.seq != ta.seq { tr.violations.append("seek 後閱讀中 != 目標") }      // 8
                    if abs(a.visualX(of: ta)) > 1e-6 || abs(b.visualX(of: tb)) > 1e-6 { tr.violations.append("seek 後目標未貼齊左緣") }
                    if a.holdRemaining != a.config.seekHoldSeconds { tr.violations.append("seek 後保持未重設") }
                } else if outcomeLabel(oa) == outcomeLabel(ob) {
                    if a.baseOffset != base0 || a.holdRemaining != h0 { tr.violations.append("不動作的 seek 改變了狀態 \(oa)") }
                }
                // 1：seek 不改任何既有訊息的 tapeX／width
                var newCount = 0
                if case .moved(_, let forced) = oa, forced != nil { newCount = 1 }
                if Array(a.placed.dropLast(newCount).suffix(tailA.count).map { [$0.tapeX, $0.width] }) != tailA { tr.violations.append("seek 改變了 A 的 tapeX／width") }
                if Array(b.placed.dropLast(newCount).suffix(tailB.count).map { [$0.tapeX, $0.width] }) != tailB { tr.violations.append("seek 改變了 B 的 tapeX／width") }
            }
        case 103..<106: // 指標進入
            if !pointer { tr.pointerEnters += 1 }
            a.setPointerInside(true); b.setPointerInside(true); pointer = true
        case 140..<150: // reconfigure（只在 withReconfigure 時出現）：A、B 套用同一組可變欄位，量測不變 → 寬度仍為 130
            let off = a.scrollOffset, tt = a.tapeTime, hold = a.holdRemaining
            let before = a.placed.suffix(100).map { [$0.tapeX, $0.width] }
            let visual = a.placed.suffix(100).map { a.visualX(of: $0) }
            var t = SchedulerTunables(config: a.config)
            t.speed = [0, 40, 70, 100][tunableSeeds.int(4)]   // ≤ 100：每步 ≤ 1 秒時尾端不會被甩出左緣（否則依既有規則改排到右緣，間距不再是 gap）
            t.viewportWidth = [120, 200, 320, 500][tunableSeeds.int(4)]
            t.replayCount = [1, 3, 5, 10][tunableSeeds.int(4)]
            a.reconfigure(t, measurer: flatMeasure); b.reconfigure(t, measurer: flatMeasure)
            tr.reconfigures += 1
            if a.scrollOffset != off { tr.violations.append("reconfigure 改變 scrollOffset") }        // 3：視覺連續
            if a.tapeTime != tt || a.holdRemaining != hold { tr.violations.append("reconfigure 改變 tape 時間／保持") }
            if a.placed.suffix(100).map({ [$0.tapeX, $0.width] }) != before { tr.violations.append("reconfigure 改變已排入訊息") }   // 1
            if a.placed.suffix(100).map({ a.visualX(of: $0) }) != visual { tr.violations.append("reconfigure 改變視覺位置") }
        default:        // 指標離開（機率較高，使指標在內的時間佔少數）
            a.setPointerInside(false); b.setPointerInside(false); pointer = false
        }
        if a.tapeTime != b.tapeTime { tr.violations.append("tapeTime 分歧") }
        if a.holdRemaining != b.holdRemaining { tr.violations.append("holdRemaining 分歧") }
        // 7：A 與 B 的閱讀位置（序號、名次、總數）一致
        let ra = a.readingPosition, rb = b.readingPosition
        if ra?.item.seq != rb?.item.seq || ra?.index != rb?.index || ra?.total != rb?.total {
            tr.violations.append("A/B 閱讀位置分歧 \(String(describing: ra?.item.seq)) vs \(String(describing: rb?.item.seq))")
        }
        // A 的每則 tapeX 必等於 B 同一則的 tapeX − 累計 delta（排入後不變直到 rebase）。
        if let ap = a.placed.last, let bp = b.placed.last, ap.id == bp.id, ap.tapeX != bp.tapeX - cumulativeDelta {
            tr.violations.append("tapeX 與 B−delta 不符 \(ap.id)")
        }
    }
    // 6：每則即時訊息只以 live 播一次（含 `>` 強制排入的），且順序遞增
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
        // seek／指標停留確實被涵蓋（避免空轉通過）
        #expect(tr.seeks > 1000 && tr.movedSeeks > 300 && tr.forcedPlacements > 50)
        #expect(tr.pointerEnters > 100 && tr.frozenTicks > 1000 && tr.holdTicks > 100)
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

    @Test func invariantsHoldWithRuntimeReconfigure() {
        let tr = runInvariantScenario(seed: 20261025, steps: 30_000, withReconfigure: true)
        #expect(tr.violations.isEmpty, "不變量違反（前 5 筆）：\(tr.violations.prefix(5))")
        #expect(tr.reconfigures > 1000 && tr.placements.count > 300)   // speed 0 的時段不補料，門檻低於無 reconfigure 版
        #expect(tr.movedSeeks > 300 && tr.rebases > 100 && tr.hides > 100 && tr.frozenTicks > 1000 && tr.holdTicks > 100)
    }

    @Test func reconfigureSeedsAlsoHold() {
        for seed: UInt64 in [1, 2, 3, 42, 99999] {
            let tr = runInvariantScenario(seed: seed, steps: 8_000, withReconfigure: true)
            #expect(tr.violations.isEmpty, "seed \(seed): \(tr.violations.prefix(3))")
        }
    }
}
