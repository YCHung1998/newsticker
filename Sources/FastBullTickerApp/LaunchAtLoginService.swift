import Foundation

// settings-gear task 6：開機自動啟動（`launch-at-login`）。純 Foundation：協定、狀態、可測的控制器。
// 真實實作（唯一碰系統登入項目 API 的檔案）見 `SystemLaunchAtLoginService.swift`；自動測試一律使用假服務，不得真的註冊。
// 開機自動啟動屬系統狀態，不寫入 `style.json`。

/// 登入項目的實際狀態（對應系統回報的四種狀態）。
public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    /// 已註冊但需要使用者到「系統設定 → 一般 → 登入項目」核准。
    case requiresApproval
    /// 系統找不到可註冊的 App（例如不是從 .app 執行）。
    case notFound
}

/// 可注入的開機自動啟動服務。
@MainActor
public protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func enable() throws
    func disable() throws
    /// 開啟系統設定的登入項目頁（需核准時用）。
    func openSystemSettings()
}

/// UI 顯示用的狀態（開關位置、說明文字、是否提供「開啟系統設定」）。
public struct LaunchAtLoginViewState: Equatable, Sendable {
    public var isOn: Bool
    public var detail: String
    public var offersOpenSettings: Bool
    public var isError: Bool
    public init(isOn: Bool, detail: String, offersOpenSettings: Bool, isError: Bool) {
        self.isOn = isOn; self.detail = detail; self.offersOpenSettings = offersOpenSettings; self.isError = isError
    }
}

/// 把服務結果轉成 UI 狀態。**開關位置一律以操作後重新讀取的 `status` 為準**（不是使用者按了什麼），
/// 錯誤如實顯示（「失敗：訊息」），不吞掉、不崩潰。ad-hoc 簽名 App 的註冊結果屬平台行為【假設】：可能成功、需核准或失敗。
@MainActor
public final class LaunchAtLoginController {
    private let service: LaunchAtLoginService
    private var lastError: String?
    public private(set) var viewState: LaunchAtLoginViewState

    public init(service: LaunchAtLoginService) {
        self.service = service
        self.viewState = Self.makeState(status: service.status, error: nil)
    }

    /// 重新讀取實際狀態（例如面板開啟時；使用者可能已在系統設定中改過）。舊的錯誤訊息一併清除。
    public func refresh() {
        lastError = nil
        viewState = Self.makeState(status: service.status, error: nil)
    }

    /// 使用者要求開／關。狀態本來就符合時不呼叫服務。
    public func setEnabled(_ on: Bool) {
        lastError = nil
        do {
            if on {
                if service.status != .enabled { try service.enable() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.disable()
            }
        } catch {
            lastError = (error as NSError).localizedDescription
        }
        viewState = Self.makeState(status: service.status, error: lastError)
    }

    public func openSystemSettings() { service.openSystemSettings() }

    static func makeState(status: LaunchAtLoginStatus, error: String?) -> LaunchAtLoginViewState {
        let isOn = status == .enabled                       // 開關位置只由實際狀態決定
        let offers = status == .requiresApproval
        let detail: String
        switch status {
        case .enabled: detail = "已啟用"
        case .notRegistered: detail = "未啟用"
        case .requiresApproval: detail = "需要在「系統設定 → 一般 → 登入項目」核准"
        case .notFound: detail = "找不到可註冊的 App（請從 .app 執行）"
        }
        if let error { return LaunchAtLoginViewState(isOn: isOn, detail: "失敗：\(error)", offersOpenSettings: offers, isError: true) }
        return LaunchAtLoginViewState(isOn: isOn, detail: detail, offersOpenSettings: offers, isError: false)
    }
}
