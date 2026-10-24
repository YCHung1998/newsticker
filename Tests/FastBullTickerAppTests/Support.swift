import Foundation
import Darwin
@testable import FastBullTickerApp
import FastBullTickerCore

/// 假時鐘：時間只在 `advance(by:)` 時前進；到期的計時器依序在其 queue 上執行並等待完成。
final class FakeClock: FeedClock, @unchecked Sendable {
    private final class Entry: FeedTimer, @unchecked Sendable {
        let due: TimeInterval; let queue: DispatchQueue; let block: @Sendable () -> Void
        var cancelled = false
        init(due: TimeInterval, queue: DispatchQueue, block: @escaping @Sendable () -> Void) { self.due = due; self.queue = queue; self.block = block }
        func cancel() { cancelled = true }
    }
    private let lock = NSLock()
    private var t: TimeInterval = 1000
    private var entries: [Entry] = []

    func now() -> TimeInterval { lock.withLock { t } }
    func schedule(after delay: TimeInterval, on queue: DispatchQueue, _ block: @escaping @Sendable () -> Void) -> FeedTimer {
        lock.withLock {
            let e = Entry(due: t + delay, queue: queue, block: block)
            entries.append(e)
            return e
        }
    }
    var pendingTimerCount: Int { lock.withLock { entries.filter { !$0.cancelled }.count } }

    func advance(by seconds: TimeInterval) {
        let target = lock.withLock { t + seconds }
        while true {
            let next: Entry? = lock.withLock {
                entries.removeAll { $0.cancelled }
                guard let e = entries.filter({ $0.due <= target + 1e-9 }).min(by: { $0.due < $1.due }) else { return nil }
                entries.removeAll { $0 === e }
                t = max(t, e.due)
                return e
            }
            guard let e = next else { break }
            e.queue.async(execute: e.block)
            e.queue.sync {}          // 等該回呼（及其排入的後續）跑完
        }
        lock.withLock { t = target }
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [FeedEvent] = []
    func append(_ e: FeedEvent) { lock.withLock { _events.append(e) } }
    var all: [FeedEvent] { lock.withLock { _events } }
    var messages: [Message] { all.compactMap { if case .message(let m) = $0 { return m } else { return nil } } }
    var exitDelays: [TimeInterval] { all.compactMap { if case .exited(_, _, let d) = $0 { return d } else { return nil } } }
    var pids: [Int32] { all.compactMap { if case .started(_, let p) = $0 { return p } else { return nil } } }
    var stuckCount: Int { all.filter { if case .stuck = $0 { return true } else { return false } }.count }
    var startedCount: Int { pids.count }
    var badLines: [DecodeError] { all.compactMap { if case .badLine(let e) = $0 { return e } else { return nil } } }
}

/// 輪詢等待條件（真實時間）；逾時回傳 false。
func waitUntil(timeout: TimeInterval = 10, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if cond() { return true }
        usleep(10_000)
    }
    return cond()
}

/// 暫存目錄與假 helper 腳本。
final class Sandbox {
    let dir: URL
    init() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("feedclient-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    func script(_ name: String, _ body: String, executable: Bool = true) -> URL {
        let url = dir.appendingPathComponent(name)
        try! ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        if executable { chmod(url.path, 0o755) } else { chmod(url.path, 0o644) }
        return url
    }
    var pidFile: URL { dir.appendingPathComponent("helper.pid") }
    var marker: URL { dir.appendingPathComponent("term.marker") }
}

enum Lines {
    static let snapshot = #"{"v":1,"type":"snapshot","items":[{"source":"fastbull","id":"2","published_at_ms":2000,"text":"B"},{"source":"fastbull","id":"1","published_at_ms":1000,"text":"A"}]}"#
    static let items = #"{"v":1,"type":"items","items":[{"source":"fastbull","id":"3","published_at_ms":3000,"text":"C"}]}"#
    static let status = #"{"v":1,"type":"status","source":"fastbull","state":"ok","message":"ok"}"#
}

/// 建立 client（預設：假時鐘、亂數固定 0.5 → jitter 為 0、不用 pid file）。
func makeClient(_ helper: URL, clock: FeedClock, log: EventLog,
                configure: (inout FeedClientConfig) -> Void = { _ in }) -> FeedClient {
    var cfg = FeedClientConfig(helperURL: helper, pidFileURL: nil)
    configure(&cfg)
    return FeedClient(config: cfg, clock: clock, random: { 0.5 }, onEvent: { log.append($0) })
}

func processIsAlive(_ pid: Int32) -> Bool {
    guard kill(pid, 0) == 0 else { return false }
    // 殭屍（已結束但未回收）視為已死
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-o", "stat=", "-p", String(pid)]
    let out = Pipe(); p.standardOutput = out
    try? p.run(); let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    let stat = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !stat.isEmpty && !stat.hasPrefix("Z")
}

/// 結束 client 並讓假時鐘跳過結束逾時，確保不留下忽略 EOF 的測試行程。
func finish(_ c: FeedClient, _ clock: FakeClock) {
    let done = Box()
    c.shutdown { done.eof() }
    usleep(100_000)
    clock.advance(by: 10)
    _ = waitUntil { done.eofCount == 1 }
}
