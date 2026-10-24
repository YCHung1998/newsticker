## MODIFIED Requirements

### Requirement: 切換操作不啟用 App、不搶鍵盤焦點
點擊 `<`／`>`、拖曳、滑鼠進出面板 MUST NOT 使本 App 成為前景或取得鍵盤焦點：程式 MUST NOT 呼叫 `NSApp.activate` 或 `NSApplication.activate(ignoringOtherApps:)`，面板維持 `canBecomeKey = false`／`canBecomeMain = false` 與 `.nonactivatingPanel`。tracking area MUST 使用 `.activeAlways`，不得依賴 App 啟用。此限制沿用 app-shell 的 `panel-shell`「Accessory App 且永不啟用」。全專案唯一例外為 `single-instance` capability 的重複實例對話框（僅 `SingleInstanceGuard.swift`，啟動最前段、面板尚未建立）。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/` 執行 `grep -rn "activate(" Sources/`
- **THEN** SHALL 無對 `NSApp`／`NSApplication` 的啟用呼叫，唯一例外為 `SingleInstanceGuard.swift`

#### Scenario: 操作期間 frontmost 不變
- **WHEN** 使用者在另一 App 持續打字，同時點擊 `<`／`>`、滑鼠進出面板
- **THEN** `frontmostApplication` SHALL 不變、鍵盤輸入 SHALL 不中斷、本 App 的啟用通知 SHALL 為零（需人工驗收）
