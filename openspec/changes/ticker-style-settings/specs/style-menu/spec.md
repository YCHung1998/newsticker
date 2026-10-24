## ADDED Requirements

### Requirement: 樣式子選單的項目清單
選單列選單（與面板右鍵共用同一份 `NSMenu`，見 app-shell 的 `status-menu`）SHALL 在「點穿模式」與分隔線之間新增一個「樣式」項目，其子選單由上而下為：(1)（僅在「設定檔有誤」狀態時）停用的提示行「設定檔有誤，沿用上次有效值」；(2)「字級」子選單；(3)「捲動速度」滑桿；(4)「訊息量」子選單；(5)「圓角」滑桿；(6)「即時配色」子選單；(7) 分隔線；(8)「顯示時間」勾選；(9)「顯示標籤」勾選；(10) 分隔線；(11)「開啟樣式設定檔…」；(12)「重設為預設」。所有項目 MUST 在 `NSMenu` 內完成：MUST NOT 開啟任何新視窗、MUST NOT 使用 `NSAlert` 或對話框、MUST NOT 呼叫 `NSApp.activate`（以免啟用 App）。選單的項目清單 MUST 由純資料模型（`StyleMenuModel`，輸入目前樣式與「設定檔有誤」狀態，輸出項目描述：標題、勾選、是否停用、動作）產生，`NSMenu` 僅負責呈現，使項目清單可不建立 `NSMenu` 即測試。原有四個項目（透明度、隱藏／顯示、點穿、結束）MUST 保持原順序與行為；原 `StatusMenuTests` 對「恰為四項」的斷言須隨之更新為五項（透明度、隱藏／顯示、點穿、樣式、結束）。

#### Scenario: 項目清單
- **WHEN** 以預設樣式建立 `StyleMenuModel`
- **THEN** 項目 SHALL 依序為字級、捲動速度、訊息量、圓角、即時配色、分隔線、顯示時間、顯示標籤、分隔線、開啟樣式設定檔、重設為預設，且無提示行

#### Scenario: 設定檔有誤時多一行提示
- **WHEN** 「設定檔有誤」狀態為真
- **THEN** 子選單第一項 SHALL 為停用的「設定檔有誤，沿用上次有效值」

#### Scenario: 不建立視窗
- **WHEN** 建立選單並執行所有項目動作的測試
- **THEN** SHALL 不產生任何 `NSWindow`／`NSAlert`，也 SHALL 不呼叫任何啟用 App 的 API

### Requirement: 字級預設檔位
「字級」子選單 SHALL 提供檔位：小 13、標準 16（預設）、大 20、特大 24（pt）【假設】；目前 `fontSize` 等於某檔位者 MUST 顯示勾選，不等於任何檔位（例如手動編輯為 17）時 MUST 不勾選任何項目。選擇檔位 MUST 設定 `fontSize` 並套用、寫回。檔位值 MUST 皆在 `fontSize` 的合法範圍內。

#### Scenario: 選大
- **WHEN** 選擇「大」
- **THEN** `fontSize` SHALL 變為 20，「大」SHALL 勾選，其他 SHALL 不勾選

#### Scenario: 自訂值
- **WHEN** `fontSize` 為 17
- **THEN** 四個檔位 SHALL 皆不勾選

### Requirement: 捲動速度滑桿
「捲動速度」SHALL 以 `NSMenuItem.view` 內的滑桿呈現（比照既有透明度滑桿），範圍等於 `scrollSpeed` 的合法範圍（20–300 px/s），初值為目前 `scrollSpeed`，連續拖動即時生效（經排程器 `reconfigure`，視覺位置連續）並 debounce 寫回。滑桿旁 SHALL 顯示目前數值（整數）。

#### Scenario: 拖到最大
- **WHEN** 滑桿拖到最大
- **THEN** `scrollSpeed` SHALL 為 300 並套用

#### Scenario: 範圍一致
- **WHEN** 檢查滑桿的最小與最大值
- **THEN** SHALL 等於 `scrollSpeed` 的合法範圍

### Requirement: 訊息量檔位
「訊息量」子選單 SHALL 提供檔位：5、10（預設）、20 則【假設】，標題以「n 則」表示；勾選規則同字級。選擇檔位 MUST 設定 `replayCount` 並套用、寫回；套用語意見 `ticker-style`（影響之後的重播取料；若 `ticker-navigation-link` 已 apply，`(n/N)` 的 N 隨之改變）。檔位值 MUST 皆在 `replayCount` 的合法範圍（3–30）內。

#### Scenario: 選 20
- **WHEN** 選擇「20 則」
- **THEN** `replayCount` SHALL 變為 20，之後的重播 SHALL 循環最新 20 則

#### Scenario: 檔位在合法範圍
- **WHEN** 檢查所有訊息量檔位
- **THEN** 每一個 SHALL 在 3–30 之內

### Requirement: 圓角滑桿
「圓角」SHALL 以滑桿呈現，範圍 0–21pt（`cornerRadius` 的合法範圍），連續拖動即時生效並 debounce 寫回；最左為直角（預設）。

#### Scenario: 拖動
- **WHEN** 滑桿拖到 10
- **THEN** `cornerRadius` SHALL 為 10 並套用到面板的圖層

### Requirement: 即時配色預設
「即時配色」子選單 SHALL 提供至少三組預設，每組同時設定 `liveBackground` 與 `liveText`：白底黑字（預設）`#FFFFFF`／`#000000`、黃底黑字 `#FFE45C`／`#000000`、綠底白字 `#1E7B3C`／`#FFFFFF`【假設：色碼由本規格訂定，使用者尚未確認；三組對比度皆高於 4.5】。目前樣式的兩個色碼與某組完全相同者 MUST 顯示勾選。選擇預設 MUST 只改這兩個欄位（不動重播配色）、套用並寫回。重播配色與其他色彩只能經設定檔編輯【假設】。

#### Scenario: 選黃底黑字
- **WHEN** 選擇「黃底黑字」
- **THEN** `liveBackground` SHALL 為 `#FFE45C`、`liveText` SHALL 為 `#000000`，`replayBackground` 與 `replayText` SHALL 不變

#### Scenario: 預設皆可讀
- **WHEN** 計算三組預設的對比度
- **THEN** 每組 SHALL 大於等於 4.5

### Requirement: 顯示時間與顯示標籤切換
「顯示時間」勾選項 MUST 切換 `showTime`，「顯示標籤」勾選項 MUST 切換 `showLabel`；勾選狀態 MUST 反映目前樣式。切換 MUST 套用並寫回。

#### Scenario: 關閉標籤
- **WHEN** 取消勾選「顯示標籤」
- **THEN** `showLabel` SHALL 為 false，標籤 SHALL 隱藏，帶子 SHALL 從面板左緣起顯示

### Requirement: 開啟樣式設定檔
「開啟樣式設定檔…」MUST 以系統預設應用程式開啟樣式檔：若檔案不存在，MUST 先以目前生效樣式（正規化格式）建立檔案再開啟。開啟動作 MUST 經可注入的 `FileOpener`（單方法，輸入檔案 URL，回傳是否成功）；正式實作為 `NSWorkspace.shared.open`，MUST NOT 在測試中被呼叫。本 App MUST NOT 因此被啟用；被開啟的編輯器成為前景是預期行為。開啟失敗 MUST 只記錄日誌。

#### Scenario: 檔案不存在時先建立
- **WHEN** 樣式檔不存在時選擇「開啟樣式設定檔…」
- **THEN** SHALL 先在暫存目錄建立含目前生效樣式的 `style.json`，再呼叫注入的 opener 一次，參數 SHALL 為該檔案 URL

#### Scenario: 檔案存在時不改寫
- **WHEN** 樣式檔已存在
- **THEN** SHALL 不改寫檔案，只呼叫 opener

### Requirement: 重設為預設
「重設為預設」MUST 把生效樣式設為 `TickerStyle.default`、套用並寫回；寫回前若磁碟上現有檔案內容與預設不同，MUST 依「寫回與備份」先複製為 `style.json.bak`。不得顯示確認對話框（選單內無法確認，且不得開新視窗）；以備份作為可復原手段【假設】。

#### Scenario: 重設
- **WHEN** 目前樣式為自訂值，選擇「重設為預設」
- **THEN** 生效樣式 SHALL 等於預設，`style.json.bak` SHALL 含重設前的檔案內容，`style.json` SHALL 為預設的正規化內容

### Requirement: 選單與狀態同步
選單展開時 MUST 以目前生效樣式更新勾選與滑桿位置與「設定檔有誤」提示（熱重載或手動改檔後亦然），可使用 `NSMenuDelegate.menuNeedsUpdate`。選單展開期間補料計時器 MUST 持續運作（沿用 app-shell 的 `.common` mode `Timer`，本 change 不得改變）。滑桿操作期間的連續變更 MUST 不造成帶子空白或位置跳動。

#### Scenario: 熱重載後選單同步
- **WHEN** 使用者手動把檔案的 `fontSize` 改為 20 並已熱重載，再展開選單
- **THEN** 字級「大」SHALL 勾選

#### Scenario: 展開期間不斷料
- **WHEN** 選單展開並拖動速度滑桿 60 秒（需人工，於正式 bundle 驗證）
- **THEN** 帶子 SHALL 無空白、速度 SHALL 即時變化

### Requirement: 測試策略與禁止項目
選單項目清單、檔位與預設值、勾選規則、動作對樣式的影響 MUST 以純函式的 `StyleMenuModel` 與注入的假儲存庫／假 opener／假時鐘測試；`NSMenu` 層只做必要的組裝測試（不顯示、不建立 `NSStatusItem`，比照既有 `StatusMenuTests`）。自動測試 MUST NOT 開啟真實視窗、MUST NOT 呼叫真實的 `NSWorkspace.shared.open`（以守衛測試掃描 `Tests/`，並確認 `Sources/` 只在 `Workspace*Opener.swift` 檔案出現，本 change 新增 `WorkspaceFileOpener.swift`）、MUST NOT 寫入真實樣式檔。圓角、配色與字級的實際觀感與滑桿手感為【需人工目視】。

#### Scenario: 守衛
- **WHEN** `Tests/` 原始碼出現 `NSWorkspace.shared.open`
- **THEN** 守衛測試 SHALL 失敗
