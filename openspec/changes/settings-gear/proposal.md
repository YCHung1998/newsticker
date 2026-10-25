## Why

使用者希望在「即時財經快訊」標籤之前有一個**設定齒輪**，作為使用者 UI 設定介面（原話：「我希望有一個設定齒輪放在『即時財經快訊』之前，作為使用者 UI 設定介面」）；點齒輪「跳出面板，面板有選單可以調整」。目前所有設定只能走選單列的「樣式」子選單或手動編輯 `style.json`，而 `nav-layout-tweaks` 已把版面做成可由單一偏移推導（預留齒輪槽），現在是補上齒輪的時機。使用者同時要求把先前建議的三個新設定一併納入：左右切換後的停留時間、輪詢間隔、開機自動啟動。

## What Changes

- **版面**：面板由左至右為〔齒輪槽 28pt〕→ 紅色標籤 → 控制列 `< (n/N) >` → 訊息帶子。為維持使用者已確認的帶子可視寬度 370pt，面板寬度由 620 改為**推導值** 28 + 150 + 100 + 370 = 648pt（不再寫死）。`showLabel=false` 時齒輪仍在最左、控制列緊接其後（帶子可視寬度 520 不變）。
- **齒輪圖示與命中**：自繪齒輪（路徑，非 SF Symbol）、hover 時高亮；命中測試新增 `HitTarget.gear`（優先序：齒輪／按鈕／迴紋針 > 拖曳），mouse-up 觸發，只回應左鍵，不啟用 App。
- **新設定（寫進 `TickerStyle`／`style.json`）**：`seekHoldSeconds`（左右切換後停留秒數，預設 1、範圍 0.5–10）、`pollIntervalSeconds`（輪詢間隔，檔位 10／30／60，預設 10）。停留時間經 Core `reconfigure`／`SchedulerTunables` 生效；輪詢間隔變更時**重啟 helper**（`--interval-ms`），重啟期間顯示不中斷，helper 重發的 `snapshot` 不誤觸 LIVE、不洗掉帶子與即時佇列。
- **開機自動啟動**：不進 `style.json`（屬系統狀態）；以 `SMAppService.mainApp` 包成可注入的 `LaunchAtLoginService`，UI 顯示實際狀態（啟用／未啟用／需核准／錯誤）。
- **設定面板（B 段）**：點齒輪彈出非啟用 `NSPanel`，內含現有「樣式」選單的全部項目（字級、捲動速度、圓角、重播訊息量、即時配色、顯示時間、顯示標籤、開啟樣式設定檔、重設為預設）加上上述三個新設定；點齒輪、面板外、關閉鈕即關閉；操作立即生效並寫回 `style.json`。選單列「樣式」子選單**保留**，與面板共用同一份 `StyleMenuModel` 與動作。
- **BREAKING（相對現況）**：面板寬度 620 → 648；既有以面板座標寫死的測試斷言需平移 28pt（逐項記錄於 `Tests/README.md`，不刪除任何斷言）；`SchedulerTunables` 由六欄位增為七欄位。

## Capabilities

### New Capabilities
- `settings-gear`: 齒輪槽版面（槽寬、面板寬度推導）、齒輪圖示與 hover、`HitTarget.gear` 與 mouse-up 觸發、不啟用 App。
- `settings-values`: `TickerStyle` 新欄位 `seekHoldSeconds`／`pollIntervalSeconds` 的範圍、檔位、夾制、預設與生效路徑；對應 `StyleMenuAction`。
- `poll-interval`: helper 輪詢間隔參數、計畫性重啟（`FeedClient.reconfigure(arguments:)`）、重啟與 `snapshot` 重送的安全性。
- `launch-at-login`: `LaunchAtLoginService` 協定、狀態對應、錯誤呈現、測試不得真註冊。
- `settings-panel`: 點齒輪彈出的非啟用設定面板（內容、位置、關閉規則、與樣式選單共用、平台風險與人工驗收）。

### Modified Capabilities
- `ticker-navigation`: 「控制列的位置與版面」（齒輪槽由預留變為實作、面板寬 648）、「命中測試與拖曳區分」（新增 `.gear`）、「切換後暫停自動捲動並恢復」（停留秒數可由設定調整，預設仍 1 秒）。
- `ticker-scheduler`: 新增「seekHoldSeconds 可於執行期調整」（`SchedulerTunables` 增第七欄位）。因主 specs 尚無「執行期重新設定」（它在進行中的 `ticker-style-settings`），此項以 ADDED 提出，依賴關係見 design.md。

## Impact

- 程式：`Sources/FastBullTickerApp/` 的 `ControlStripLayout`、`HitTesting`、`NavigationInput`、`ShellConfig`（最小增修）、`TickerView`、`ControlStripGlyphs`（或新檔 `GearGlyph.swift`）、`TickerStyle`、`StyleMenuModel`、`StyleApplier`、`FeedClient`、新檔 `LaunchAtLoginService.swift`；`Sources/FastBullTickerCore/TickerScheduler.swift`（`SchedulerTunables` 增欄位）。B 段另有設定面板檔案與 `AppDelegate` 組裝。
- 測試：新增 Core／App 測試與 `Tests/ga-mutations.py`；既有測試中寫死 620／座標的斷言平移（見 design.md）。
- 依賴：進行中的 `ticker-style-settings`（`TickerStyle`、`StyleStore`、`StyleMenuModel` 尚未同步到主 specs）、`single-instance-guard`、`app-shell`（只讀，不修改）。平台：`ServiceManagement`（macOS 13+，本專案最低 14）。
- 不改：協議（`protocol/`）、Rust helper（`ticker-connect/`，已支援 `--interval-ms`）、`spikes/`。
