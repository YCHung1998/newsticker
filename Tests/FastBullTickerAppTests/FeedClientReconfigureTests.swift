import Testing
import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

// settings-gear task 5：`helperArguments`、`FeedClient.reconfigure(arguments:)`（計畫性重啟）。執行：swift test --filter FeedClientReconfigure
// 全部使用假 helper 腳本（/bin/sh 暫存腳本）＋假時鐘；不連網、不碰真實 helper。

@Suite struct HelperArgumentsTests {
    @Test func defaultIntervalPassesNoArguments() {
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 10) == [])
    }
    @Test func otherIntervalsPassIntervalMs() {
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 30) == ["--interval-ms", "30000"])
        #expect(FeedClientConfig.helperArguments(pollIntervalSeconds: 60) == ["--interval-ms", "60000"])
    }
    @Test func everyStepProducesAParseableArgumentPair() {
        for step in StyleRanges.pollIntervalSteps {
            let a = FeedClientConfig.helperArguments(pollIntervalSeconds: step)
            #expect(a.isEmpty || (a.count == 2 && a[0] == "--interval-ms" && Int(a[1]) == step * 1000))
        }
    }
}

@Suite struct FeedClientReconfigureTests {
    /// 啟動時把自己的參數與 pid 各記一行、送出 snapshot，然後等 stdin EOF（`exec cat`）才結束。
    /// `crashflag` 存在時改為立刻 `exit 1`（用來製造真正的崩潰）。
    private func recordingHelper(_ sb: Sandbox, ignoreEOF: Bool = false) -> (URL, URL) {
        let args = sb.dir.appendingPathComponent("args.log")
        var body = "echo \"$$ $*\" >> \"\(args.path)\"\n"
        body += "[ -f \"\(sb.dir.path)/crashflag\" ] && exit 1\n"
        body += "echo '\(Lines.snapshot)'\n"
        body += ignoreEOF ? "trap 'exit 0' TERM\nwhile :; do sleep 0.05; done" : "exec cat >/dev/null"
        return (sb.script("recording", body), args)
    }
    private func argLines(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map { line in
            line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().joined(separator: " ")
        }
    }
    private func pidLines(_ url: URL) -> [Int32] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { Int32($0.split(separator: " ").first ?? "") }
    }

    @Test func startupArgumentsReachTheHelper() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log) { $0.arguments = FeedClientConfig.helperArguments(pollIntervalSeconds: 60) }
        c.start()
        #expect(waitUntil { argLines(args).count == 1 })
        #expect(argLines(args) == ["--interval-ms 60000"])
        finish(c, clock)
    }

    @Test func runningHelperIsRestartedWithTheNewArguments() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        let oldPid = log.pids[0]
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        #expect(waitUntil { log.startedCount == 2 })
        #expect(waitUntil { argLines(args).count == 2 })
        #expect(argLines(args) == ["", "--interval-ms 30000"])
        #expect(log.pids[1] != oldPid && waitUntil { !processIsAlive(oldPid) }, "舊 helper 已結束")
        #expect(log.exitDelays == [0], "計畫性重啟：立即重啟、沒有退避等待")
        #expect(log.stuckCount == 0 && log.badLines.isEmpty)
        // 新 helper 也送了 snapshot（每次啟動都會再送一次）
        #expect(waitUntil { log.messages.filter { if case .snapshot = $0 { return true } else { return false } }.count == 2 })
        #expect(c.diagnostics.generation == 2)
        finish(c, clock)
    }

    @Test func sameArgumentsDoNotRestart() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 && argLines(args).count == 1 })      // 腳本已實際跑起來
        c.reconfigure(arguments: [])
        c.queue.sync {}
        usleep(300_000)
        #expect(log.startedCount == 1 && argLines(args).count == 1 && log.exitDelays.isEmpty)
        c.reconfigure(arguments: ["--interval-ms", "60000"])
        #expect(waitUntil { log.startedCount == 2 })
        c.reconfigure(arguments: ["--interval-ms", "60000"])
        c.queue.sync {}
        usleep(300_000)
        #expect(log.startedCount == 2, "與目前（已套用）的參數相同不再重啟")
        finish(c, clock)
    }

    @Test func plannedRestartsDoNotTouchTheBackoffState() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, _) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        #expect(waitUntil { log.startedCount == 2 })
        c.reconfigure(arguments: ["--interval-ms", "60000"])
        #expect(waitUntil { log.startedCount == 3 })
        // 之後讓下一個 helper 真的崩潰：退避應從第一階（base 1 秒、jitter 0）開始，而不是被前兩次計畫性重啟墊高。
        FileManager.default.createFile(atPath: sb.dir.appendingPathComponent("crashflag").path, contents: Data())
        c.reconfigure(arguments: [])
        #expect(waitUntil { log.startedCount == 4 })        // 第四個 helper 啟動即崩潰
        #expect(waitUntil { log.exitDelays.count == 4 })
        #expect(log.exitDelays == [0, 0, 0, 1], "前三次是計畫性（0），真正崩潰的退避仍是第一階 1 秒：\(log.exitDelays)")
        finish(c, clock)
    }

    @Test func secondCallWhileRestartIsPendingMergesIntoOneRestart() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb, ignoreEOF: true)       // 忽略 stdin EOF：重啟會卡到 SIGTERM
        let ready = sb.dir.appendingPathComponent("ready")
        _ = ready
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { argLines(args).count == 1 })
        usleep(300_000)                                              // 讓 trap 就緒
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        usleep(300_000)
        #expect(log.startedCount == 1, "舊 helper 忽略 EOF，重啟尚未完成")
        c.reconfigure(arguments: ["--interval-ms", "60000"])
        clock.advance(by: 2)                                         // terminateTimeout → SIGTERM
        #expect(waitUntil { log.startedCount == 2 })
        usleep(300_000)
        #expect(log.startedCount == 2, "合併：只再啟動一個新 helper")
        #expect(argLines(args) == ["", "--interval-ms 60000"], "參數為最後一次呼叫的值")
        finish(c, clock)
    }

    @Test func helperIgnoringEofIsTerminatedBySigtermAndLeavesNoOrphan() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb, ignoreEOF: true)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { argLines(args).count == 1 })
        usleep(300_000)
        let oldPid = pidLines(args)[0]
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        usleep(300_000)
        #expect(processIsAlive(oldPid), "逾時前仍在")
        clock.advance(by: 2)
        #expect(waitUntil { log.startedCount == 2 })
        #expect(waitUntil { !processIsAlive(oldPid) }, "SIGTERM 後舊 helper 結束，沒有孤兒")
        finish(c, clock)
    }

    @Test func reconfigureWhileBackingOffOnlyUpdatesTheNextLaunch() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        FileManager.default.createFile(atPath: sb.dir.appendingPathComponent("crashflag").path, contents: Data())
        let (h, args) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.exitDelays.count == 1 })             // 崩潰、退避等待中
        c.reconfigure(arguments: ["--interval-ms", "60000"])
        c.queue.sync {}
        usleep(200_000)
        #expect(log.startedCount == 1, "退避中不額外啟動")
        try? FileManager.default.removeItem(at: sb.dir.appendingPathComponent("crashflag"))
        clock.advance(by: log.exitDelays[0])
        #expect(waitUntil { log.startedCount == 2 })
        #expect(waitUntil { argLines(args).count == 2 })
        #expect(argLines(args).last == "--interval-ms 60000", "下一次啟動使用新參數")
        finish(c, clock)
    }

    @Test func reconfigureAfterShutdownDoesNothing() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        let done = Box()
        c.shutdown { done.eof() }
        #expect(waitUntil { done.eofCount == 1 })
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        c.queue.sync {}
        usleep(300_000)
        #expect(log.startedCount == 1 && argLines(args).count == 1 && c.diagnostics.state == .stopped)
    }

    @Test func reconfigureBeforeStartUsesTheNewArgumentsAtStart() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, args) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        c.start()
        #expect(waitUntil { argLines(args).count == 1 })
        #expect(argLines(args) == ["--interval-ms 30000"] && log.startedCount == 1)
        finish(c, clock)
    }

    @Test func staleOutputFromTheOldGenerationIsIgnoredAfterRestart() {
        let sb = Sandbox(), log = EventLog(), clock = FakeClock()
        let (h, _) = recordingHelper(sb)
        let c = makeClient(h, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.startedCount == 1 })
        c.reconfigure(arguments: ["--interval-ms", "30000"])
        #expect(waitUntil { log.startedCount == 2 })
        let before = log.messages.count
        c.queue.sync { c.receive(Data((Lines.items + "\n").utf8), generation: 1) }     // 舊世代的延遲輸出
        #expect(log.messages.count == before)
        finish(c, clock)
    }
}
