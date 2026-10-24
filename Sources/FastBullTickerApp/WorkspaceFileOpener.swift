import AppKit

/// 開啟檔案的介面（單方法）。「開啟樣式設定檔…」經它開啟，自動測試只能注入假實作。
@MainActor
public protocol FileOpener: AnyObject {
    /// 回傳 true 代表已交給系統處理（實際開啟是非同步的）。
    func open(_ url: URL) -> Bool
}

/// 唯一新增的真實檔案 opener：以系統預設應用程式開啟（使用者明確動作）。
/// 啟用的是**被開啟的編輯器**，不是本 App（本 App 不呼叫任何啟用 API）。失敗只回報給 `onFailure`（日誌用），不重試。
/// 自動測試絕不呼叫本類別的 `open`。
@MainActor
public final class WorkspaceFileOpener: FileOpener {
    private let onFailure: @Sendable (Error) -> Void

    public init(onFailure: @escaping @Sendable (Error) -> Void) { self.onFailure = onFailure }

    public func open(_ url: URL) -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let failure = onFailure
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error { DispatchQueue.main.async { failure(error) } }
        }
        return true
    }
}
