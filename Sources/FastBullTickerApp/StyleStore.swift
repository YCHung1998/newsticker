import Foundation

// ticker-style-settings 3.1：樣式檔的載入、熱重載與寫回。
// 時間（debounce）經 `FeedClock`、監看經 `StyleFileWatching`、檔案系統經 `StyleFileSystem` 注入，
// 因此自動測試只用暫存目錄＋假物件，不依賴真實檔案事件時序，也不會碰使用者真實的 style.json。

// MARK: 檔案系統（可注入）

public protocol StyleFileSystem: Sendable {
    /// 讀最多 `limit + 1` 位元組（超過 `limit` 即可判定過大，不必讀完整檔案）。檔案不存在回傳 nil，其他錯誤丟出。
    func read(_ url: URL, limit: Int) throws -> Data?
    func createDirectory(_ url: URL) throws
    /// 在 `url` 同目錄寫入暫存檔並回傳其路徑。
    func writeTemporary(_ data: Data, besides url: URL) throws -> URL
    /// 以 `temp` 原子取代 `url`（`url` 不存在則改名）。
    func replace(_ url: URL, with temp: URL) throws
    /// 複製為 `dst`（覆蓋既有）。
    func copy(_ src: URL, to dst: URL) throws
    func remove(_ url: URL)
}

public struct DiskStyleFileSystem: StyleFileSystem {
    public init() {}
    public func read(_ url: URL, limit: Int) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        return try h.read(upToCount: limit + 1) ?? Data()
    }
    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    public func writeTemporary(_ data: Data, besides url: URL) throws -> URL {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: [])
        return tmp
    }
    public func replace(_ url: URL, with temp: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
    public func copy(_ src: URL, to dst: URL) throws {
        if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
        try FileManager.default.copyItem(at: src, to: dst)
    }
    public func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

// MARK: Store

public enum StyleChangeSource: Equatable, Sendable {
    /// 啟動載入不通知（呼叫端直接讀 `style`）；熱重載讀到新內容。
    case file
    /// 選單（`update`／`resetToDefault`）修改。
    case menu
}

/// 目前生效的樣式與其持久化。執行緒安全（內部鎖）；`onChange` 於以下執行緒呼叫：
/// 熱重載＝`queue`（正式為主執行緒）、`update`／`resetToDefault`＝呼叫端執行緒（選單操作，主執行緒）。
public final class StyleStore: @unchecked Sendable {
    public static let environmentKey = "FASTBULL_TICKER_STYLE"
    public static let reloadDebounce: TimeInterval = 0.3        // 【假設】
    public static let writeDebounce: TimeInterval = 0.5         // 【假設】與位置存檔一致

    /// 路徑決定：環境變數 `FASTBULL_TICKER_STYLE`（完整檔案路徑）優先，否則 `~/Library/Application Support/FastBullTicker/style.json`。
    public static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                      home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let p = environment[environmentKey], !p.isEmpty { return URL(fileURLWithPath: p) }
        return home.appendingPathComponent("Library/Application Support/FastBullTicker/style.json")
    }

    public let fileURL: URL
    public var backupURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent(fileURL.lastPathComponent + ".bak") }

    private let watcher: StyleFileWatching
    private let clock: FeedClock
    private let queue: DispatchQueue
    private let fs: StyleFileSystem
    private let log: AppLog?

    private let lock = NSLock()      // 保護下列狀態
    private let ioLock = NSLock()    // 序列化所有檔案 I/O（外層；先 ioLock 再 lock）
    private var _style = TickerStyle.default
    private var _configProblem: StyleLoadError?
    private var _lastBytes: Data?
    private var _reloadTimer: FeedTimer?
    private var _writeTimer: FeedTimer?
    private var _writePending = false
    private var _parseCount = 0
    private var _writeCount = 0
    private var _lastWriteError: String?
    private var _lastWarnings: [StyleWarning] = []
    private var _onChange: ((TickerStyle, StyleChangeSource) -> Void)?

    /// 目前生效的樣式（永遠合法）。
    public var style: TickerStyle { lock.withLock { _style } }
    /// 「設定檔有誤」狀態：最近一次讀檔整份無法解讀時非 nil，下一次成功載入（或檔案被刪除、或成功寫回）時清除。
    public var configProblem: StyleLoadError? { lock.withLock { _configProblem } }
    public var hasConfigProblem: Bool { configProblem != nil }
    /// 最近一次載入的欄位層級警告。
    public var lastWarnings: [StyleWarning] { lock.withLock { _lastWarnings } }
    /// 診斷計數：解析次數（位元組相同而略過者不計）、實際寫檔次數、最近一次寫入失敗原因。
    public var parseCount: Int { lock.withLock { _parseCount } }
    public var writeCount: Int { lock.withLock { _writeCount } }
    public var lastWriteError: String? { lock.withLock { _lastWriteError } }
    public var hasPendingWrite: Bool { lock.withLock { _writePending } }
    /// 套用端回呼（主執行緒由呼叫端保證：正式 `queue` 為 `.main`）。
    public var onChange: ((TickerStyle, StyleChangeSource) -> Void)? {
        get { lock.withLock { _onChange } }
        set { lock.withLock { _onChange = newValue } }
    }

    public init(fileURL: URL, watcher: StyleFileWatching, clock: FeedClock = SystemFeedClock(), queue: DispatchQueue = .main,
                fileSystem: StyleFileSystem = DiskStyleFileSystem(), log: AppLog? = nil) {
        self.fileURL = fileURL; self.watcher = watcher; self.clock = clock; self.queue = queue; self.fs = fileSystem; self.log = log
    }

    deinit { watcher.stop() }

    // MARK: 啟動

    /// 啟動載入＋開始監看。檔案不存在 → 預設且**不建立檔案**；無法解讀 → 預設、記錄錯誤、設「設定檔有誤」，不修改該檔案。
    public func start() {
        load()
        startWatching()
    }

    public func load() {
        ioLock.withLock {
            let (data, readError) = readFile()
            lock.withLock { _lastBytes = data }
            if let readError {
                lock.withLock { _style = .default; _configProblem = .notJSON(readError) }
                write("style: error 無法讀取樣式檔：\(readError)；使用預設樣式")
                return
            }
            guard let data else {
                lock.withLock { _style = .default; _configProblem = nil; _lastWarnings = [] }
                write("style: 無樣式檔，使用預設樣式（不自動建立）")
                return
            }
            lock.withLock { _parseCount += 1 }
            switch StyleParser.parse(data) {
            case .success(let r):
                lock.withLock { _style = r.style; _configProblem = nil; _lastWarnings = r.warnings }
                logWarnings(r.warnings)
                write("style: 已載入樣式檔")
            case .failure(let e):
                lock.withLock { _style = .default; _configProblem = e; _lastWarnings = [] }
                write("style: error 樣式檔無法解讀：\(e)；使用預設樣式，檔案保持不變")
            }
        }
    }

    public func startWatching() {
        let dir = fileURL.deletingLastPathComponent()
        let ok = watcher.start(directory: dir) { [weak self] in self?.directoryChanged() }
        if !ok { write("style: error 無法監看目錄 \(dir.path)，熱重載停用") }
    }

    public func stopWatching() {
        watcher.stop()
        lock.withLock { _reloadTimer?.cancel(); _reloadTimer = nil }
    }

    // MARK: 熱重載

    private func directoryChanged() {
        lock.lock(); defer { lock.unlock() }
        _reloadTimer?.cancel()
        _reloadTimer = clock.schedule(after: Self.reloadDebounce, on: queue) { [weak self] in self?.reload() }
    }

    /// debounce 後執行。位元組與上次相同（含自寫入）不解析；樣式與生效樣式相等不通知；整份失敗保留舊值。
    func reload() {
        lock.withLock { _reloadTimer = nil }
        var notify: TickerStyle?
        ioLock.withLock {
            let (data, readError) = readFile()
            if let readError { write("style: error 熱重載讀檔失敗：\(readError)；保留目前樣式"); return }
            guard let data else {
                let had = lock.withLock { () -> Bool in let h = _lastBytes != nil; _lastBytes = nil; _configProblem = nil; return h }
                if had { write("style: 樣式檔已被刪除；保留目前生效樣式（要回到預設請用「重設為預設」）") }
                return
            }
            if lock.withLock({ data == _lastBytes }) { return }               // 內容相同（含自寫入）
            lock.withLock { _lastBytes = data; _parseCount += 1 }
            switch StyleParser.parse(data) {
            case .failure(let e):
                lock.withLock { _configProblem = e }
                write("style: error 樣式檔無法解讀：\(e)；保留目前樣式")
            case .success(let r):
                logWarnings(r.warnings)
                lock.withLock {
                    _configProblem = nil; _lastWarnings = r.warnings
                    if r.style != _style {
                        _style = r.style; notify = r.style
                        _writeTimer?.cancel(); _writeTimer = nil; _writePending = false      // 檔案較新：丟棄尚未寫出的選單變更
                    }
                }
                write(notify != nil ? "style: 熱重載已套用" : "style: 熱重載：樣式未變，不重套")
            }
        }
        if let s = notify, let cb = onChange { cb(s, .file) }
    }

    // MARK: 選單修改與寫回

    /// 修改生效樣式（結果夾進合法範圍）：立即套用並通知，再 debounce 合併後原子寫回。無變化則什麼都不做。
    public func update(_ mutate: (inout TickerStyle) -> Void) {
        var s = style
        mutate(&s)
        apply(s.clamped())
    }

    /// 重設為預設：先把現有檔案備份為 `.bak`（無確認對話框，`.bak` 就是復原手段），再套用預設並寫回。
    public func resetToDefault() {
        ioLock.withLock { backupExistingFile() }
        apply(.default, forceWrite: true)
    }

    /// 取得 `ensureFileExists` 的內容用於「開啟樣式設定檔…」：檔案不存在時以目前樣式建立（同步寫入）。
    @discardableResult
    public func ensureFileExists() -> Bool {
        let exists = ioLock.withLock { ((try? fs.read(fileURL, limit: 1)) ?? nil) != nil }
        if exists { return true }
        return flushWrite(force: true)
    }

    private func apply(_ new: TickerStyle, forceWrite: Bool = false) {
        let changed: Bool = lock.withLock {
            guard new != _style else { return false }
            _style = new
            return true
        }
        guard changed || forceWrite else { return }
        if changed, let cb = onChange { cb(new, .menu) }
        lock.withLock {
            _writePending = true
            _writeTimer?.cancel()
            _writeTimer = clock.schedule(after: Self.writeDebounce, on: queue) { [weak self] in _ = self?.flushWrite() }
        }
    }

    /// 立即寫出（測試與結束時可呼叫）；取消待寫的計時器。回傳是否成功。
    @discardableResult
    public func flushWrite(force: Bool = false) -> Bool {
        let pending: Bool = lock.withLock {
            _writeTimer?.cancel(); _writeTimer = nil
            let p = _writePending; _writePending = false
            return p
        }
        guard pending || force else { return true }
        return ioLock.withLock { performWrite() }
    }

    private func performWrite() -> Bool {
        let style = lock.withLock { _style }
        let data = style.normalizedJSON()
        do {
            try fs.createDirectory(fileURL.deletingLastPathComponent())
            // 備份：磁碟上現有內容無法解讀、含未知鍵、或有欄位會被改寫（夾制／型別錯誤／非法色碼）時，先留一份（避免毀掉手寫中的內容）。
            if let onDisk = try fs.read(fileURL, limit: StyleRanges.maxFileBytes), onDisk != data {
                if needsBackup(onDisk) {
                    try fs.copy(fileURL, to: backupURL)
                    write("style: 已備份原檔為 \(backupURL.lastPathComponent)")
                }
            }
            let tmp = try fs.writeTemporary(data, besides: fileURL)
            do { try fs.replace(fileURL, with: tmp) } catch { fs.remove(tmp); throw error }
            lock.withLock { _lastBytes = data; _configProblem = nil; _writeCount += 1; _lastWriteError = nil }   // 之後的目錄事件讀到相同內容即為自寫入
            write("style: 已寫回樣式檔")
            return true
        } catch {
            lock.withLock { _lastWriteError = String(describing: error) }
            write("style: error 寫入失敗：\(error)；保留記憶體中的樣式")
            return false
        }
    }

    private func needsBackup(_ onDisk: Data) -> Bool {
        switch StyleParser.parse(onDisk) {
        case .failure: return true
        case .success(let r): return r.warnings.contains { $0.kind != .lowContrast }
        }
    }

    private func backupExistingFile() {
        guard let onDisk = (try? fs.read(fileURL, limit: StyleRanges.maxFileBytes)) ?? nil, !onDisk.isEmpty else { return }
        do { try fs.copy(fileURL, to: backupURL); write("style: 重設前已備份原檔為 \(backupURL.lastPathComponent)") }
        catch { write("style: error 備份失敗：\(error)") }
    }

    // MARK: 工具

    /// (內容, 讀取錯誤)：不存在 → (nil, nil)。
    private func readFile() -> (Data?, String?) {
        do { return (try fs.read(fileURL, limit: StyleRanges.maxFileBytes), nil) }
        catch { return (nil, String(describing: error)) }
    }

    private func logWarnings(_ ws: [StyleWarning]) { for w in ws { write("style: warning \(w)") } }
    private func write(_ m: String) { log?.write(m) }
}
