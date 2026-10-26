import Testing
import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

/// 統一的結束流程（change quit-controls）：先隱藏、再結束、可重入、三個入口等價。
@MainActor
@Suite struct QuitCoordinatorTests {
    private func make() -> (QuitCoordinator, () -> [String]) {
        var calls: [String] = []
        let q = QuitCoordinator(hideTicker: { calls.append("hideTicker") }, hideSettings: { calls.append("hideSettings") },
                                terminate: { calls.append("terminate") }, log: AppLog(fileURL: nil, toStderr: false))
        return (q, { calls })
    }

    @Test func hidesEverythingBeforeTerminating() {
        let (q, calls) = make()
        q.request(from: "x")
        #expect(calls() == ["hideSettings", "hideTicker", "terminate"], "先收起設定面板與帶子，畫面立刻消失，最後才進入（最多約 6 秒的）優雅結束")
    }

    @Test func reentrantRequestsTerminateOnlyOnce() {
        let (q, calls) = make()
        q.request(from: "x"); q.request(from: "y"); q.request(from: "z")
        #expect(calls().filter { $0 == "terminate" }.count == 1)
        #expect(calls().count == 3)
        #expect(q.isQuitting)
    }

    @Test func allThreeEntryPointsRunTheSameSequence() {
        // ✕（router.onQuit）、設定面板（controller.onQuitApp）、選單列（menu.onQuit）接到同一個 coordinator。
        var sequences: [[String]] = []
        for entry in ["x", "settings", "menu"] {
            let (q, calls) = make()
            let router = NavigationInputRouter(geometry: HitGeometry(panelSize: CGSize(width: 300, height: 42), labelWidth: 0, linkSlotWidth: 0, quitSlotWidth: 28))
            let controller = SettingsPanelController(content: SettingsPanelContentView(), launch: LaunchAtLoginController(service: NoopLaunch()))
            let menu = StatusMenuController(config: .provisional, initialAlpha: 0.9)
            router.onQuit = { q.request(from: "x") }
            controller.onQuitApp = { q.request(from: "settings") }
            menu.onQuit = { q.request(from: "menu") }
            switch entry {
            case "x":
                router.mouseDown(at: CGPoint(x: 290, y: 20), button: .left, performDrag: {})
                router.mouseUp(at: CGPoint(x: 290, y: 20), button: .left)
            case "settings": controller.handle(.quitApp)
            default:
                let item = menu.menu.items.last!
                _ = item.target?.perform(item.action)
            }
            sequences.append(calls())
        }
        #expect(sequences.count == 3 && sequences.allSatisfy { $0 == ["hideSettings", "hideTicker", "terminate"] }, "\(sequences)")
    }

    @Test func logsWhichEntryRequestedTheQuit() {
        let log = AppLog(fileURL: nil, toStderr: false)
        let q = QuitCoordinator(hideTicker: {}, hideSettings: {}, terminate: {}, log: log)
        q.request(from: "x-button")
        q.request(from: "menu")
        #expect(log.recorded.filter { $0.contains("quit: requested") }.count == 1)
        #expect(log.recorded.contains { $0.contains("x-button") })
        #expect(log.recorded.contains { $0.contains("quit: already quitting") })
    }
}

private final class NoopLaunch: LaunchAtLoginService {
    var status: LaunchAtLoginStatus { .notRegistered }
    func enable() throws {}
    func disable() throws {}
    func openSystemSettings() {}
}

/// 整合：QuitCoordinator 的 terminate 走真的 FeedClient 優雅結束；App（這裡的 client）與 helper 都要消失、不殘留。
@MainActor
@Suite struct QuitIntegrationTests {
    @Test func quitShutsDownTheRealHelperWithoutOrphan() async throws {
        let sb = Sandbox()
        let helper = sb.script("fake-helper.sh", """
        echo $$ > "\(sb.dir.path)/helper.pid.txt"
        printf '{"v":1,"type":"snapshot","items":[{"source":"fastbull","id":"1","published_at_ms":1000,"text":"A"}]}\\n'
        while read -r _; do :; done
        """)
        let clock = ManualClock()
        let (driver, _) = makeDriver(clock: clock)
        let coord = AppCoordinator(driver: driver, log: AppLog(fileURL: nil, toStderr: false))
        let client = FeedClient(config: FeedClientConfig(helperURL: helper, pidFileURL: nil), onEvent: AppCoordinator.bridge(to: coord))
        client.start()
        let deadline = Date().addingTimeInterval(10)
        while coord.snapshots < 1 && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        #expect(coord.snapshots >= 1)
        let pid = try #require(Int32((try String(contentsOf: sb.dir.appendingPathComponent("helper.pid.txt"), encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == 0, "helper 還活著")

        var hidden = 0
        let finishedFlag = FinishedFlag()
        let q = QuitCoordinator(hideTicker: { hidden += 1 }, hideSettings: {}, terminate: {
            client.shutdown { finishedFlag.set() }
        }, log: AppLog(fileURL: nil, toStderr: false))
        q.request(from: "x-button")
        q.request(from: "menu")                     // 重入
        #expect(hidden == 1)
        let end = Date().addingTimeInterval(10)
        while !finishedFlag.value && Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        #expect(finishedFlag.value, "優雅結束完成")
        let gone = Date().addingTimeInterval(5)
        while kill(pid, 0) == 0 && Date() < gone { try? await Task.sleep(nanoseconds: 50_000_000) }
        #expect(kill(pid, 0) != 0, "helper 已結束，沒有殘留")
    }
}

private final class FinishedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    func set() { lock.withLock { v = true } }
    var value: Bool { lock.withLock { v } }
}
