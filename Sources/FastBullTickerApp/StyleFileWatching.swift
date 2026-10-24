import Foundation

/// 樣式檔所在目錄的變動監看（可注入）。監看目錄而非單一檔案描述元：多數編輯器以「寫暫存檔再改名取代」儲存，
/// 對原檔案的監看會在第一次儲存後失效。`onChange` 可能在任意執行緒呼叫；去抖與讀檔由 `StyleStore` 負責。
public protocol StyleFileWatching: AnyObject {
    /// 開始監看 `directory`。成功回傳 true；目錄不存在或無法開啟回傳 false（呼叫端記錄日誌）。重複呼叫等同先 `stop()`。
    @discardableResult
    func start(directory: URL, onChange: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

/// 正式實作：`DispatchSource` 檔案系統事件（`O_EVTONLY`，不需任何權限）。
/// 實際行為（TextEdit、vim 等編輯器的儲存方式）為【需人工】驗證；退路是輪詢 `mtime`（design.md 決定 3）。
public final class DispatchSourceStyleWatcher: StyleFileWatching, @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?

    public init(queue: DispatchQueue = DispatchQueue(label: "FastBullTicker.style-watcher")) { self.queue = queue }
    deinit { stop() }

    @discardableResult
    public func start(directory: URL, onChange: @escaping @Sendable () -> Void) -> Bool {
        stop()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib, .link, .revoke], queue: queue)
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { close(fd) }
        lock.withLock { source = src }
        src.resume()
        return true
    }

    public func stop() {
        let s = lock.withLock { () -> DispatchSourceFileSystemObject? in let s = source; source = nil; return s }
        s?.cancel()
    }
}
