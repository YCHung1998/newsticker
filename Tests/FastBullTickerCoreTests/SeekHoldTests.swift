import Testing
import Foundation
@testable import FastBullTickerCore

/// seek、捲動保持、指標停留凍結（tasks 5.1）。
/// t=5 時：placed = 10@200, 9@350, 8@500, 7@650；scrollOffset 500 → 閱讀中為 id8（3/10）。
@Suite struct SeekHoldTests {
    private func make(_ tweak: (inout SchedulerConfig) -> Void = { _ in }) -> (FakeClock, TickerScheduler) {
        var cfg = SchedulerConfig.test
        cfg.seekHoldSeconds = 8          // 機制測試明確指定 8 秒（預設值於 nav-layout-tweaks 改為 1 秒；預設值另由下方 DefaultHold 測試覆蓋）
        tweak(&cfg)
        let clock = FakeClock()
        var s = makeScheduler(clock, config: cfg)
        _ = s.receive(snap(Array(1...10)))
        for t in 0...5 { clock.t = Double(t); _ = s.tick() }       // 逐秒 tick：10@200, 9@350, 8@500, 7@650
        return (clock, s)
    }
    private func leftEdge(_ s: TickerScheduler, _ p: PlacedItem) -> Double { s.visualX(of: p) }

    // MARK: seek 基本

    @Test func previousAlignsTargetToLeftEdgeAndStartsHold() {
        var (_, s) = make()
        #expect(s.readingItem?.id == "8")
        let outcome = s.seek(.previous)
        guard case .moved(let target, let newly) = outcome else { Issue.record("expected moved, got \(outcome)"); return }
        #expect(target.id == "9" && newly == nil)
        #expect(abs(leftEdge(s, target)) < 1e-9)
        #expect(s.readingPosition?.item.id == "9" && s.readingPosition?.index == 2 && s.readingPosition?.total == 10)
        #expect(s.holdRemaining == 8)
    }

    @Test func nextUsesAlreadyPlacedItem() {
        var (_, s) = make()
        guard case .moved(let target, let newly) = s.seek(.next) else { Issue.record("expected moved"); return }
        #expect(target.id == "7" && newly == nil)
        #expect(s.readingPosition?.index == 4)
        #expect(abs(leftEdge(s, target)) < 1e-9)
    }

    @Test func nextForcePlacesWithNormalGapWhenNotYetPlaced() {
        var (_, s) = make()
        _ = s.seek(.next)                              // → 7（目前帶子最後一則）
        let tail = s.placed.last!
        guard case .moved(let target, let newly) = s.seek(.next) else { Issue.record("expected moved"); return }
        #expect(newly == target && target.id == "6" && target.style == .replay)
        #expect(target.tapeX == tail.tapeX + tail.width + s.config.gap)
        #expect(target.seq == tail.seq + 1 && target.listID == tail.listID && target.listIndex == 5)
        #expect(abs(leftEdge(s, target)) < 1e-9)
        #expect(s.readingPosition?.index == 5)
    }

    @Test func lastOfRoundNextJumpsToNextRoundStart() {
        var (_, s) = make()
        for _ in 0..<7 { _ = s.seek(.next) }           // 8 → 7 ... → 1（第 10 則）
        #expect(s.readingPosition?.index == 10 && s.readingPosition?.item.id == "1")
        let last = s.placed.last!
        #expect(last.id == "1")
        guard case .moved(let target, let newly) = s.seek(.next) else { Issue.record("expected moved"); return }
        #expect(newly == target && target.id == "10" && target.listIndex == 1 && target.listID != last.listID)
        #expect(target.tapeX == last.tapeX + last.width + s.config.gap)
        #expect(s.readingPosition?.index == 1 && s.readingPosition?.total == 10)
    }

    @Test func nextTakesLiveQueueFirst() {
        var (_, s) = make()
        _ = s.seek(.next)                              // R = 7（最後一則）
        _ = s.receive(live([21]))
        guard case .moved(let target, let newly) = s.seek(.next) else { Issue.record("expected moved"); return }
        #expect(newly == target && target.id == "21" && target.style == .live)
        #expect(s.readingPosition?.index == 1 && s.readingPosition?.total == 1)
        #expect(s.liveQueueCount == 0, "強制排入的即時訊息算播過，不會再被取出")
    }

    @Test func forcedLiveItemIsNotPlayedAgain() {
        var (clock, s) = make()
        _ = s.seek(.next)
        _ = s.receive(live([21]))
        _ = s.seek(.next)
        var out: [PlacedItem] = []
        for _ in 0..<400 { clock.t += 0.25; out += s.tick() }
        #expect(!out.contains { $0.style == .live }, "21 只播一次")
    }

    @Test func previousAtListStartDoesNothing() {
        var (clock, s) = make()
        _ = s.seek(.previous); _ = s.seek(.previous)   // 8 → 9 → 10（第 1 則）
        #expect(s.readingPosition?.index == 1)
        clock.t += 3; _ = s.tick()                     // 消耗部分保持
        let hold = s.holdRemaining, base = s.baseOffset, placed = s.placed
        #expect(s.seek(.previous) == .atListStart)
        #expect(s.holdRemaining == hold && s.baseOffset == base && s.placed == placed)
        #expect(hold == 5)
    }

    @Test func emptyTapeAndHiddenAndNoMaterial() {
        let clock = FakeClock()
        var empty = makeScheduler(clock)
        #expect(empty.seek(.next) == .noReadingItem && empty.seek(.previous) == .noReadingItem)

        var (clock2, s) = make()
        let before = (s.baseOffset, s.holdRemaining, s.placed)
        s.hide(); clock2.t += 10
        #expect(s.seek(.next) == .hidden && s.seek(.previous) == .hidden)
        #expect(s.baseOffset == before.0 && s.holdRemaining == before.1 && s.placed == before.2)
        s.show()

        _ = s.seek(.next)                              // R = 最後一則
        _ = s.receive(.snapshot([]))                   // 歷史清空，且沒有即時訊息
        let base = s.baseOffset, hold = s.holdRemaining
        #expect(s.seek(.next) == .noMaterial)
        #expect(s.baseOffset == base && s.holdRemaining == hold)
    }

    @Test func seekNeverChangesAnyTapeXOrWidth() {
        var (_, s) = make()
        let before = s.placed.map { [$0.tapeX, $0.width] }
        _ = s.seek(.previous); _ = s.seek(.next); _ = s.seek(.next); _ = s.seek(.previous)
        let after = s.placed.prefix(before.count).map { [$0.tapeX, $0.width] }
        #expect(Array(after) == before)
        for (p, q) in zip(s.placed, s.placed.dropFirst()) { #expect(q.tapeX - (p.tapeX + p.width) == s.config.gap) }
    }

    @Test func positionIsPureFunctionOfTapeTimeBetweenSeeks() {
        var (clock, s) = make { $0.seekHoldSeconds = 0 }
        _ = s.seek(.previous)
        let base = s.baseOffset
        clock.t += 2; _ = s.tick()
        #expect(s.scrollOffset == base + s.config.speed * s.tapeTime)
        #expect(s.scrollOffset(atTapeTime: s.tapeTime) == s.scrollOffset)
        #expect(s.scrollOffset(atTapeTime: s.tapeTime + 1) == s.scrollOffset + 100)
    }

    @Test func forcedPlacementDoesNotCreateInterferenceWhenSeekIsBackward() {
        var (_, s) = make()
        let n = s.placed.count
        _ = s.seek(.previous)
        #expect(s.placed.count == n)
    }

    // MARK: 保持

    @Test func holdFreezesThenResumesWithoutJump() {
        var (clock, s) = make()
        _ = s.seek(.previous)
        let off = s.scrollOffset
        clock.t += 5; _ = s.tick()
        #expect(s.scrollOffset == off && s.holdRemaining == 3)
        clock.t += 3; _ = s.tick()
        #expect(s.scrollOffset == off && s.holdRemaining == 0)
        clock.t += 2; _ = s.tick()
        #expect(s.scrollOffset == off + 2 * 100, "第 8 秒後從對齊位置接著走")
    }

    @Test func partialConsumptionInOneStep() {
        var (clock, s) = make()
        _ = s.seek(.previous)
        let off = s.scrollOffset
        clock.t += 10; _ = s.tick()                    // 8 秒保持 + 2 秒移動
        #expect(s.scrollOffset == off + 200 && s.holdRemaining == 0)
    }

    @Test func secondSeekResetsHoldNotAccumulates() {
        var (clock, s) = make()
        _ = s.seek(.previous)
        clock.t += 6; _ = s.tick()
        #expect(s.holdRemaining == 2)
        _ = s.seek(.next)
        #expect(s.holdRemaining == 8)
    }

    @Test func zeroHoldSecondsMeansNoHold() {
        var (clock, s) = make { $0.seekHoldSeconds = 0 }
        _ = s.seek(.previous)
        let off = s.scrollOffset
        clock.t += 1; _ = s.tick()
        #expect(s.holdRemaining == 0 && s.scrollOffset == off + 100)
    }

    @Test func tickStillFillsDuringHold() {
        var (_, s) = make()
        _ = s.seek(.next); _ = s.seek(.next)           // 強制排入 6@800，對齊 scrollOffset 800
        let n = s.placed.count
        let out = s.tick()                             // 同一時刻：右緣 1000，尾端 930 + 20 ≤ 1000
        #expect(!out.isEmpty && s.placed.count > n && s.holdRemaining == 8)
        #expect(out[0].tapeX == s.placed[n - 1].tapeX + s.placed[n - 1].width + 20)
    }

    // MARK: 指標停留、隱藏

    @Test func pointerInsideFreezesAndDoesNotConsumeHold() {
        var (clock, s) = make()
        _ = s.seek(.previous)
        let off = s.scrollOffset
        s.setPointerInside(true)
        clock.t += 30; _ = s.tick()
        #expect(s.scrollOffset == off && s.holdRemaining == 8 && s.isPointerInside)
        s.setPointerInside(false)
        #expect(s.holdRemaining == 8 && s.scrollOffset == off)
        clock.t += 8; _ = s.tick()
        #expect(s.scrollOffset == off && s.holdRemaining == 0)
        clock.t += 1; _ = s.tick()
        #expect(s.scrollOffset == off + 100)
    }

    @Test func pointerInsideWithoutHoldFreezesScrolling() {
        var (clock, s) = make()
        let off = s.scrollOffset
        s.setPointerInside(true)
        clock.t += 10; _ = s.tick()
        #expect(s.scrollOffset == off)
        s.setPointerInside(false)
        clock.t += 1; _ = s.tick()
        #expect(s.scrollOffset == off + 100)
    }

    @Test func timeBeforePointerEntersIsCounted() {
        var (clock, s) = make()
        let t0 = s.tapeTime
        clock.t += 2                                   // 還沒 tick/advance
        s.setPointerInside(true)                       // 先推進時鐘，再凍結
        #expect(s.tapeTime == t0 + 2)
        clock.t += 5
        s.setPointerInside(false)
        #expect(s.tapeTime == t0 + 2, "凍結期間的 5 秒不計")
    }

    @Test func setPointerInsideIsIdempotent() {
        var (clock, s) = make()
        s.setPointerInside(true)
        let t = s.tapeTime
        clock.t += 3
        s.setPointerInside(true)                       // 第二次不得把期間算進去，也不得改變凍結位置
        #expect(s.tapeTime == t)
        s.setPointerInside(false); s.setPointerInside(false)
        clock.t += 1; _ = s.tick()
        #expect(s.tapeTime == t + 1)
    }

    @Test func hideDuringHoldDoesNotConsumeIt() {
        var (clock, s) = make()
        _ = s.seek(.previous)
        let off = s.scrollOffset
        s.hide(); clock.t += 3600; s.show()
        #expect(s.holdRemaining == 8 && s.scrollOffset == off)
        clock.t += 1; _ = s.tick()
        #expect(s.holdRemaining == 7 && s.scrollOffset == off)
    }

    @Test func hiddenAndPointerAreIndependent() {
        var (clock, s) = make()
        let off = s.scrollOffset
        s.setPointerInside(true)
        s.hide()
        s.setPointerInside(false)                      // 指標離開，但仍隱藏
        clock.t += 100; _ = s.tick()
        #expect(s.scrollOffset == off)
        s.show()
        clock.t += 1; _ = s.tick()
        #expect(s.scrollOffset == off + 100)

        s.hide(); s.setPointerInside(true); s.show()   // 顯示了，但指標仍在內
        clock.t += 100; _ = s.tick()
        #expect(s.scrollOffset == off + 100)
        s.setPointerInside(false)
        clock.t += 1; _ = s.tick()
        #expect(s.scrollOffset == off + 200)
    }

    // MARK: rebase 保留與回溯

    @Test func rebaseKeepsRecentPlacedSoPreviousStillWorks() {
        var (_, s) = make()
        let delta = s.rebase()
        #expect(delta == 500)
        #expect(s.placed.count == 4, "預設 retainPlacedCount=64：全部保留，含負座標")
        #expect(s.placed.first!.tapeX < 0)
        let spacingBefore = zip(s.placed, s.placed.dropFirst()).map { $1.tapeX - $0.tapeX }
        guard case .moved(let target, _) = s.seek(.previous) else { Issue.record("expected moved"); return }
        #expect(target.id == "9" && target.tapeX < 0)
        #expect(abs(leftEdge(s, target)) < 1e-9)
        #expect(zip(s.placed, s.placed.dropFirst()).map { $1.tapeX - $0.tapeX } == spacingBefore)
    }

    @Test func smallRetainCountMakesPreviousNotRetained() {
        var (_, s) = make { $0.retainPlacedCount = 2 }
        _ = s.rebase()
        #expect(s.placed.map(\.id) == ["8", "7"])
        let base = s.baseOffset, hold = s.holdRemaining
        #expect(s.readingPosition?.item.id == "8" && s.readingPosition?.index == 3)
        #expect(s.seek(.previous) == .previousNotRetained)
        #expect(s.baseOffset == base && s.holdRemaining == hold)
    }

    @Test func retainNeverDropsBelowOldBehaviourKeepRule() {
        // retainPlacedCount=1：行為退回舊規則（保留尾端與仍可見者）
        var (_, s) = make { $0.retainPlacedCount = 1 }
        _ = s.rebase()
        #expect(s.placed.map(\.id) == ["8", "7"], "右緣 > 0 的仍保留，不因 retain 較小而多丟")
    }
}

/// nav-layout-tweaks：左右切換後的停留預設 1 秒（使用者第二輪回饋）。這些測試不覆寫 `seekHoldSeconds`。
@Suite struct DefaultSeekHoldTests {
    private func makeDefault() -> (FakeClock, TickerScheduler) {
        let clock = FakeClock()
        var s = makeScheduler(clock, config: SchedulerConfig.test)
        _ = s.receive(snap(Array(1...10)))
        for t in 0...5 { clock.t = Double(t); _ = s.tick() }
        return (clock, s)
    }

    @Test func defaultIsOneSecond() {
        #expect(SchedulerConfig().seekHoldSeconds == 1)
        var (_, s) = makeDefault()
        _ = s.seek(.previous)
        #expect(s.holdRemaining == 1)
    }

    @Test func holdsForOneSecondThenResumesWithoutJump() {
        var (clock, s) = makeDefault()
        _ = s.seek(.previous)
        let off = s.scrollOffset
        clock.t += 0.5; _ = s.tick()
        #expect(s.scrollOffset == off && abs(s.holdRemaining - 0.5) < 1e-9)
        clock.t += 0.5; _ = s.tick()
        #expect(s.scrollOffset == off && s.holdRemaining == 0)
        clock.t += 2; _ = s.tick()
        #expect(s.scrollOffset == off + 2 * 100, "第 1 秒後從對齊位置接著走")
    }

    @Test func secondSeekResetsToOneSecondNotAccumulates() {
        var (clock, s) = makeDefault()
        _ = s.seek(.previous)
        clock.t += 0.6; _ = s.tick()
        #expect(abs(s.holdRemaining - 0.4) < 1e-9)
        _ = s.seek(.next)
        #expect(s.holdRemaining == 1)
    }
}
