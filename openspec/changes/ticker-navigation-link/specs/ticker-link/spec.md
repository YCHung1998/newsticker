## ADDED Requirements

### Requirement: 迴紋針圖示的顯示規則
每則含 `url` 的訊息 SHALL 在文字之後顯示迴紋針圖示，圖示位於訊息最右側的連結欄位（寬度 `linkSlotWidth`，暫定 26pt【假設】）。不含 `url` 的訊息 MUST 不顯示圖示，也 MUST NOT 保留連結欄位寬度（版面見 `ticker-layout` 的「有連結的訊息保留連結欄位寬度」）【假設：選擇「不顯示」而非「顯示但停用」，以免使用者誤以為壞掉；需使用者確認】。圖示顏色 MUST 與該則文字顏色相同（`live` 為黑、`replay` 為白，之後隨樣式設定），以向量路徑（`CGPath`）或 SF Symbol `paperclip` 繪製皆可【假設，實作可選】，並預渲染進該則訊息的 bitmap。圖示不得被截斷文字的「…」遮蓋。圖示的外觀與大小屬【需人工目視】。與 app-shell 的 `ticker-renderer`（每則訊息預渲染為 bitmap）相關。

#### Scenario: 有 url 顯示圖示
- **WHEN** 渲染一則含 `url` 的訊息
- **THEN** 其 bitmap 在連結欄位範圍內 SHALL 含前景色像素，欄位範圍外不屬文字處 SHALL 無額外前景像素（以像素取樣斷言）

#### Scenario: 無 url 不顯示
- **WHEN** 渲染一則不含 `url` 的訊息
- **THEN** 其寬度 SHALL 不含連結欄位，bitmap SHALL 與本 change 之前逐像素相同

#### Scenario: 截斷文字仍有圖示
- **WHEN** 含 `url` 的長訊息被截斷為「…」結尾
- **THEN** 連結欄位 SHALL 位於「…」之後且不重疊

### Requirement: 點擊迴紋針以預設瀏覽器開啟連結
在迴紋針命中區（見 `ticker-navigation` 的「命中測試與拖曳區分」）按下並於同一命中區放開左鍵 SHALL 以系統預設瀏覽器開啟該訊息的 `url`，且對一次點擊 MUST 恰開啟一次。開啟動作 MUST 經由可注入的 `URLOpener` 介面（單一方法，輸入 `URL`，回傳是否成功）；正式實作為 `NSWorkspace.shared.open` 並明確指定 `OpenConfiguration`，預設讓被開啟的瀏覽器成為前景（使用者要閱讀完整內容）【假設：瀏覽器前景；若使用者希望留在原 App，改 `activates = false`，待確認】。拖曳（mouse-down 後超過拖曳門檻）、移出命中區再放開、右鍵、Control-點擊、點穿模式下 MUST NOT 開啟。`url` 以排入當下 `PlacedItem.url` 為準，不得在點擊時重新查詢歷史。

#### Scenario: 點擊開啟一次
- **WHEN** 在含 `url` 的訊息的迴紋針命中區按下並放開左鍵
- **THEN** 注入的 opener SHALL 恰被呼叫一次，參數 SHALL 為該訊息的 `url`

#### Scenario: 移出再放開
- **WHEN** 在迴紋針上按下左鍵，移出命中區再放開
- **THEN** opener SHALL 不被呼叫

#### Scenario: 右鍵與 Control-點擊
- **WHEN** 在迴紋針上按右鍵或 Control-左鍵
- **THEN** opener SHALL 不被呼叫

#### Scenario: opener 失敗
- **WHEN** opener 回傳 false
- **THEN** App SHALL 寫日誌並繼續運作，SHALL NOT 重試、SHALL NOT 彈出對話框

### Requirement: 只允許開啟 http 與 https 連結
開啟前 MUST 以純函式 `LinkPolicy.openableURL(from: String) -> OpenableURL?` 驗證：scheme MUST 為 `http` 或 `https`、host 非空、MUST NOT 含 userinfo（`user:pass@`）【假設：避免誤導性網址】、字串長度不超過 2048 位元組、`URL(string:)` 解析成功；任一不符回傳 `nil`，此時 MUST NOT 呼叫 opener（僅寫日誌）。此驗證是對協定層 `url` 規則的第二道防線，不得因協定層已驗證而省略。`LinkPolicy` MUST NOT 提供繞過驗證的 API；opener 的參數型別 MUST 是通過驗證才能構造的包裝型別，使「未驗證的 URL 無法被開啟」在型別層即成立。

#### Scenario: 合法連結
- **WHEN** 輸入 `https://www.fastbull.com/tw/fastshort/4334051_1_2`
- **THEN** SHALL 回傳對應 `URL`

#### Scenario: 非 http(s)
- **WHEN** 輸入 `javascript:alert(1)`、`file:///etc/hosts`、`ftp://example.com/a` 或 `mailto:a@b.c`
- **THEN** SHALL 回傳 `nil`，opener SHALL 不被呼叫

#### Scenario: 含 userinfo 或無 host
- **WHEN** 輸入 `https://user:pw@example.com/` 或 `https:///path`
- **THEN** SHALL 回傳 `nil`

#### Scenario: 超長
- **WHEN** 輸入超過 2048 位元組的 `https://...`
- **THEN** SHALL 回傳 `nil`

#### Scenario: 傳給 opener 的只有 http(s)
- **WHEN** 以包含合法與非法 `url` 的訊息組合模擬多次點擊，opener 為記錄用的假物件
- **THEN** 記錄到的所有 URL 的 scheme SHALL 皆為 `http` 或 `https`

### Requirement: 開啟連結不啟用本 App、不搶鍵盤焦點
點擊迴紋針 MUST NOT 使本 App 成為前景或取得鍵盤焦點：不呼叫 `NSApp.activate`，面板維持 `.nonactivatingPanel`、`canBecomeKey = false`。被開啟的瀏覽器成為前景是預期行為，不屬於「搶焦點」；但本 App 的啟用通知（`NSWorkspace.didActivateApplicationNotification` 中屬於本 App 者）MUST 為零。點擊期間使用者在其他 App 的輸入焦點行為（被瀏覽器取代前景）以外，不得有本 App 造成的焦點變化。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/` 搜尋 `NSApp.activate` 與 `activate(ignoringOtherApps`
- **THEN** SHALL 無結果

#### Scenario: 點擊後前景為瀏覽器而非本 App
- **WHEN** 使用者在 TextEdit 打字時點擊迴紋針（需人工驗收）
- **THEN** 預設瀏覽器 SHALL 開啟該頁，`frontmostApplication` SHALL 不是本 App，本 App 啟用通知 SHALL 為零

### Requirement: 自動測試不得開啟真實瀏覽器
所有自動測試 MUST 只使用注入的假 `URLOpener`；正式 `NSWorkspace` 實作 MUST 只在 `AppDelegate` 組裝處建立。測試原始碼 MUST NOT 呼叫 `NSWorkspace.shared.open`（由守衛測試掃描 `Tests/` 目錄，比照 `ticker-connect` 的 `no_external_network` 守衛）；`Sources/` 中 `NSWorkspace.shared.open` MUST 只出現在以 `Workspace` 開頭、`Opener.swift` 結尾、實作 opener 協定的檔案（本 change 為 `WorkspaceURLOpener.swift`；`ticker-style-settings` 另有 `WorkspaceFileOpener.swift`）。測試 MUST NOT 連到正式網站；FastBull 連結只作為字串驗證用的輸入。

#### Scenario: 守衛測試
- **WHEN** `Tests/` 原始碼出現 `NSWorkspace.shared.open`
- **THEN** 守衛測試 SHALL 失敗並指出檔案

#### Scenario: 組裝處才有真實 opener
- **WHEN** 檢查 `Sources/`
- **THEN** `NSWorkspace.shared.open` SHALL 只出現在 `Workspace*Opener.swift` 檔案中（本 change 僅 `WorkspaceURLOpener.swift`）
