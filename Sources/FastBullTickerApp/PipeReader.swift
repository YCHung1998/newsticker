import Foundation

/// 包裝 `readabilityHandler`：收到空資料（EOF）時**立即清除 handler 並關閉 fd**，避免 busy loop。
/// `invocationCount` 供測試斷言「EOF 後不再被呼叫」。
final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var _invocations = 0
    private var _bytes = 0
    private var _finished = false

    var invocationCount: Int { lock.withLock { _invocations } }
    var byteCount: Int { lock.withLock { _bytes } }
    var isFinished: Bool { lock.withLock { _finished } }
    /// handler 是否已被清除（測試用）。
    var handlerCleared: Bool { handle.readabilityHandler == nil }

    /// - Parameters:
    ///   - onData: 在背景執行緒呼叫，非空。
    ///   - onEOF: 在背景執行緒呼叫，僅一次。
    init(handle: FileHandle, onData: @escaping @Sendable (Data) -> Void, onEOF: @escaping @Sendable () -> Void) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] h in
            guard let self else { h.readabilityHandler = nil; return }
            let data = h.availableData
            self.lock.lock()
            self._invocations += 1
            self._bytes += data.count
            let alreadyFinished = self._finished
            if data.isEmpty { self._finished = true }
            self.lock.unlock()
            if data.isEmpty {
                h.readabilityHandler = nil          // 關鍵：不清除會對 EOF 空轉
                try? h.close()
                if !alreadyFinished { onEOF() }
            } else {
                onData(data)
            }
        }
    }

    /// 主動停止（行程結束後清理）。
    func cancel() {
        handle.readabilityHandler = nil
        lock.lock(); _finished = true; lock.unlock()
    }
}
