import Testing
import Foundation
@testable import FastBullTickerApp

// 遮蔽防抖（切換 Space 閃爍修復）。執行：swift test --filter OcclusionDebouncer
// 全程假時鐘，不開視窗。

/// 假排程器：時間只在 `advance` 時前進，到期的工作依序執行。
@MainActor
final class FakeSchedule {
    private struct Entry { let id: Int; let due: TimeInterval; let work: @MainActor () -> Void; var cancelled = false }
    private var entries: [Entry] = []
    private var nextId = 0
    private(set) var now: TimeInterval = 0
    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        nextId += 1
        let id = nextId
        entries.append(Entry(id: id, due: now + delay, work: work))
        return { [weak self] in MainActor.assumeIsolated { if let i = self?.entries.firstIndex(where: { $0.id == id }) { self?.entries[i].cancelled = true } } }
    }
    func advance(_ dt: TimeInterval) {
        let target = now + dt
        while let e = entries.filter({ !$0.cancelled && $0.due <= target + 1e-9 }).min(by: { $0.due < $1.due }) {
            now = max(now, e.due)
            entries.removeAll { $0.id == e.id }
            e.work()
        }
        now = target
    }
}

@MainActor
struct DebounceRig {
    let fake = FakeSchedule()
    let decisions = Box()
    final class Box { var list: [OcclusionDebouncer.Decision] = [] }
    let deb: OcclusionDebouncer
    init(delay: TimeInterval = 1.0) {
        let fake = self.fake, box = self.decisions
        deb = OcclusionDebouncer(confirmDelay: delay, schedule: { fake.schedule($0, $1) }, onDecision: { box.list.append($0) })
    }
}

@MainActor
@Suite struct OcclusionDebouncerTests {
    @Test func configDelayIsOneSecondAssumption() {
        #expect(ShellConfig.provisional.occludedConfirmDelay == 1.0)
    }

    @Test func briefInvisibilityUnderOneSecondNeverFreezes() {
        let r = DebounceRig()
        r.deb.note(visible: false)
        r.fake.advance(0.6)
        r.deb.note(visible: true)
        r.fake.advance(5)
        #expect(r.decisions.list == [.cancelled])
        #expect(!r.deb.isOccluded)
    }

    @Test func sustainedInvisibilityFreezesOnlyAfterDelay() {
        let r = DebounceRig()
        r.deb.note(visible: false)
        r.fake.advance(0.99)
        #expect(r.decisions.list.isEmpty)                      // 還沒滿 1 秒：不凍結
        r.fake.advance(0.02)
        #expect(r.decisions.list == [.confirmedOccluded])
        #expect(r.deb.isOccluded)
    }

    @Test func repeatedInvisibleNotesDoNotExtendTheTimer() {
        let r = DebounceRig()
        r.deb.note(visible: false)
        r.fake.advance(0.7)
        r.deb.note(visible: false)                             // 重複通知不重設計時
        r.fake.advance(0.4)
        #expect(r.decisions.list == [.confirmedOccluded])
    }

    @Test func visibleAfterFreezeThawsImmediately() {
        let r = DebounceRig()
        r.deb.note(visible: false)
        r.fake.advance(1.5)
        r.deb.note(visible: true)                              // 不推進時間：必須立即
        #expect(r.decisions.list == [.confirmedOccluded, .thawed])
        #expect(!r.deb.isOccluded)
    }

    @Test func flappingSequenceUnderOneSecondNeverFreezes() {
        let r = DebounceRig()
        for _ in 0..<20 {
            r.deb.note(visible: false); r.fake.advance(0.4)
            r.deb.note(visible: true); r.fake.advance(0.3)
        }
        r.fake.advance(10)
        #expect(!r.decisions.list.contains(.confirmedOccluded))
        #expect(!r.deb.isOccluded)
    }

    @Test func visibleWhileAlreadyVisibleDecidesNothing() {
        let r = DebounceRig()
        r.deb.note(visible: true)
        #expect(r.decisions.list.isEmpty)
    }

    @Test func staleTimerFromCancelledRoundCannotFreezeALaterRound() {
        let r = DebounceRig()
        r.deb.note(visible: false); r.fake.advance(0.8)
        r.deb.note(visible: true)
        r.deb.note(visible: false); r.fake.advance(0.5)        // 第一輪的計時此刻到期，不得生效
        #expect(!r.decisions.list.contains(.confirmedOccluded))
        r.fake.advance(0.6)
        #expect(r.decisions.list.filter { $0 == .confirmedOccluded }.count == 1)
    }
}

@MainActor
@Suite struct OcclusionDriverIntegrationTests {
    /// 把防抖器接到 driver（與 AppDelegate 相同接法），翻動期間 renderer 不得被暫停／恢復。
    @Test func flappingDoesNotTouchRendererPauseAtAll() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        let fake = FakeSchedule()
        let deb = OcclusionDebouncer(confirmDelay: 1.0, schedule: { fake.schedule($0, $1) }) { dec in
            switch dec { case .confirmedOccluded: d.setOccluded(true); case .thawed: d.setOccluded(false); case .cancelled: break }
        }
        d.receive(.snapshot(sampleItems(3))); d.step()
        for _ in 0..<10 { deb.note(visible: false); fake.advance(0.3); deb.note(visible: true); fake.advance(0.2) }
        #expect(!r.calls.contains(.paused(true)))
        #expect(!r.calls.contains(.paused(false)))
        #expect(!d.isFrozen)
    }

    @Test func userHiddenFreezesImmediatelyAndIsNotAffectedByDebounce() {
        let clock = ManualClock()
        let (d, r) = makeDriver(clock: clock)
        let fake = FakeSchedule()
        let deb = OcclusionDebouncer(confirmDelay: 1.0, schedule: { fake.schedule($0, $1) }) { dec in
            switch dec { case .confirmedOccluded: d.setOccluded(true); case .thawed: d.setOccluded(false); case .cancelled: break }
        }
        deb.note(visible: false)                               // 防抖中
        d.setUserHidden(true)
        #expect(d.isFrozen && r.paused)                        // 立即，不等 1 秒
        fake.advance(2)                                        // 防抖確認後
        d.setUserHidden(false)
        #expect(d.isFrozen)                                    // 仍被遮蔽凍結，直到可見
        deb.note(visible: true)
        #expect(!d.isFrozen && !r.paused)
    }
}
