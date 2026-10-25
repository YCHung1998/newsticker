## ADDED Requirements

### Requirement: LaunchAtLoginService 協定與狀態
App SHALL 以可注入的協定 `LaunchAtLoginService` 包裝開機自動啟動：`status`（`LaunchAtLoginStatus`：`enabled`、`notRegistered`、`requiresApproval`、`notFound`）、`enable() throws`、`disable() throws`、`openSystemSettings()`。真實實作 `SystemLaunchAtLoginService` MUST 使用 `SMAppService.mainApp`（macOS 13+）並是 `Sources/` 中唯一 import `ServiceManagement` 的檔案；`SMAppService.Status` 轉為 `LaunchAtLoginStatus` MUST 由純函式 `map` 完成（涵蓋 `.enabled`、`.notRegistered`、`.requiresApproval`、`.notFound` 與未知值）。開機自動啟動屬系統狀態，MUST NOT 寫入 `style.json` 或 `TickerStyle`。

#### Scenario: 狀態對應
- **WHEN** 以 `.enabled`、`.notRegistered`、`.requiresApproval`、`.notFound` 呼叫 `map`
- **THEN** SHALL 依序得到 `enabled`、`notRegistered`、`requiresApproval`、`notFound`

#### Scenario: 不進樣式檔
- **WHEN** 檢視 `TickerStyle.keys`
- **THEN** SHALL 不含任何開機自動啟動相關的鍵

### Requirement: 如實呈現狀態與錯誤
`LaunchAtLoginController`（純邏輯，可注入服務）MUST 把服務結果轉為 UI 用的 `LaunchAtLoginViewState`：(1)開關位置以「呼叫後重新讀取的 `status`」為準（`enabled` 為開，其餘為關），而不是使用者按了什麼；(2)說明文字：`enabled` →「已啟用」、`notRegistered` →「未啟用」、`requiresApproval` →「需要在「系統設定 → 一般 → 登入項目」核准」且 `offersOpenSettings` 為 true、`notFound` →「找不到可註冊的 App（請從 .app 執行）」；(3) `enable()`／`disable()` 丟錯時 MUST 顯示「失敗：<錯誤訊息>」並保留重新讀到的實際狀態，MUST NOT 崩潰或默默吞掉；(4)重新整理狀態（例如面板開啟時）MUST 重新讀取 `status`，因為使用者可能在系統設定中改過。ad-hoc 簽名 App 的註冊結果屬平台行為【假設】：可能成功、可能需核准、可能失敗，三種都 MUST 如實顯示，且本 App MUST NOT 宣稱已啟用除非 `status == .enabled`。

#### Scenario: 成功啟用
- **WHEN** 假服務 `enable()` 成功且之後 `status` 為 `enabled`
- **THEN** 檢視狀態 SHALL 為開關開、說明「已啟用」

#### Scenario: 需要核准
- **WHEN** 假服務 `enable()` 成功但 `status` 為 `requiresApproval`
- **THEN** 開關 SHALL 為關、說明 SHALL 含「系統設定 → 一般 → 登入項目」、`offersOpenSettings` SHALL 為 true

#### Scenario: 註冊失敗
- **WHEN** 假服務 `enable()` 丟出錯誤「Operation not permitted」
- **THEN** 說明 SHALL 以「失敗：」開頭並含該訊息，開關 SHALL 為關（狀態仍為 `notRegistered`），且 SHALL 不崩潰

#### Scenario: 停用
- **WHEN** 狀態為 `enabled` 時呼叫停用，假服務 `disable()` 成功後 `status` 為 `notRegistered`
- **THEN** 開關 SHALL 為關、說明「未啟用」

#### Scenario: 外部改變後重新整理
- **WHEN** 使用者在系統設定中關閉登入項目後重新整理
- **THEN** 檢視狀態 SHALL 反映重新讀取的 `status`

### Requirement: 測試不得真的註冊
所有自動測試 MUST 使用假服務；MUST NOT 呼叫真實 `SMAppService`（`register`／`unregister`／`openSystemSettingsLoginItems`）。靜態守衛測試 MUST 確認 `Tests/` 目錄不出現 `SMAppService` 字串（`map` 測試以隱含成員語法傳入狀態值，不建構 `SMAppService` 物件），`Sources/` 僅 `SystemLaunchAtLoginService.swift` 出現。真實註冊的行為（三種結果）為【需人工驗收】。

#### Scenario: 守衛
- **WHEN** 掃描原始碼
- **THEN** `Tests/` SHALL 無 `SMAppService`；`Sources/` 中含 `SMAppService` 的檔案 SHALL 恰為 `SystemLaunchAtLoginService.swift`

#### Scenario: 人工驗收
- **WHEN** 在實機以 ad-hoc 簽名的 `build/FastBullTicker.app` 開啟開關
- **THEN** 面板 SHALL 顯示 `enabled`、`requiresApproval` 或失敗訊息三者之一，且與「系統設定 → 一般 → 登入項目」所見一致（需人工驗收）
