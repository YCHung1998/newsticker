import Testing
import Foundation
@testable import FastBullTickerApp

// settings-gear task 6：開機自動啟動服務。執行：swift test --filter LaunchAtLogin
// 全部使用假服務；**不得真的註冊登入項目**（守衛測試掃描原始碼確認）。真實註冊結果屬人工驗收。
// 注意：此檔不得出現系統登入項目 API 的型別名稱字串（守衛會掃描 Tests/）；下方以字串拼接組出要掃描的名稱。

private struct FakeError: LocalizedError { let text: String; var errorDescription: String? { text } }

@MainActor
private final class FakeLaunchService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    /// `enable()` 成功後的狀態（模擬 ad-hoc 簽名 App 的三種平台結果）。
    var statusAfterEnable: LaunchAtLoginStatus = .enabled
    var enableError: Error?
    var disableError: Error?
    private(set) var enableCalls = 0, disableCalls = 0, openSettingsCalls = 0
    init(_ status: LaunchAtLoginStatus = .notRegistered) { self.status = status }
    func enable() throws {
        enableCalls += 1
        if let e = enableError { throw e }
        status = statusAfterEnable
    }
    func disable() throws {
        disableCalls += 1
        if let e = disableError { throw e }
        status = .notRegistered
    }
    func openSystemSettings() { openSettingsCalls += 1 }
}

@MainActor
@Suite struct LaunchAtLoginTests {
    @Test func enableSucceedsAndShowsEnabled() {
        let s = FakeLaunchService()
        let c = LaunchAtLoginController(service: s)
        #expect(c.viewState == LaunchAtLoginViewState(isOn: false, detail: "未啟用", offersOpenSettings: false, isError: false))
        c.setEnabled(true)
        #expect(s.enableCalls == 1)
        #expect(c.viewState == LaunchAtLoginViewState(isOn: true, detail: "已啟用", offersOpenSettings: false, isError: false))
    }

    @Test func requiresApprovalIsShownHonestlyAndOffersSystemSettings() {
        let s = FakeLaunchService(); s.statusAfterEnable = .requiresApproval
        let c = LaunchAtLoginController(service: s)
        c.setEnabled(true)
        #expect(!c.viewState.isOn, "開關位置以重新讀取的 status 為準：需核准時不是「已啟用」")
        #expect(c.viewState.detail.contains("系統設定 → 一般 → 登入項目") && c.viewState.offersOpenSettings && !c.viewState.isError)
        c.openSystemSettings()
        #expect(s.openSettingsCalls == 1)
    }

    @Test func registrationFailureShowsTheMessageAndKeepsTheRealStatus() {
        let s = FakeLaunchService(); s.enableError = FakeError(text: "Operation not permitted")
        let c = LaunchAtLoginController(service: s)
        c.setEnabled(true)
        #expect(c.viewState.detail == "失敗：Operation not permitted" && c.viewState.isError)
        #expect(!c.viewState.isOn && s.status == .notRegistered, "失敗後開關仍是關")
    }

    @Test func failedDisableKeepsTheSwitchOnBecauseTheServiceStillSaysEnabled() {
        let s = FakeLaunchService(.enabled); s.disableError = FakeError(text: "boom")
        let c = LaunchAtLoginController(service: s)
        #expect(c.viewState.isOn)
        c.setEnabled(false)
        #expect(c.viewState.isOn && c.viewState.detail == "失敗：boom" && c.viewState.isError)
    }

    @Test func disableFromEnabled() {
        let s = FakeLaunchService(.enabled)
        let c = LaunchAtLoginController(service: s)
        c.setEnabled(false)
        #expect(s.disableCalls == 1 && c.viewState == LaunchAtLoginViewState(isOn: false, detail: "未啟用", offersOpenSettings: false, isError: false))
    }

    @Test func refreshRereadsTheServiceAndClearsAnOldError() {
        let s = FakeLaunchService(); s.enableError = FakeError(text: "x")
        let c = LaunchAtLoginController(service: s)
        c.setEnabled(true)
        #expect(c.viewState.isError)
        s.status = .enabled                                   // 使用者在系統設定中自己開了
        c.refresh()
        #expect(c.viewState == LaunchAtLoginViewState(isOn: true, detail: "已啟用", offersOpenSettings: false, isError: false))
        s.status = .notRegistered                             // 又自己關掉
        c.refresh()
        #expect(!c.viewState.isOn && c.viewState.detail == "未啟用")
    }

    @Test func notFoundIsShown() {
        let c = LaunchAtLoginController(service: FakeLaunchService(.notFound))
        #expect(!c.viewState.isOn && c.viewState.detail.contains("找不到") && !c.viewState.offersOpenSettings)
    }

    @Test func requestsThatChangeNothingDoNotCallTheService() {
        let on = FakeLaunchService(.enabled)
        LaunchAtLoginController(service: on).setEnabled(true)
        #expect(on.enableCalls == 0, "已啟用就不再註冊")
        let off = FakeLaunchService(.notRegistered)
        LaunchAtLoginController(service: off).setEnabled(false)
        #expect(off.disableCalls == 0)
    }

    @Test func turningOffWhileApprovalIsPendingUnregisters() {
        let s = FakeLaunchService(.requiresApproval)
        let c = LaunchAtLoginController(service: s)
        c.setEnabled(false)
        #expect(s.disableCalls == 1 && c.viewState.detail == "未啟用")
    }

    // MARK: 真實實作的純函式與守衛

    @Test func platformStatusMapping() {
        #expect(SystemLaunchAtLoginService.map(.enabled) == .enabled)
        #expect(SystemLaunchAtLoginService.map(.notRegistered) == .notRegistered)
        #expect(SystemLaunchAtLoginService.map(.requiresApproval) == .requiresApproval)
        #expect(SystemLaunchAtLoginService.map(.notFound) == .notFound)
    }

    @Test func launchAtLoginIsNotAStyleKey() {
        #expect(!TickerStyle.keys.contains { $0.lowercased().contains("login") || $0.lowercased().contains("launch") })
    }

    @Test func onlyTheSystemServiceFileMentionsThePlatformAPIAndTestsNeverDo() throws {
        let name = "SM" + "AppService"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func swiftFiles(_ sub: String) -> [URL] {
            let e = FileManager.default.enumerator(at: root.appendingPathComponent(sub), includingPropertiesForKeys: nil)
            return (e?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
        var inSources: [String] = []
        for f in swiftFiles("Sources") where try String(contentsOf: f, encoding: .utf8).contains(name) { inSources.append(f.lastPathComponent) }
        #expect(inSources == ["SystemLaunchAtLoginService.swift"], "Sources 中提到平台 API 的檔案：\(inSources)")
        var inTests: [String] = []
        for f in swiftFiles("Tests") where try String(contentsOf: f, encoding: .utf8).contains(name) { inTests.append(f.lastPathComponent) }
        #expect(inTests.isEmpty, "Tests 中不得出現：\(inTests)")
        // 只有該檔 import ServiceManagement
        var importers: [String] = []
        for f in swiftFiles("Sources") where try String(contentsOf: f, encoding: .utf8).contains("import ServiceManagement") { importers.append(f.lastPathComponent) }
        #expect(importers == ["SystemLaunchAtLoginService.swift"])
    }
}
