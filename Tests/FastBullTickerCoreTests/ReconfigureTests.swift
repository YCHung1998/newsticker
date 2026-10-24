import Testing
import Foundation
@testable import FastBullTickerCore

/// ticker-style-settings 2.1：`reconfigure`、`SchedulerTunables`、`SchedulerConfig.showTime`。
/// 基準狀態（同 SeekHoldTests）：t=5 時 placed = 10@200, 9@350, 8@500, 7@650；speed 100、scrollOffset 500、gap 20、viewport 200。
@Suite struct ReconfigureTests {
    private func make(_ tweak: (inout SchedulerConfig) -> Void = { _ in }) -> (FakeClock, TickerScheduler) {
        var cfg = SchedulerConfig.test
        tweak(&cfg)
        let clock = FakeClock()
        var s = makeScheduler(clock, config: cfg)
        _ = s.receive(snap(Array(1...10)))
        for t in 0...5 { clock.t = Double(t); _ = s.tick() }
        return (clock, s)
    }
    private func tunables(_ s: TickerScheduler, _ tweak: (inout SchedulerTunables) -> Void) -> SchedulerTunables {
        var t = SchedulerTunables(config: s.config)
        tweak(&t)
        return t
    }

    // MARK: 速度

    @Test func speedChangeKeepsVisualPositionsAndContinuesAtNewSpeed() {
        var (clock, s) = make()
        let before = s.placed.map { s.visualX(of: $0) }
        #expect(s.scrollOffset == 500 && !before.isEmpty)
        s.reconfigure(tunables(s) { $0.speed = 200 }, measurer: flatMeasure)
        #expect(s.scrollOffset == 500, "呼叫當下位置不變")
        #expect(s.placed.map { s.visualX(of: $0) } == before)
        #expect(s.config.speed == 200)
        clock.t = 6; _ = s.tick()
        #expect(abs(s.scrollOffset - 700) < 1e-9, "之後以新速度前進")
    }

    @Test func timeElapsedBeforeReconfigureIsCountedAtOldSpeed() {
        var (clock, s) = make()
        clock.t = 5.5                                   // 尚未 tick：流逝的 0.5 秒屬於舊速度
        s.reconfigure(tunables(s) { $0.speed = 200 }, measurer: flatMeasure)
        #expect(abs(s.scrollOffset - 550) < 1e-9)
        clock.t = 6.5; _ = s.tick()
        #expect(abs(s.scrollOffset - 750) < 1e-9)
    }

    @Test func speedToZeroAndBackIsContinuous() {
        var (clock, s) = make()
        s.reconfigure(tunables(s) { $0.speed = 0 }, measurer: flatMeasure)
        clock.t = 9; _ = s.tick()
        #expect(s.scrollOffset == 500)
        s.reconfigure(tunables(s) { $0.speed = 100 }, measurer: flatMeasure)
        #expect(s.scrollOffset == 500)
        clock.t = 10; _ = s.tick()
        #expect(abs(s.scrollOffset - 600) < 1e-9)
    }

    @Test func identicalTunablesChangeNothing() {
        var (_, s) = make()
        let placed = s.placed, off = s.scrollOffset, base = s.baseOffset, tt = s.tapeTime
        s.reconfigure(SchedulerTunables(config: s.config), measurer: flatMeasure)
        #expect(s.placed == placed && s.scrollOffset == off && s.baseOffset == base && s.tapeTime == tt)
    }

    // MARK: 已排入不變、之後排入採新設定

    @Test func placedItemsUnchangedAndNewOnesUseNewTunables() {
        var (clock, s) = make()
        let before = s.placed
        let doubled: TextMeasurer = { flatMeasure($0) * 2 }
        s.reconfigure(tunables(s) { $0.maxItemWidth = 500; $0.showTime = false }, measurer: doubled)
        #expect(s.placed == before, "tapeX／width／text／timeString 全部不變")
        s.tickTo(clock, 9)
        let added = Array(s.placed.dropFirst(before.count))
        #expect(!added.isEmpty)
        #expect(added.allSatisfy { $0.timeString.isEmpty && $0.width == 2 * 40 }, "showTime=false：顯示字串只有 t010 之類 4 字元，量測 ×2")
        #expect(added[0].tapeX == before.last!.tapeX + before.last!.width + 20, "與前一則間距仍為 gap")
        for (p, q) in zip(s.placed, s.placed.dropFirst()) { #expect(q.tapeX - (p.tapeX + p.width) == 20) }
    }

    @Test func timeZoneAffectsOnlyLaterItems() {
        var (clock, s) = make()
        let before = s.placed
        s.reconfigure(tunables(s) { $0.timeZone = TimeZone(secondsFromGMT: 8 * 3600)! }, measurer: flatMeasure)
        #expect(s.placed == before)
        s.tickTo(clock, 9)
        let added = Array(s.placed.dropFirst(before.count))
        #expect(!added.isEmpty && added[0].timeString != before.last!.timeString)
        #expect(added[0].timeString == TimeFormatter(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!).string(forMs: 1_000_000 + Int64(Int(added[0].id)!) * 1000))
    }

    @Test func enlargingViewportFillsToNewRightEdgeWithGap() {
        var (_, s) = make()
        let n = s.placed.count
        s.reconfigure(tunables(s) { $0.viewportWidth = 600 }, measurer: flatMeasure)
        #expect(s.placed.count == n, "reconfigure 本身不排入")
        let out = s.tick()
        #expect(!out.isEmpty)
        let tailEnd = s.placed.last!.tapeX + s.placed.last!.width
        #expect(tailEnd + 20 > s.scrollOffset + 600, "補到尾端超出新右緣")
        for (p, q) in zip(s.placed, s.placed.dropFirst()) { #expect(q.tapeX - (p.tapeX + p.width) == 20) }
    }

    @Test func shrinkingViewportDoesNotRemoveOrMove() {
        var (_, s) = make()
        let before = s.placed
        s.reconfigure(tunables(s) { $0.viewportWidth = 100 }, measurer: flatMeasure)
        #expect(s.placed == before)
        #expect(s.tick().isEmpty)
    }

    // MARK: replayCount

    @Test func shrinkingReplayCountMidRoundDoesNotCrashAndCyclesOnlyLatest() {
        let clock = FakeClock()
        var s = makeScheduler(clock)
        _ = s.receive(snap(Array(1...10)))
        var t = 0.0
        while s.placed.count < 7 { t += 1; clock.t = t; _ = s.tick() }
        #expect(s.placed.count == 7)
        s.reconfigure(tunables(s) { $0.replayCount = 5 }, measurer: flatMeasure)
        #expect(s.latestItems.map(\.id) == ["10", "9", "8", "7", "6"])
        let before = s.placed
        var added: [PlacedItem] = []
        for _ in 0..<30 { t += 1; clock.t = t; added += s.tick() }
        #expect(added.count > 10)
        #expect(Set(added.map(\.id)).isSubset(of: ["10", "9", "8", "7", "6"]))
        #expect(Array(s.placed.prefix(before.count)) == before)
    }

    @Test func growingReplayCountUsesMoreHistoryLater() {
        var (clock, s) = make { $0.replayCount = 3 }
        s.reconfigure(tunables(s) { $0.replayCount = 8 }, measurer: flatMeasure)
        var added: [PlacedItem] = []
        for i in 6...60 { clock.t = Double(i); added += s.tick() }
        #expect(Set(added.map(\.id)).contains("3"), "放大後會取到原本取不到的較舊訊息")
    }

    // MARK: 隱藏、保持、seek、rebase、模式

    @Test func reconfigureWhileHiddenIsLegalAndKeepsFrozenTime() {
        var (clock, s) = make()
        s.hide()
        let frozen = s.tapeTime, off = s.scrollOffset
        clock.t += 3600
        s.reconfigure(tunables(s) { $0.speed = 300; $0.viewportWidth = 400 }, measurer: flatMeasure)
        #expect(s.isHidden && s.tapeTime == frozen && s.scrollOffset == off)
        #expect(s.tick().isEmpty)
        s.show()
        #expect(s.scrollOffset == off)
        clock.t += 2; _ = s.tick()
        #expect(abs(s.scrollOffset - (off + 600)) < 1e-9)
    }

    @Test func holdIsUnaffectedBySpeedChange() {
        var (clock, s) = make { $0.seekHoldSeconds = 8 }       // 機制測試：明確指定 8 秒（預設值已於 nav-layout-tweaks 改為 1 秒，另有測試）
        guard case .moved(let target, _) = s.seek(.previous) else { Issue.record("expected moved"); return }
        let off = s.scrollOffset
        s.reconfigure(tunables(s) { $0.speed = 250 }, measurer: flatMeasure)
        #expect(s.holdRemaining == 8 && s.scrollOffset == off && abs(s.visualX(of: target)) < 1e-9)
        clock.t = 8; _ = s.tick()                       // 保持中（3 秒）
        #expect(s.scrollOffset == off && s.holdRemaining == 5)
        clock.t = 14; _ = s.tick()                      // 保持結束後 1 秒以新速度前進
        #expect(s.holdRemaining == 0 && abs(s.scrollOffset - (off + 250)) < 1e-9)
    }

    @Test func seekAfterSpeedChangeAlignsTargetToLeftEdge() {
        var (_, s) = make()
        s.reconfigure(tunables(s) { $0.speed = 40 }, measurer: flatMeasure)
        guard case .moved(let target, _) = s.seek(.previous) else { Issue.record("expected moved"); return }
        #expect(abs(s.visualX(of: target)) < 1e-9)
    }

    @Test func rebaseAfterReconfigureKeepsVisualPositions() {
        var (clock, s) = make()
        s.reconfigure(tunables(s) { $0.speed = 70 }, measurer: flatMeasure)
        clock.t = 8; _ = s.tick()
        let visual = Dictionary(uniqueKeysWithValues: s.placed.map { ($0.seq, s.visualX(of: $0)) })
        _ = s.rebase()
        for p in s.placed { #expect(abs(s.visualX(of: p) - visual[p.seq]!) < 1e-9) }
        clock.t = 9; _ = s.tick()
        #expect(abs(s.scrollOffset - 70) < 1e-9, "rebase 後以新速度繼續")
    }

    @Test func reconfigureKeepsModeQueueAndFixedFields() {
        var (_, s) = make()
        _ = s.receive(live([11, 12]))
        let mode = s.mode, q = s.liveQueueCount
        let gap = s.config.gap, lim = s.config.liveQueueLimit, hist = s.config.historyLimit, rb = s.config.rebaseThreshold
        s.reconfigure(tunables(s) { $0.speed = 150; $0.replayCount = 4; $0.viewportWidth = 300 }, measurer: flatMeasure)
        #expect(s.mode == mode && s.liveQueueCount == q)
        #expect(s.config.gap == gap && s.config.liveQueueLimit == lim && s.config.historyLimit == hist && s.config.rebaseThreshold == rb)
    }

    @Test func tunablesExposeExactlySixFields() {
        let names = Mirror(reflecting: SchedulerTunables(config: SchedulerConfig())).children.compactMap(\.label).sorted()
        #expect(names == ["maxItemWidth", "replayCount", "showTime", "speed", "timeZone", "viewportWidth"])
    }

    // MARK: SchedulerConfig.showTime

    @Test func schedulerConfigShowTimeDefaultsTrue() {
        #expect(SchedulerConfig().showTime)
        #expect(SchedulerTunables(config: SchedulerConfig()).showTime)
    }

    @Test func showTimeFalseInConfigPlacesTextOnly() {
        let clock = FakeClock()
        var cfg = SchedulerConfig.test
        cfg.showTime = false
        var s = makeScheduler(clock, config: cfg)
        _ = s.receive(snap([1, 2, 3]))
        clock.t = 1
        let out = s.tick()
        #expect(!out.isEmpty && out.allSatisfy { $0.timeString.isEmpty && $0.text.hasPrefix("t") && $0.width == 40 })
    }

    @Test func reconfigureTogglesShowTimeForLaterItemsOnly() {
        var (clock, s) = make()
        let before = s.placed
        #expect(before.allSatisfy { !$0.timeString.isEmpty })
        s.reconfigure(tunables(s) { $0.showTime = false }, measurer: flatMeasure)
        clock.t = 9; _ = s.tick()
        let added = s.placed.dropFirst(before.count)
        #expect(!added.isEmpty && added.allSatisfy { $0.timeString.isEmpty })
        #expect(Array(s.placed.prefix(before.count)) == before)
    }
}
