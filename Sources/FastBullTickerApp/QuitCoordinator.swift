import Foundation

/// 統一的結束流程（change quit-controls）：帶子上的 ✕、設定面板的「結束程式」、選單列／右鍵選單的「結束」都呼叫 `request`。
/// 先收起設定面板與帶子（畫面立刻消失，不會在 helper 收尾的最多約 6 秒內停在畫面上像當掉），再 `terminate`
/// （App 端是 `NSApp.terminate`，接著由 `applicationShouldTerminate` 優雅關閉 helper）。可重入：只會結束一次。
/// 副作用都經注入的閉包，所以可完整單元測試；不啟用本 App。
@MainActor
public final class QuitCoordinator {
    private let hideTicker: () -> Void
    private let hideSettings: () -> Void
    private let terminate: () -> Void
    private let log: AppLog?
    public private(set) var isQuitting = false

    public init(hideTicker: @escaping () -> Void, hideSettings: @escaping () -> Void, terminate: @escaping () -> Void, log: AppLog?) {
        self.hideTicker = hideTicker; self.hideSettings = hideSettings; self.terminate = terminate; self.log = log
    }

    /// `entry`：哪個入口要求結束（日誌用）。
    public func request(from entry: String) {
        guard !isQuitting else {
            log?.write("quit: already quitting, ignored request from \(entry)")
            return
        }
        isQuitting = true
        log?.write("quit: requested from \(entry)")
        hideSettings()
        hideTicker()
        terminate()
    }
}
