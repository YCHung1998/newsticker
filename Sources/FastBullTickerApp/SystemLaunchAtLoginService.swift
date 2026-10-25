import Foundation
import ServiceManagement

/// 真實的開機自動啟動服務：`SMAppService.mainApp`（macOS 13+；本專案最低 14）。
/// 這是 `Sources/` 中唯一 import `ServiceManagement` 的檔案（守衛測試 `LaunchAtLoginTests` 掃描確認）。
/// **自動測試從不呼叫 `enable`／`disable`／`openSystemSettings`**（會真的改使用者的登入項目）；`map` 是純函式，可測。
/// 平台行為【假設】：本 App 為 ad-hoc 簽名、無 team ID、通常不在 /Applications，`register()` 可能成功、可能需核准、也可能丟錯；
/// App 被搬移後登入項目會指向舊路徑——一律由 UI 如實呈現，見 design.md 決定 9。
@MainActor
public final class SystemLaunchAtLoginService: LaunchAtLoginService {
    private let app = SMAppService.mainApp
    public init() {}

    public var status: LaunchAtLoginStatus { Self.map(app.status) }
    public func enable() throws { try app.register() }
    public func disable() throws { try app.unregister() }
    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// 系統狀態 → 本專案狀態。未知的新狀態一律視為「未啟用」（不宣稱已啟用）。
    public static func map(_ s: SMAppService.Status) -> LaunchAtLoginStatus {
        switch s {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notRegistered
        }
    }
}
