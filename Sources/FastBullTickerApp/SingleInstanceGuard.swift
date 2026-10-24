import AppKit
import Darwin

// single-instance-guard：避免兩個實例共用 helper pid 檔而互相回收 helper。
// 決策邏輯（SingleInstanceGuard）只依賴下列協定，自動測試一律注入假物件。
// 本檔是全專案唯一允許呼叫 `NSApp.activate` 的地方（見 openspec single-instance）：
// 對話框必須顯示到最前面，而 accessory App 不啟用就會藏在別的視窗後面。

struct InstanceInfo: Equatable {
    var pid: Int32
    var launchDate: Date?
}

enum ReplaceChoice: Equatable { case closeOld, cancel }
enum InstanceDecision: Equatable { case proceed, quitSelf }

protocol RunningInstancesProvider { func runningInstances() -> [InstanceInfo] }   // 含自己；由 guard 排除
protocol AlertPresenter {
    func confirmReplace() -> ReplaceChoice
    func showCannotClose()
}
protocol InstanceTerminator {
    func terminate(pid: Int32)
    func forceTerminate(pid: Int32)
    func isRunning(pid: Int32) -> Bool
}
protocol Sleeper { func sleep(_ seconds: Double) }

struct SingleInstanceGuard {
    static let allowMultipleVariable = "FASTBULL_TICKER_ALLOW_MULTIPLE"   // 【假設】名稱
    static let bundleIdentifier = "local.fastbull.FastBullTicker"
    static let gracefulTimeout = 5.0      // 【假設】
    static let forceTimeout = 2.0         // 【假設】
    static let pollInterval = 0.1

    let selfPid: Int32
    let selfLaunchDate: Date?
    let environment: [String: String]
    let provider: RunningInstancesProvider
    let alert: AlertPresenter
    let terminator: InstanceTerminator
    let sleeper: Sleeper

    func run() -> InstanceDecision {
        if environment[Self.allowMultipleVariable] == "1" { return .proceed }
        let others = provider.runningInstances().filter { $0.pid != selfPid }
        if others.isEmpty { return .proceed }
        // 競態：只有對所有其他實例都「較晚」者才詢問；較早者照常執行。
        guard others.allSatisfy({ isLater(selfPid, selfLaunchDate, than: $0) }) else { return .proceed }
        guard alert.confirmReplace() == .closeOld else { return .quitSelf }

        let pids = others.map(\.pid)
        pids.forEach { terminator.terminate(pid: $0) }
        var remaining = waitUntilGone(pids, limit: Self.gracefulTimeout)
        if !remaining.isEmpty {
            remaining.forEach { terminator.forceTerminate(pid: $0) }
            remaining = waitUntilGone(remaining, limit: Self.forceTimeout)
        }
        if remaining.isEmpty { return .proceed }
        alert.showCannotClose()
        return .quitSelf
    }

    /// 兩邊 launchDate 都有且不同 → 較大者較晚；否則（相同或缺漏）pid 較大者較晚。
    private func isLater(_ pid: Int32, _ date: Date?, than other: InstanceInfo) -> Bool {
        if let a = date, let b = other.launchDate, a != b { return a > b }
        return pid > other.pid
    }

    private func waitUntilGone(_ pids: [Int32], limit: Double) -> [Int32] {
        var waited = 0.0
        var alive = pids.filter { terminator.isRunning(pid: $0) }
        while !alive.isEmpty, waited < limit - 1e-9 {
            sleeper.sleep(Self.pollInterval)
            waited += Self.pollInterval
            alive = alive.filter { terminator.isRunning(pid: $0) }
        }
        return alive
    }

    /// 真實組裝（無 bundle identifier，例如 `swift run`，視為無需檢查）。
    @MainActor
    static func makeSystem(environment: [String: String]) -> SingleInstanceGuard {
        let id = Bundle.main.bundleIdentifier ?? ""
        return SingleInstanceGuard(
            selfPid: ProcessInfo.processInfo.processIdentifier,
            selfLaunchDate: NSRunningApplication.current.launchDate,
            environment: environment,
            provider: id == bundleIdentifier ? SystemInstancesProvider(bundleIdentifier: id) : EmptyInstancesProvider(),
            alert: NSAlertPresenter(), terminator: SystemInstanceTerminator(), sleeper: RunLoopSleeper())
    }
}

// MARK: 真實實作（測試不得引用）

struct EmptyInstancesProvider: RunningInstancesProvider { func runningInstances() -> [InstanceInfo] { [] } }

struct SystemInstancesProvider: RunningInstancesProvider {
    let bundleIdentifier: String
    func runningInstances() -> [InstanceInfo] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map { InstanceInfo(pid: $0.processIdentifier, launchDate: $0.launchDate) }
    }
}

struct SystemInstanceTerminator: InstanceTerminator {
    func terminate(pid: Int32) { _ = NSRunningApplication(processIdentifier: pid)?.terminate() }
    func forceTerminate(pid: Int32) { _ = NSRunningApplication(processIdentifier: pid)?.forceTerminate() }
    /// `kill(pid, 0)`：不依賴 run loop 更新 `isTerminated`（guard 在主執行緒輪詢）。EPERM 表示存在但無權限。
    func isRunning(pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}

struct RunLoopSleeper: Sleeper {
    func sleep(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
}

/// 只會在主執行緒由 `AppDelegate` 呼叫（`makeSystem` 為 @MainActor）。
final class NSAlertPresenter: AlertPresenter, @unchecked Sendable {
    private var activated = false

    func confirmReplace() -> ReplaceChoice {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = "FastBullTicker 已在執行"
            alert.informativeText = "要關閉先前開啟的那個，改用這個嗎？"
            alert.addButton(withTitle: "關閉舊的並繼續")   // 第一個＝預設
            alert.addButton(withTitle: "取消")
            return present(alert) == .alertFirstButtonReturn ? .closeOld : .cancel
        }
    }

    func showCannotClose() {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.messageText = "無法關閉舊的實例"
            alert.informativeText = "無法關閉舊的實例，請手動關閉。"
            alert.addButton(withTitle: "好")
            _ = present(alert)
        }
    }

    @MainActor private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if !activated { activated = true; NSApp.activate() }   // 全專案唯一的啟用呼叫（整個程序最多一次）
        return alert.runModal()
    }
}
