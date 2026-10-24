## MODIFIED Requirements

### Requirement: 開啟連結不啟用本 App、不搶鍵盤焦點
點擊迴紋針 MUST NOT 使本 App 成為前景或取得鍵盤焦點：不呼叫 `NSApp.activate`，面板維持 `.nonactivatingPanel`、`canBecomeKey = false`。被開啟的瀏覽器成為前景是預期行為，不屬於「搶焦點」；但本 App 的啟用通知（`NSWorkspace.didActivateApplicationNotification` 中屬於本 App 者）MUST 為零。點擊期間使用者在其他 App 的輸入焦點行為（被瀏覽器取代前景）以外，不得有本 App 造成的焦點變化。全專案唯一例外為 `single-instance` capability 的重複實例對話框（僅 `SingleInstanceGuard.swift`，啟動最前段、面板尚未建立）；該例外與點擊迴紋針路徑無關。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/` 搜尋 `NSApp.activate` 與 `activate(ignoringOtherApps`
- **THEN** SHALL 只在 `SingleInstanceGuard.swift` 出現（`single-instance` 的唯一例外），其餘檔案 SHALL 無結果

#### Scenario: 點擊後前景為瀏覽器而非本 App
- **WHEN** 使用者在 TextEdit 打字時點擊迴紋針（需人工驗收）
- **THEN** 預設瀏覽器 SHALL 開啟該頁，`frontmostApplication` SHALL 不是本 App，本 App 啟用通知 SHALL 為零
