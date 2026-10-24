import AppKit

/// 唯一的真實 opener：以預設瀏覽器開啟網址。只收 `OpenableURL`（未經 `LinkPolicy` 驗證者無法構造）。
/// - 不啟用本 App（`NSWorkspace.OpenConfiguration.activates` 是讓**瀏覽器**成為前景【假設：使用者要閱讀】）。
/// - 失敗不重試；失敗原因只透過 `onFailure` 回報（日誌用）。
/// 自動測試絕不呼叫本類別的 `open`。
@MainActor
public final class WorkspaceURLOpener: URLOpener {
    public static let opensWithActivation = true
    private let onFailure: @Sendable (Error) -> Void

    public init(onFailure: @escaping @Sendable (Error) -> Void) { self.onFailure = onFailure }

    /// 回傳 true 代表已交給系統處理（實際開啟是非同步的）；失敗時 `onFailure` 會被呼叫，不重試。
    public func open(_ url: OpenableURL) -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = Self.opensWithActivation
        let failure = onFailure
        NSWorkspace.shared.open(url.url, configuration: config) { _, error in
            if let error { DispatchQueue.main.async { failure(error) } }
        }
        return true
    }
}
