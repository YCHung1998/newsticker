import Foundation

/// 把設定面板的內容視圖、樣式來源與開機啟動控制器接起來（settings-gear task 8）。不碰視窗。
/// 樣式動作原樣交給 `onStyleAction`（App 接到 `StyleActionRunner.run`，與選單同一條路徑）；開機啟動只經 `LaunchAtLoginController`，不經 `StyleStore`。
@MainActor
public final class SettingsPanelController {
    public let content: SettingsPanelContentView
    public let launch: LaunchAtLoginController
    /// 目前生效的樣式與「設定檔有誤」狀態。
    public var source: () -> (style: TickerStyle, hasConfigProblem: Bool) = { (.default, false) }
    public var onStyleAction: (StyleMenuAction) -> Void = { _ in }
    public var onClose: () -> Void = {}

    public init(content: SettingsPanelContentView, launch: LaunchAtLoginController) {
        self.content = content; self.launch = launch
        content.onCommand = { [weak self] in self?.handle($0) }
    }

    /// 依目前樣式與開機啟動狀態重新整理全部控制項（就地更新）。
    public func refresh() {
        let s = source()
        content.reload(SettingsPanelModel.items(style: s.style, hasConfigProblem: s.hasConfigProblem, launch: launch.viewState))
    }

    /// 面板開啟前：重新讀取開機啟動的實際狀態（使用者可能已在系統設定改過），再整理控制項。
    public func willOpen() {
        launch.refresh()
        refresh()
    }

    public func handle(_ command: SettingsPanelModel.Command) {
        switch command {
        case .style(let action):
            onStyleAction(action)
            refresh()                                   // 夾制或無變化時，控制項也回到實際值
        case .setLaunchAtLogin(let on):
            launch.setEnabled(on)
            refresh()
        case .openLoginSettings:
            launch.openSystemSettings()
        case .close:
            onClose()
        }
    }
}
