import Testing
import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

// task 2.1：FeedClient 核心。執行：swift test --filter FeedClientTests（與 BackoffPolicyTests、PipeReaderTests）

@Suite struct BackoffPolicyTests {
    let policy = BackoffPolicy()

    @Test func doublesFromOneAndCapsAtSixty() {
        let seq = (0..<10).map { policy.nominalDelay(attempt: $0) }
        #expect(seq == [1, 2, 4, 8, 16, 32, 60, 60, 60, 60])
    }

    @Test func jitterIsWithinPlusMinusTwentyPercent() {
        #expect(policy.delay(attempt: 3, randomUnit: 0) == 8 * 0.8)
        #expect(policy.delay(attempt: 3, randomUnit: 0.5) == 8)
        #expect(abs(policy.delay(attempt: 3, randomUnit: 1) - 8 * 1.2) < 1e-9)
        #expect(policy.delay(attempt: 100, randomUnit: 1) <= 60 * 1.2 + 1e-9)    // 不溢位
    }

    @Test func resetsOnlyWhenStableLongerThanSixtySeconds() {
        var s = BackoffState()
        for _ in 0..<3 { _ = s.nextDelay(policy: policy, randomUnit: 0.5) }
        s.processEnded(ranFor: 30, policy: policy)
        #expect(s.attempt == 3)                       // 短暫運行不重置
        s.processEnded(ranFor: 60, policy: policy)
        #expect(s.attempt == 3)                       // 恰好 60 不算「超過」
        s.processEnded(ranFor: 61, policy: policy)
        #expect(s.attempt == 0)
        #expect(s.nextDelay(policy: policy, randomUnit: 0.5) == 1)
    }

    @Test func injectedRandomnessIsTheOnlySourceOfJitter() {
        var a = BackoffState(), b = BackoffState()
        let xs = (0..<6).map { _ in a.nextDelay(policy: policy, randomUnit: 0.25) }
        let ys = (0..<6).map { _ in b.nextDelay(policy: policy, randomUnit: 0.25) }
        #expect(xs == ys)
    }
}

@Suite struct PipeReaderTests {
    @Test func eofClearsHandlerAndStopsInvocations() throws {
        let pipe = Pipe()
        let box = Box()
        let reader = PipeReader(handle: pipe.fileHandleForReading,
                                onData: { box.add($0.count) }, onEOF: { box.eof() })
        pipe.fileHandleForWriting.write(Data("hello".utf8))
        try pipe.fileHandleForWriting.close()
        #expect(waitUntil { box.eofCount == 1 })
        usleep(300_000)                                   // 若 handler 未清除，這段時間會空轉數千次
        #expect(reader.handlerCleared)
        #expect(reader.invocationCount <= 3, "EOF 後 handler 不應繼續被呼叫（busy loop），實際 \(reader.invocationCount)")
        #expect(box.eofCount == 1)
        #expect(box.bytes == 5)
    }
}

final class Box: @unchecked Sendable {
    private let lock = NSLock(); private var b = 0; private var e = 0
    func add(_ n: Int) { lock.withLock { b += n } }
    func eof() { lock.withLock { e += 1 } }
    var bytes: Int { lock.withLock { b } }
    var eofCount: Int { lock.withLock { e } }
}

@Suite struct FeedClientTests {
    @Test func normalOutputIsDeliveredInOrder() {
        let sb = Sandbox()
        let helper = sb.script("normal", "echo '\(Lines.snapshot)'\necho '\(Lines.items)'\necho '\(Lines.status)'\nexec cat >/dev/null")
        let log = EventLog(), clock = FakeClock()
        let c = makeClient(helper, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.messages.count == 3 })
        let kinds = log.messages.map { m -> String in
            switch m { case .snapshot: "snapshot"; case .items: "items"; case .status: "status" }
        }
        #expect(kinds == ["snapshot", "items", "status"])
        #expect(log.exitDelays.isEmpty)
        var done = false; let flag = Box()
        c.shutdown { flag.eof() }
        done = waitUntil { flag.eofCount == 1 }
        #expect(done)
    }

    @Test func crashRestartsWithExponentialBackoffUsingFakeClock() {
        let sb = Sandbox()
        let helper = sb.script("crash", "echo '\(Lines.status)'\nexit 3")
        let log = EventLog(), clock = FakeClock()
        let c = makeClient(helper, clock: clock, log: log)
        c.start()
        for n in 1...5 {
            #expect(waitUntil { log.exitDelays.count == n }, "第 \(n) 次崩潰未被偵測")
            #expect(clock.pendingTimerCount >= 1)
            clock.advance(by: log.exitDelays[n - 1])      // 假時鐘前進到重啟點
        }
        #expect(waitUntil { log.startedCount == 6 })
        #expect(log.exitDelays == [1, 2, 4, 8, 16])      // r=0.5 → 無 jitter
        finish(c, clock)
    }

    @Test func restartHappensOnlyAfterTheBackoffDelay() {
        let sb = Sandbox()
        let helper = sb.script("crash", "exit 1")
        let log = EventLog(), clock = FakeClock()
        let c = makeClient(helper, clock: clock, log: log)
        c.start()
        #expect(waitUntil { log.exitDelays.count == 1 })
        clock.advance(by: 0.9)
        usleep(200_000)
        #expect(log.startedCount == 1, "退避時間未到不應重啟")
        clock.advance(by: 0.1)
        #expect(waitUntil { log.startedCount == 2 })
        finish(c, clock)
    }

    @Test func backoffResetsOnlyAfterStableRunOverSixtySeconds() {
        let sb = Sandbox()
        // 第 1 次：立即崩潰；之後的世代：常駐，由測試 kill。
        let counter = sb.dir.appendingPathComponent("n")
        let helper = sb.script("gen", """
        n=$(cat '\(counter.path)' 2>/dev/null || echo 0); n=$((n+1)); echo $n > '\(counter.path)'
        if [ "$n" = "1" ]; then exit 1; fi
        exec sleep 1000
        """)
        let log = EventLog(), clock = FakeClock()
        let c = makeClient(helper, clock: clock, log: log) { $0.stuckThreshold = 1e9; $0.wakeGrace = 1e9 }
        c.start()
        #expect(waitUntil { log.exitDelays.count == 1 })
        #expect(log.exitDelays == [1])
        clock.advance(by: 1)
        #expect(waitUntil { log.startedCount == 2 })
        clock.advance(by: 30)                              // 運行 30 秒後崩潰：不重置
        kill(log.pids[1], SIGKILL)
        #expect(waitUntil { log.exitDelays.count == 2 })
        #expect(log.exitDelays[1] == 2)
        clock.advance(by: 2)
        #expect(waitUntil { log.startedCount == 3 })
        clock.advance(by: 61)                              // 運行 61 秒後崩潰：重置
        kill(log.pids[2], SIGKILL)
        #expect(waitUntil { log.exitDelays.count == 3 })
        #expect(log.exitDelays[2] == 1)
        finish(c, clock)
    }

    @Test func halfLineIsAssembledAndBadLineIsSkipped() {
        let sb = Sandbox()
        let helper = sb.script("half", """
        printf '{"v":1,"type":"status","source":"fastbull",'
        sleep 0.2
        printf '"state":"ok","message":"m"}\\n'
        echo 'this is not json'
        echo '\(Lines.items)'
        exec cat >/dev/null
        """)
        let log = EventLog()
        let c = makeClient(helper, clock: FakeClock(), log: log)
        c.start()
        #expect(waitUntil { log.messages.count == 2 })
        #expect(log.messages.first == .status(Status(source: "fastbull", state: .ok, message: "m")))
        #expect(log.badLines.count == 1)
        #expect(log.badLines.first?.reason == .notJSON)
        c.shutdown()
    }

    @Test func stderrFloodDoesNotBlockHelper() {
        let sb = Sandbox()
        let helper = sb.script("flood", """
        dd if=/dev/zero bs=1048576 count=30 >&2 2>/dev/null
        echo '\(Lines.status)'
        exec cat >/dev/null
        """)
        let log = EventLog()
        let c = makeClient(helper, clock: FakeClock(), log: log)
        c.start()
        #expect(waitUntil(timeout: 20) { log.messages.count == 1 }, "stderr 塞滿導致 helper 被阻塞")
        #expect(c.diagnostics.stderrBytesDrained >= 30 * 1_048_576)
        c.shutdown()
    }

    @Test func staleGenerationEventsAreIgnored() {
        let sb = Sandbox()
        let helper = sb.script("crash", "exit 1")
        let log = EventLog(), clock = FakeClock()
        let c = makeClient(helper, clock: clock, log: log) { $0.stuckThreshold = 1e9; $0.wakeGrace = 1e9 }
        c.start()
        #expect(waitUntil { log.exitDelays.count == 1 })
        clock.advance(by: 1)
        #expect(waitUntil { log.startedCount == 2 })
        #expect(waitUntil { log.exitDelays.count == 2 })    // 第 2 代也崩潰（腳本同一支）
        // 此時 generation == 2，處於 backingOff；第 1 代遲到的終止／資料事件必須被忽略。
        let before = log.all.count
        c.queue.sync {
            c.terminated(generation: 1, status: 9)
            c.receive(Data((Lines.status + "\n").utf8), generation: 1)
        }
        usleep(100_000)
        #expect(log.all.count == before, "舊世代事件不應產生任何事件")
        if case .backingOff(let g, _) = c.diagnostics.state { #expect(g == 2) } else { Issue.record("狀態不應改變") }
        clock.advance(by: 100)
        #expect(waitUntil { log.startedCount == 3 })
        usleep(100_000)
        #expect(log.startedCount <= 4, "不應因舊事件多重啟")
        finish(c, clock)
    }

    @Test func helperPathOverrideAndBundleLookup() throws {
        let sb = Sandbox()
        let env = [FeedClientConfig.helperEnvironmentVariable: "/tmp/fake-helper"]
        #expect(FeedClientConfig.resolveHelperURL(environment: env, bundle: .main)?.path == "/tmp/fake-helper")

        // 無環境變數：用 bundle 的 Contents/MacOS/ticker-connect
        let app = sb.dir.appendingPathComponent("X.app/Contents")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>x.y</string><key>CFBundleExecutable</key><string>X</string></dict></plist>
        """.write(to: app.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let helper = app.appendingPathComponent("MacOS/ticker-connect")
        try "#!/bin/sh\n".write(to: helper, atomically: true, encoding: .utf8)
        chmod(helper.path, 0o755)
        let bundle = try #require(Bundle(url: sb.dir.appendingPathComponent("X.app")))
        let found = FeedClientConfig.resolveHelperURL(environment: [:], bundle: bundle)
        #expect(found?.resolvingSymlinksInPath().path == helper.resolvingSymlinksInPath().path)
        #expect(FeedClientConfig.resolveHelperURL(environment: ["FASTBULL_TICKER_HELPER": ""], bundle: bundle) != nil)
    }

    @Test func overrideEnvironmentStartsThatHelperInsteadOfBundleOne() {
        let sb = Sandbox()
        let fake = sb.script("override", "echo '\(Lines.status)'\nexec cat >/dev/null")
        let url = FeedClientConfig.resolveHelperURL(environment: [FeedClientConfig.helperEnvironmentVariable: fake.path], bundle: .main)
        let log = EventLog()
        let c = makeClient(url!, clock: FakeClock(), log: log)
        c.start()
        #expect(waitUntil { log.messages.count == 1 })
        c.shutdown()
    }
}
