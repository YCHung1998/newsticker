import Testing
import Foundation
@testable import FastBullTickerApp

// single-instance-guard：全部以假物件驗證決策；不建立真實 NSAlert、不呼叫真實 terminate、不開視窗。

final class FakeAlert: AlertPresenter {
    var choice: ReplaceChoice = .closeOld
    private(set) var confirmCount = 0
    private(set) var cannotCloseCount = 0
    func confirmReplace() -> ReplaceChoice { confirmCount += 1; return choice }
    func showCannotClose() { cannotCloseCount += 1 }
}

final class FakeWorld: InstanceTerminator, Sleeper, RunningInstancesProvider {
    var instances: [InstanceInfo]
    /// 存活的 pid；`diesAfterTerminate`／`diesAfterForce` 為多久（累計睡眠秒）後消失，nil＝永不。
    var alive: Set<Int32>
    var diesAfterTerminate: Double? = 1
    var diesAfterForce: Double? = 0.5
    private(set) var terminated: [Int32] = []
    private(set) var forced: [Int32] = []
    private(set) var slept: Double = 0
    private var terminateAt: [Int32: Double] = [:]
    private var forceAt: [Int32: Double] = [:]
    init(instances: [InstanceInfo]) { self.instances = instances; alive = Set(instances.map(\.pid)) }

    func runningInstances() -> [InstanceInfo] { instances }
    func terminate(pid: Int32) { terminated.append(pid); terminateAt[pid] = slept }
    func forceTerminate(pid: Int32) { forced.append(pid); forceAt[pid] = slept }
    func isRunning(pid: Int32) -> Bool {
        if let t = terminateAt[pid], let d = diesAfterTerminate, slept - t >= d { alive.remove(pid) }
        if let t = forceAt[pid], let d = diesAfterForce, slept - t >= d { alive.remove(pid) }
        return alive.contains(pid)
    }
    func sleep(_ seconds: Double) { slept += seconds }
}

@Suite struct SingleInstanceGuardTests {
    static let me: Int32 = 500
    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    func make(_ world: FakeWorld, _ alert: FakeAlert, env: [String: String] = [:], myDate: Date? = t0.addingTimeInterval(10)) -> SingleInstanceGuard {
        SingleInstanceGuard(selfPid: Self.me, selfLaunchDate: myDate, environment: env,
                            provider: world, alert: alert, terminator: world, sleeper: world)
    }
    func old(_ pid: Int32 = 100, date: Date? = t0) -> InstanceInfo { InstanceInfo(pid: pid, launchDate: date) }
    var selfInfo: InstanceInfo { InstanceInfo(pid: Self.me, launchDate: Self.t0.addingTimeInterval(10)) }

    @Test func noOtherInstanceProceedsSilently() {
        let w = FakeWorld(instances: [selfInfo]); let a = FakeAlert()
        #expect(make(w, a).run() == .proceed)
        #expect(a.confirmCount == 0 && w.terminated.isEmpty && w.forced.isEmpty)
    }

    @Test func cancelQuitsSelfAndNeverTouchesOld() {
        let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert(); a.choice = .cancel
        #expect(make(w, a).run() == .quitSelf)
        #expect(a.confirmCount == 1 && w.terminated.isEmpty && w.forced.isEmpty && a.cannotCloseCount == 0)
    }

    @Test func closeOldTerminatesThenProceedsWithoutForce() {
        let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert()
        #expect(make(w, a).run() == .proceed)
        #expect(w.terminated == [100] && w.forced.isEmpty && a.cannotCloseCount == 0)
        #expect(!w.alive.contains(100))
    }

    @Test func doesNotProceedBeforeOldIsGone() {
        let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert()
        w.diesAfterTerminate = 3.0          // 3 秒後才消失：必須等到那時才繼續
        #expect(make(w, a).run() == .proceed)
        #expect(w.slept >= 2.9 && w.slept < 5.5)
        #expect(w.forced.isEmpty)
    }

    @Test func forceTerminatesWhenStillAliveAfterFiveSeconds() {
        let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert()
        w.diesAfterTerminate = nil; w.diesAfterForce = 0.5
        #expect(make(w, a).run() == .proceed)
        #expect(w.forced == [100])
        #expect(w.slept >= 4.9 && w.slept < 7.0)
    }

    @Test func failsWithSecondAlertWhenForceDoesNotWork() {
        let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert()
        w.diesAfterTerminate = nil; w.diesAfterForce = nil
        #expect(make(w, a).run() == .quitSelf)
        #expect(a.cannotCloseCount == 1 && w.forced == [100])
        #expect(w.slept >= 6.9 && w.slept < 7.5)
    }

    @Test func terminateIsOnlyEverCalledOnOthersNeverSelf() {
        let w = FakeWorld(instances: [selfInfo, old(100), old(101, date: Self.t0.addingTimeInterval(1))]); let a = FakeAlert()
        w.diesAfterTerminate = nil; w.diesAfterForce = nil
        _ = make(w, a).run()
        #expect(!w.terminated.contains(Self.me) && !w.forced.contains(Self.me))
        #expect(Set(w.terminated) == [100, 101] && Set(w.forced) == [100, 101])
    }

    @Test func raceOtherIsLaterDoesNotAskAndProceeds() {
        let w = FakeWorld(instances: [selfInfo, InstanceInfo(pid: 100, launchDate: Self.t0.addingTimeInterval(20))]); let a = FakeAlert()
        #expect(make(w, a).run() == .proceed)
        #expect(a.confirmCount == 0 && w.terminated.isEmpty)
    }

    @Test func sameLaunchDateDecidedByPid() {
        let d = Self.t0.addingTimeInterval(10)
        // 我 pid 500 > 100 → 我較晚 → 詢問
        var w = FakeWorld(instances: [selfInfo, InstanceInfo(pid: 100, launchDate: d)]); var a = FakeAlert(); a.choice = .cancel
        #expect(make(w, a).run() == .quitSelf && a.confirmCount == 1)
        // 對方 pid 900 > 500 → 對方較晚 → 我不詢問
        w = FakeWorld(instances: [selfInfo, InstanceInfo(pid: 900, launchDate: d)]); a = FakeAlert()
        #expect(make(w, a).run() == .proceed && a.confirmCount == 0)
    }

    @Test func missingLaunchDateFallsBackToPid() {
        var w = FakeWorld(instances: [InstanceInfo(pid: Self.me, launchDate: nil), InstanceInfo(pid: 100, launchDate: Self.t0)]); var a = FakeAlert(); a.choice = .cancel
        #expect(make(w, a, myDate: nil).run() == .quitSelf && a.confirmCount == 1)
        w = FakeWorld(instances: [selfInfo, InstanceInfo(pid: 900, launchDate: nil)]); a = FakeAlert()
        #expect(make(w, a).run() == .proceed && a.confirmCount == 0)
    }

    @Test func bothSidesNeverAsk() {
        // 同一份世界從兩個實例的視角各跑一次：最多一邊詢問。
        let a1 = Self.t0, a2 = Self.t0.addingTimeInterval(0.3)
        let world = [InstanceInfo(pid: 10, launchDate: a1), InstanceInfo(pid: 20, launchDate: a2)]
        var asks = 0
        for (pid, date) in [(Int32(10), a1), (Int32(20), a2)] {
            let w = FakeWorld(instances: world); let al = FakeAlert(); al.choice = .cancel
            _ = SingleInstanceGuard(selfPid: pid, selfLaunchDate: date, environment: [:], provider: w, alert: al, terminator: w, sleeper: w).run()
            asks += al.confirmCount
        }
        #expect(asks == 1)
    }

    @Test func environmentOneSkipsEverything() {
        let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert()
        #expect(make(w, a, env: ["FASTBULL_TICKER_ALLOW_MULTIPLE": "1"]).run() == .proceed)
        #expect(a.confirmCount == 0 && w.terminated.isEmpty)
    }

    @Test func otherEnvironmentValuesDoNotSkip() {
        for v in ["0", "", "true"] {
            let w = FakeWorld(instances: [selfInfo, old()]); let a = FakeAlert(); a.choice = .cancel
            #expect(make(w, a, env: ["FASTBULL_TICKER_ALLOW_MULTIPLE": v]).run() == .quitSelf, "value=\(v)")
            #expect(a.confirmCount == 1)
        }
    }

    // MARK: 靜態守衛

    @Test func activateAppearsOnlyInSingleInstanceGuardExactlyOnce() throws {
        let root = try #require(OpenerGuard.repoRoot())
        let hits = OpenerGuard.activationHitCounts(root: root)
        #expect(hits == ["SingleInstanceGuard.swift": 1], "\(hits)")
        #expect(OpenerGuard.activationViolations(root: root).isEmpty)
    }

    @Test func plantedActivateInOtherFileIsStillCaught() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let code = "func f() { NSApp.activate() }"
        try code.write(to: d.appendingPathComponent("Sources/SingleInstanceGuard.swift"), atomically: true, encoding: .utf8)
        #expect(OpenerGuard.activationViolations(root: d).isEmpty)
        try code.write(to: d.appendingPathComponent("Sources/Other.swift"), atomically: true, encoding: .utf8)
        #expect(OpenerGuard.activationViolations(root: d) == ["Other.swift"])
        try? FileManager.default.removeItem(at: d.appendingPathComponent("Sources/Other.swift"))
        try (code + "\n" + code).write(to: d.appendingPathComponent("Sources/SingleInstanceGuard.swift"), atomically: true, encoding: .utf8)
        #expect(OpenerGuard.activationViolations(root: d) == ["SingleInstanceGuard.swift (超過一處)"])
    }

    @Test func testsNeverTouchRealAlertOrTerminator() throws {
        let root = try #require(OpenerGuard.repoRoot())
        let bad = ["NSAlert" + "(", "NSAlert" + "Presenter", "SystemInstance" + "Terminator", "RunLoop" + "Sleeper"]
        for f in OpenerGuard.swiftFiles(under: root.appendingPathComponent("Tests")) {
            let s = try String(contentsOf: f, encoding: .utf8)
            for b in bad { #expect(!s.contains(b), "\(f.lastPathComponent) 含 \(b)") }
        }
    }

    @Test func appDelegateChecksBeforePanelAndFeed() throws {
        let root = try #require(OpenerGuard.repoRoot())
        let s = try String(contentsOf: root.appendingPathComponent("Sources/FastBullTickerApp/AppDelegate.swift"), encoding: .utf8)
        let i = try #require(s.range(of: "instanceCheck(")?.lowerBound)
        let p = try #require(s.range(of: "PanelShell(config")?.lowerBound)
        let f = try #require(s.range(of: "startFeed(coordinator)")?.lowerBound)
        #expect(i < p && i < f)
        // 結束新實例時立即 return
        let tail = s[i...].prefix(400)
        #expect(tail.contains("return"))
    }
}
