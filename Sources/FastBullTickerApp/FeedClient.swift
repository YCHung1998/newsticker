import Foundation
import Darwin
import FastBullTickerCore

// MARK: - 公開型別

/// 不可恢復的啟動錯誤：不進入退避迴圈，`FeedClient` 停在 `.failed`。
public enum FeedFatalError: Error, Equatable, Sendable {
    case helperNotFound(path: String)
    case notExecutable(path: String)
    case launchFailed(path: String, reason: String)
}

public enum FeedState: Equatable, Sendable {
    case idle
    case running(generation: Int)
    case backingOff(generation: Int, delay: TimeInterval)
    case failed(FeedFatalError)
    case stopped
}

/// `FeedClient` 對外事件。回呼在 client 內部的序列佇列上呼叫，請勿在回呼內阻塞。
public enum FeedEvent: Equatable, Sendable {
    case message(Message)
    /// 單行解碼失敗：記錄並略過，不終止串流。
    case badLine(DecodeError)
    case oversizeLine(discardedBytes: Int)
    case started(generation: Int, pid: Int32)
    /// helper 非預期結束，將於 `restartIn` 秒後重啟。
    case exited(generation: Int, status: Int32, restartIn: TimeInterval)
    /// 判定卡死，正在終止該 generation。
    case stuck(generation: Int)
    case fatal(FeedFatalError)
    /// 啟動前依 pid file 清掉了上一個 App 遺留的 helper。
    case reclaimedStaleHelper(pid: Int32)
}

public struct FeedClientConfig: Sendable {
    public var helperURL: URL
    public var arguments: [String]
    /// 卡死閾值：暫定 90 秒 = 3 × 心跳（心跳至少每 30 秒）。【假設】
    public var stuckThreshold: TimeInterval
    /// 喚醒寬限：暫定重新起算一個完整卡死閾值。【假設】
    public var wakeGrace: TimeInterval
    /// 結束時關閉 stdin 後等待多久才送 SIGTERM：暫定 2 秒。【假設】
    public var terminateTimeout: TimeInterval
    public var backoff: BackoffPolicy
    /// nil = 不使用 pid file。
    public var pidFileURL: URL?

    public init(helperURL: URL,
                arguments: [String] = [],
                stuckThreshold: TimeInterval = 90,
                wakeGrace: TimeInterval = 90,
                terminateTimeout: TimeInterval = 2,
                backoff: BackoffPolicy = BackoffPolicy(),
                pidFileURL: URL? = PidFile.defaultURL()) {
        self.helperURL = helperURL; self.arguments = arguments
        self.stuckThreshold = stuckThreshold; self.wakeGrace = wakeGrace
        self.terminateTimeout = terminateTimeout; self.backoff = backoff; self.pidFileURL = pidFileURL
    }

    /// 開發用覆寫 helper 路徑的環境變數名稱（2026-10-24 自訂【假設】）。
    public static let helperEnvironmentVariable = "FASTBULL_TICKER_HELPER"
    public static let helperExecutableName = "ticker-connect"

    /// helper 輪詢間隔參數（settings-gear）：預設的 10 秒不帶參數（命令列與加入本設定之前完全相同），其他值為 `--interval-ms N`。
    public static func helperArguments(pollIntervalSeconds: Int) -> [String] {
        pollIntervalSeconds == TickerStyle.default.pollIntervalSeconds ? [] : ["--interval-ms", String(pollIntervalSeconds * 1000)]
    }

    /// 先看環境變數覆寫，再找 bundle 內 `Contents/MacOS/ticker-connect`。
    public static func resolveHelperURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        bundle: Bundle = .main) -> URL? {
        if let override = environment[helperEnvironmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return bundle.url(forAuxiliaryExecutable: helperExecutableName)
    }
}

public struct FeedDiagnostics: Equatable, Sendable {
    public var state: FeedState
    public var generation: Int
    /// 嘗試啟動 helper 的次數（缺檔情境應為 1）。
    public var launchAttempts: Int
    /// 目前 generation 的 stderr 已讀走位元組數。
    public var stderrBytesDrained: Int
    /// 目前 generation 的 stdout readabilityHandler 被呼叫次數。
    public var stdoutHandlerInvocations: Int
}

// MARK: - FeedClient

/// 管理 helper 行程：Process＋Pipe、generation token、退避重啟、卡死判定、喚醒寬限、
/// 不可恢復錯誤、優雅結束、pid file。所有可變狀態只在內部序列佇列上存取。
public final class FeedClient: @unchecked Sendable {
    private var config: FeedClientConfig       // 只有 `arguments` 會在 `reconfigure` 時改變（在 `queue` 上）
    private let clock: FeedClock
    private let random: @Sendable () -> Double
    private let onEvent: @Sendable (FeedEvent) -> Void
    let queue = DispatchQueue(label: "FastBullTicker.FeedClient")
    private let pidFile: PidFile?

    // 以下僅在 `queue` 上存取
    private var state: FeedState = .idle
    private var generation = 0
    private var launchAttempts = 0
    private var backoff = BackoffState()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutReader: PipeReader?
    private var stderrReader: PipeReader?
    private var lineBuffer = LineBuffer()
    private var startedAt: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    private var wakeMark: TimeInterval?
    private var stuckTimer: FeedTimer?
    private var restartTimer: FeedTimer?
    private var killTimer: FeedTimer?
    private var stopping = false
    /// 計畫性重啟（`reconfigure`）進行中：目前這個 generation 結束後立即以新參數啟動，不進退避。
    private var restartPending = false
    private var shutdownCompletions: [@Sendable () -> Void] = []

    public init(config: FeedClientConfig,
                clock: FeedClock = SystemFeedClock(),
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                onEvent: @escaping @Sendable (FeedEvent) -> Void) {
        self.config = config; self.clock = clock; self.random = random; self.onEvent = onEvent
        self.pidFile = config.pidFileURL.map(PidFile.init(url:))
    }

    public func start() {
        queue.async { [self] in
            guard state == .idle, !stopping else { return }
            launch()
        }
    }

    /// 系統喚醒：重新起算寬限期（由 `WakeObserver` 呼叫，測試可直接呼叫）。
    public func noteWake() {
        queue.async { [self] in wakeMark = clock.now() }
    }

    /// 計畫性重啟（settings-gear「poll-interval」）：以新的命令列參數重啟 helper。
    /// - 參數相同＝no-op；`shutdown` 之後忽略；
    /// - 執行中：以與 `shutdown` 相同的優雅方式結束目前 helper（關 stdin → 逾時 SIGTERM → 再逾時 SIGKILL），
    ///   結束後立即以新參數啟動，**不進退避、不改變退避狀態**（計畫性重啟不是崩潰）；重啟進行中再次呼叫只更新參數（合併）；
    /// - 其他狀態（退避等待、尚未啟動、已失敗）：只更新參數，下一次啟動使用新參數。
    public func reconfigure(arguments: [String]) {
        queue.async { [self] in
            guard !stopping, arguments != config.arguments else { return }
            config.arguments = arguments
            guard case .running = state, let p = process, p.isRunning, !restartPending else { return }
            restartPending = true
            stuckTimer?.cancel(); stuckTimer = nil
            try? stdinHandle?.close()
            armTerminationTimers(generation: generation)
        }
    }

    /// 正常結束：關閉 helper 的 stdin；逾時仍未結束則 SIGTERM（再逾時 SIGKILL）。完成後呼叫 `completion`。
    public func shutdown(completion: @escaping @Sendable () -> Void = {}) {
        queue.async { [self] in
            shutdownCompletions.append(completion)
            guard !stopping else { return }
            stopping = true
            restartTimer?.cancel(); restartTimer = nil
            stuckTimer?.cancel(); stuckTimer = nil
            if let p = process, p.isRunning {
                try? stdinHandle?.close()
                armTerminationTimers(generation: generation)
            } else {
                finishShutdown()
            }
        }
    }

    public var diagnostics: FeedDiagnostics {
        queue.sync {
            FeedDiagnostics(state: state, generation: generation, launchAttempts: launchAttempts,
                            stderrBytesDrained: stderrReader?.byteCount ?? 0,
                            stdoutHandlerInvocations: stdoutReader?.invocationCount ?? 0)
        }
    }

    // MARK: 內部（queue 上）

    /// stdin 已關閉後的升級流程：`terminateTimeout` 後 SIGTERM，再逾時 SIGKILL（`shutdown` 與計畫性重啟共用）。
    private func armTerminationTimers(generation gen: Int) {
        killTimer = clock.schedule(after: config.terminateTimeout, on: queue) { [self] in
            guard gen == generation, let p = process, p.isRunning else { return }
            p.terminate()                                      // SIGTERM
            killTimer = clock.schedule(after: config.terminateTimeout, on: queue) { [self] in
                guard gen == generation, let p = process, p.isRunning else { return }
                kill(p.processIdentifier, SIGKILL)             // 最後防線，避免孤兒
            }
        }
    }

    private func finishShutdown() {
        state = .stopped
        let done = shutdownCompletions
        shutdownCompletions = []
        done.forEach { $0() }
    }

    private func launch() {
        restartTimer = nil
        guard !stopping else { return }
        launchAttempts += 1
        let path = config.helperURL.path

        // 不可恢復錯誤：停止，不重啟。
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return fail(.helperNotFound(path: path)) }
        guard fm.isExecutableFile(atPath: path) else { return fail(.notExecutable(path: path)) }

        reclaimStaleHelper()
        stdoutReader?.cancel(); stderrReader?.cancel()

        generation += 1
        let gen = generation
        let p = Process()
        p.executableURL = config.helperURL
        p.arguments = config.arguments
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        lineBuffer = LineBuffer()
        stdoutReader = PipeReader(handle: outPipe.fileHandleForReading,
            onData: { [weak self] d in guard let self else { return }; self.queue.async { self.receive(d, generation: gen) } },
            onEOF: { [weak self] in guard let self else { return }; self.queue.async { self.stdoutEnded(generation: gen) } })
        // stderr 一律讀走並丟棄，避免管線塞滿而阻塞 helper。
        stderrReader = PipeReader(handle: errPipe.fileHandleForReading, onData: { _ in }, onEOF: {})

        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            guard let self else { return }
            self.queue.async { self.terminated(generation: gen, status: status) }
        }
        do {
            try p.run()
        } catch {
            stdoutReader?.cancel(); stderrReader?.cancel()
            return fail(.launchFailed(path: path, reason: "\(error)"))
        }
        // 父行程不需要的管線端點關掉，否則讀端永遠看不到 EOF。
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        try? inPipe.fileHandleForReading.close()

        process = p
        stdinHandle = inPipe.fileHandleForWriting
        startedAt = clock.now(); lastActivity = startedAt
        state = .running(generation: gen)
        pidFile?.write(pid: p.processIdentifier, helper: path)
        onEvent(.started(generation: gen, pid: p.processIdentifier))
        armStuckTimer(generation: gen, after: config.stuckThreshold)
    }

    private func fail(_ error: FeedFatalError) {
        state = .failed(error)
        onEvent(.fatal(error))
    }

    /// 雙實例窗口：pid file 指向仍存活、命令列含 helper 路徑、且父行程不是自己的舊 helper → 先終止再啟動。
    private func reclaimStaleHelper() {
        guard let pidFile, let rec = pidFile.read() else { return }
        defer { pidFile.removeUnconditionally() }
        guard rec.pid != getpid(), ProcessInspector.isAlive(rec.pid),
              let info = ProcessInspector.info(rec.pid),
              info.command.contains(rec.helper), info.ppid != getpid() else { return }
        ProcessInspector.terminate(rec.pid, timeout: config.terminateTimeout)
        onEvent(.reclaimedStaleHelper(pid: rec.pid))
    }

    func receive(_ data: Data, generation gen: Int) {
        guard gen == generation, !stopping else { return }     // generation token：舊世代事件一律忽略
        lastActivity = clock.now()                              // 任何 stdout 位元組（含半行）都算活著
        for event in lineBuffer.feed([UInt8](data)) {
            switch event {
            case .line(let bytes):
                switch decodeLine(bytes) {
                case .success(let m): onEvent(.message(m))
                case .failure(let e): onEvent(.badLine(e))
                }
            case .oversize(let n):
                onEvent(.oversizeLine(discardedBytes: n))
            }
        }
    }

    private func stdoutEnded(generation gen: Int) {
        guard gen == generation else { return }
        _ = lineBuffer.finish()      // 殘留半行丟棄
    }

    func terminated(generation gen: Int, status: Int32) {
        guard gen == generation else { return }   // 舊世代的終止事件：不改狀態、不觸發額外重啟
        stuckTimer?.cancel(); stuckTimer = nil
        killTimer?.cancel(); killTimer = nil
        if let p = process { pidFile?.remove(ifPid: p.processIdentifier) }
        process = nil
        try? stdinHandle?.close(); stdinHandle = nil
        if stopping { return finishShutdown() }
        if restartPending {                        // 計畫性重啟：不進退避、不碰退避狀態
            restartPending = false
            onEvent(.exited(generation: gen, status: status, restartIn: 0))
            return launch()
        }

        backoff.processEnded(ranFor: clock.now() - startedAt, policy: config.backoff)
        let delay = backoff.nextDelay(policy: config.backoff, randomUnit: random())
        state = .backingOff(generation: gen, delay: delay)
        onEvent(.exited(generation: gen, status: status, restartIn: delay))
        restartTimer = clock.schedule(after: delay, on: queue) { [self] in
            guard case .backingOff(let g, _) = state, g == gen else { return }
            launch()
        }
    }

    // MARK: 卡死判定

    private func armStuckTimer(generation gen: Int, after delay: TimeInterval) {
        stuckTimer?.cancel()
        stuckTimer = clock.schedule(after: delay, on: queue) { [self] in checkStuck(generation: gen) }
    }

    private func checkStuck(generation gen: Int) {
        guard gen == generation, case .running = state, !stopping else { return }
        var deadline = lastActivity + config.stuckThreshold
        if let wakeMark { deadline = max(deadline, wakeMark + config.wakeGrace) }
        let now = clock.now()
        if now + 1e-9 < deadline {
            return armStuckTimer(generation: gen, after: deadline - now)
        }
        stuckTimer = nil
        onEvent(.stuck(generation: gen))
        guard let p = process, p.isRunning else { return }
        p.terminate()
        killTimer = clock.schedule(after: config.terminateTimeout, on: queue) { [self] in
            guard gen == generation, let p = process, p.isRunning else { return }
            kill(p.processIdentifier, SIGKILL)
        }
    }
}
