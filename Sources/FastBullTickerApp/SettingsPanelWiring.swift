import Foundation

/// 設定面板的組裝（settings-gear task 10）：`AppDelegate` 與 headless 煙霧測試共用同一段，確保路徑相同。
/// 樣式動作走 `StyleActionRunner.run`（與選單同一條）；齒輪的 `onGear` 切換面板；跑馬燈上非齒輪的按下關閉面板；
/// 開機啟動只經 `LaunchAtLoginController`。視窗與監看器由呼叫端注入（正式為 `SettingsPanel`／`GlobalMouseDownMonitor`，測試為假實作）。
@MainActor
public struct SettingsPanelWiring {
    public let controller: SettingsPanelController
    public let coordinator: SettingsPanelCoordinator

    /// 樣式被套用之後呼叫（面板開著才重新整理）；接到 `StyleWiring.connect(onApplied:)`。
    public var refreshIfOpen: @MainActor () -> Void {
        { [controller, coordinator] in if coordinator.isOpen { controller.refresh() } }
    }

    public static func assemble(content: SettingsPanelContentView, window: SettingsPanelWindowing, monitor: MouseDownMonitoring,
                                launch: LaunchAtLoginService, store: StyleStore, runner: StyleActionRunner, view: TickerView,
                                tickerFrame: @escaping () -> CGRect, visibleFrame: @escaping () -> CGRect) -> SettingsPanelWiring {
        let controller = SettingsPanelController(content: content, launch: LaunchAtLoginController(service: launch))
        controller.source = { [weak store] in (store?.style ?? .default, store?.hasConfigProblem ?? false) }
        controller.onStyleAction = { [weak runner] in runner?.run($0) }
        let coordinator = SettingsPanelCoordinator(window: window, monitor: monitor)
        coordinator.tickerFrame = tickerFrame
        coordinator.visibleFrame = visibleFrame
        coordinator.onWillOpen = { [weak controller] in controller?.willOpen() }
        controller.onClose = { [weak coordinator] in coordinator?.close() }
        content.onSizeChange = { [weak coordinator] in coordinator?.contentSizeChanged() }
        view.router.onGear = { [weak coordinator] in coordinator?.toggle() }
        view.onTickerPointerDown = { [weak coordinator] onGear in coordinator?.tickerPointerDown(onGear: onGear) }
        return SettingsPanelWiring(controller: controller, coordinator: coordinator)
    }
}
