import Testing
import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

// task 2.2：FeedClient 韌性。執行：swift test --filter FeedClientResilience

@Suite struct FeedClientResilienceTests {
    /// 啟動一個「完全不輸出、不退出」的 helper（exec sleep → pid 即 sleep，可被 SIGTERM 直接終止）。
    private func silentClient(_ sb: Sandbox, _ clock: FakeClock, _ log: EventLog) -> FeedClient {
        let helper = sb.script("silent", "exec sleep 1000")
        return makeClient(helper, clock: clock, log: log)
    }

    // MARK: 卡死判定

    @Test func noOutputBeyondThresholdIsStuckAndRestarts() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let c = silentClient(sb, clock, log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        clock.advance(by: 89.9)
        usleep(150_000)
        #expect(log.stuckCount == 0, "閾值（90 秒）之前不得判定卡死")
        clock.advance(by: 0.1)
        #expect(waitUntil { log.stuckCount == 1 })
        #expect(waitUntil { log.exitDelays.count == 1 })           // 被終止後走退避
        clock.advance(by: log.exitDelays[0])
        #expect(waitUntil { log.startedCount == 2 })
        finish(c, clock)
    }

    @Test func anyOutputResetsTheTimerEvenWithoutStatus() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let c = silentClient(sb, clock, log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        clock.advance(by: 80)
        // 只有 items、沒有 status 的輸出（間隔小於閾值）
        c.queue.sync { c.receive(Data((Lines.items + "\n").utf8), generation: 1) }
        clock.advance(by: 89.9)                                     // 距上次輸出 89.9 秒
        usleep(150_000)
        #expect(log.stuckCount == 0)
        clock.advance(by: 0.1)
        #expect(waitUntil { log.stuckCount == 1 })
        finish(c, clock)
    }

    @Test func partialLineBytesCountAsAlive() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let c = silentClient(sb, clock, log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        clock.advance(by: 85)
        c.queue.sync { c.receive(Data(#"{"v":1,"type":"sta"#.utf8), generation: 1) }   // 無換行
        clock.advance(by: 89)
        usleep(150_000)
        #expect(log.stuckCount == 0)
        finish(c, clock)
    }

    // MARK: 喚醒寬限

    @Test func wakeGivesAFreshGracePeriod() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let c = silentClient(sb, clock, log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        clock.advance(by: 60)
        c.noteWake()                                               // 睡眠 5 分鐘後喚醒（假時鐘此刻 t=60）
        usleep(100_000)
        clock.advance(by: 89)                                      // t=149：若無寬限早在 t=90 判定卡死
        usleep(150_000)
        #expect(log.stuckCount == 0, "喚醒寬限內不得判定卡死")
        clock.advance(by: 1)                                       // t=150 = 喚醒 + 90
        #expect(waitUntil { log.stuckCount == 1 })
        finish(c, clock)
    }

    @Test func wakeNotificationFromWorkspaceCenterReachesClient() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let c = silentClient(sb, clock, log)
        let center = NotificationCenter()
        let name = Notification.Name("test.didWake")
        let observer = WakeObserver(client: c, center: center, name: name)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        clock.advance(by: 60)
        center.post(name: name, object: nil)
        usleep(100_000)
        clock.advance(by: 89)
        usleep(150_000)
        #expect(log.stuckCount == 0)
        withExtendedLifetime(observer) {}
        finish(c, clock)
    }

    // MARK: 不可恢復錯誤

    @Test func missingExecutableIsFatalWithSingleAttempt() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let missing = sb.dir.appendingPathComponent("no-such-helper")
        let c = makeClient(missing, clock: clock, log: log)
        c.start()
        #expect(waitUntil { if case .failed = c.diagnostics.state { return true } else { return false } })
        clock.advance(by: 100_000)                                 // 再久也不會重啟
        usleep(200_000)
        let d = c.diagnostics
        #expect(d.launchAttempts == 1)
        #expect(d.state == .failed(.helperNotFound(path: missing.path)))
        #expect(log.all == [.fatal(.helperNotFound(path: missing.path))])
        #expect(clock.pendingTimerCount == 0)
    }

    @Test func nonExecutableIsFatalWithoutBackoffLoop() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let h = sb.script("noexec", "exit 0", executable: false)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { if case .failed = c.diagnostics.state { return true } else { return false } })
        clock.advance(by: 100_000)
        usleep(200_000)
        #expect(c.diagnostics.launchAttempts == 1)
        #expect(c.diagnostics.state == .failed(.notExecutable(path: h.path)))
        #expect(log.exitDelays.isEmpty)
    }

    @Test func launchFailureOfExecutableWithoutValidFormatIsFatal() throws {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let url = sb.dir.appendingPathComponent("garbage")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        chmod(url.path, 0o755)
        let c = makeClient(url, clock: clock, log: log)
        c.start()
        #expect(waitUntil { if case .failed = c.diagnostics.state { return true } else { return false } })
        clock.advance(by: 100_000)
        usleep(200_000)
        #expect(c.diagnostics.launchAttempts == 1)
        if case .failed(.launchFailed) = c.diagnostics.state {} else { Issue.record("預期 launchFailed，實際 \(c.diagnostics.state)") }
    }

    // MARK: 結束流程

    @Test func shutdownClosesStdinAndCooperativeHelperIsNotSigtermed() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let h = sb.script("coop", "trap 'echo term > \"\(sb.marker.path)\"; exit 0' TERM\ncat >/dev/null")
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        let done = Box()
        c.shutdown { done.eof() }
        #expect(waitUntil { done.eofCount == 1 })                  // 假時鐘未前進，只可能因 stdin EOF 結束
        clock.advance(by: 10)
        usleep(200_000)
        #expect(!FileManager.default.fileExists(atPath: sb.marker.path), "配合的 helper 不該收到 SIGTERM")
        #expect(c.diagnostics.state == .stopped)
        #expect(log.exitDelays.isEmpty, "結束流程不得觸發重啟")
    }

    @Test func shutdownSendsSigtermAfterTimeoutWhenHelperIgnoresEof() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let ready = sb.dir.appendingPathComponent("ready")
        let h = sb.script("stubborn", "trap 'echo term > \"\(sb.marker.path)\"; exit 0' TERM\necho 1 > \"\(ready.path)\"\nwhile :; do sleep 0.05; done")
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        #expect(waitUntil { FileManager.default.fileExists(atPath: ready.path) })   // trap 已就緒
        let done = Box()
        c.shutdown { done.eof() }
        usleep(400_000)
        #expect(done.eofCount == 0, "忽略 EOF 的 helper 在逾時前不該已結束")
        clock.advance(by: 1.9)
        usleep(400_000)
        #expect(!FileManager.default.fileExists(atPath: sb.marker.path))
        clock.advance(by: 0.1)                                     // 2 秒逾時
        #expect(waitUntil { FileManager.default.fileExists(atPath: sb.marker.path) }, "逾時後應收到 SIGTERM")
        #expect(waitUntil { done.eofCount == 1 })
        #expect(c.diagnostics.state == .stopped)
    }

    @Test func shutdownWhileBackingOffCancelsRestart() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let h = sb.script("crash", "exit 1")
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.exitDelays.count == 1 })
        let done = Box()
        c.shutdown { done.eof() }
        #expect(waitUntil { done.eofCount == 1 })
        clock.advance(by: 100)
        usleep(200_000)
        #expect(log.startedCount == 1)
    }

    // MARK: 雙實例窗口（pid file）

    /// 啟動一個真的孤兒（父行程已結束 → ppid==1），回傳其 pid。
    private func spawnOrphan(_ script: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "'\(script.path)' </dev/null >/dev/null 2>&1 & echo $!"]
        let out = Pipe(); p.standardOutput = out
        try p.run(); p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return try #require(Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @Test func staleOrphanHelperIsKilledBeforeNewOneStarts() throws {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let helper = sb.script("pollhelper", "while :; do sleep 0.2; done")
        let orphan = try spawnOrphan(helper)
        defer { kill(orphan, SIGKILL) }
        #expect(waitUntil { processIsAlive(orphan) })
        PidFile(url: sb.pidFile).write(pid: orphan, helper: helper.path)     // 模擬上一個 App 被 kill -9 遺留的 pid file

        let c = makeClient(helper, clock: clock, log: log) { $0.pidFileURL = sb.pidFile; $0.terminateTimeout = 0.3 }
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        #expect(!processIsAlive(orphan), "舊 helper 必須在新 helper 啟動前被終止")
        #expect(log.all.contains(.reclaimedStaleHelper(pid: orphan)))
        let current = log.pids[0]
        #expect(PidFile(url: sb.pidFile).read() == PidFile.Record(pid: current, helper: helper.path))
        // 同一時刻只剩一個 helper
        let alive = (try pgrepCount(sb.dir.path))
        #expect(alive == 1, "預期只剩 1 個 helper，實際 \(alive)")
        finish(c, clock)
        usleep(100_000)
        clock.advance(by: 0.3)                                      // 此 helper 忽略 stdin EOF，逾時後 SIGTERM
        #expect(waitUntil(timeout: 5) { !processIsAlive(current) })
        #expect(PidFile(url: sb.pidFile).read() == nil, "正常結束後 pid file 應清除")
    }

    @Test func pidFileOfUnrelatedLiveProcessIsNotKilled() throws {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let helper = sb.script("pollhelper", "while :; do sleep 0.2; done")
        let other = sb.script("innocent", "while :; do sleep 0.2; done")
        let innocent = try spawnOrphan(other)                       // pid 被重用的情境：命令列不含 helper 路徑
        defer { kill(innocent, SIGKILL) }
        #expect(waitUntil { processIsAlive(innocent) })
        PidFile(url: sb.pidFile).write(pid: innocent, helper: helper.path)
        let c = makeClient(helper, clock: clock, log: log) { $0.pidFileURL = sb.pidFile; $0.terminateTimeout = 0.3 }
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        #expect(processIsAlive(innocent), "不相干的行程不得被終止")
        finish(c, clock)
        usleep(100_000)
        clock.advance(by: 0.3)
        #expect(waitUntil(timeout: 5) { !processIsAlive(log.pids[0]) })
    }

    private func pgrepCount(_ pattern: String) throws -> Int {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-f", pattern]
        let out = Pipe(); p.standardOutput = out
        try p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").compactMap { Int32($0) }.filter { processIsAlive($0) }.count
    }
}
