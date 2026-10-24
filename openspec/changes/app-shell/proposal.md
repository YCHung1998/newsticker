## Why

前四個 change 分別定義了協定（`message-contract`）、Rust helper（`connect-engine-fastbull`）、平台可行性實驗（`panel-feasibility-spikes`）與純邏輯核心（`show-engine-core`）。使用者實際看到與操作的是 App 殼層：浮動面板、選單列、位置記憶、渲染、helper 行程管理，以及能組裝出可執行 `.app` 的建置流程。這些全是 AppKit／行程／簽名的整合工作，風險集中在平台行為（全螢幕、Focus、計時器、螢幕參數變更）與 helper 生命週期（孤兒行程、誤判卡死、簽名失效）。本 change 把它們規格化，並把端到端驗收（假 helper → 真 helper、正式 `.app` 環境）寫成可執行的項目。

## What Changes

- 新增 `FastBullTicker` App 殼層規格：`PanelShell`、`StatusMenu`、`Persistence`、`TickerRenderer`、`FeedClient`，以及 Makefile 組裝與簽名（`helper`／`app`／`sign`／`test`）。
- **依賴 `panel-feasibility-spikes` 的 `spikes/RESULTS.md` 決定章節**：level 與 `collectionBehavior` 最終組合、渲染方案（displayLink 或 `CABasicAnimation`）、選單展開期間計時器作法、長句 bitmap 是否切塊。**（2026-10-24 修訂，【假設】協調者依使用者「繼續完成後續」指示所做，使用者尚未逐項確認）暫定實作先行**：使用者優先目標是儘早有一個能執行、能看到的 App，故 3.2／3.3／4.1 不再等待 spike 結果，先以設計文件預設值做「暫定實作（待 spike 決定確認後調整）」：level `.statusBar`、collectionBehavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`（`canJoinAllApplications` 先不加，待 S1）、渲染 `NSView.displayLink`、補料計時器 `.common` mode。這些值集中在 `ShellConfig`，spike 決定確認後只替換常數或渲染實作；暫定值不構成「已通過 S1」，5.3 仍須在正式簽名 `.app` 補驗。
- **消費 `show-engine-core` 的 API**（協定型別、`LineBuffer`、`TickerScheduler`、版面計算），不重新實作純邏輯。
- 端到端驗收：先以假 helper 腳本（正常輸出、崩潰、半行、卡死、stderr 灌滿）測 `FeedClient`，再換真 helper；helper 生命週期、螢幕參數變更、spike 結論在正式 `.app` bundle 的補驗、記憶體基準量測、VPN／Proxy 下 helper TLS 驗證。許多驗收**需使用者在機器前操作**，tasks 逐項標明。
- 不在範圍：Core 純邏輯、協定、Rust helper、spike 本身；設計文件第 10 節 v1 非目標（通知、搜尋、歷史、多來源同時顯示、設定頁、全域快捷鍵、Intel、App Store、notarization、每螢幕一視窗、可調寬度、點擊開詳情、可調速度）。
- 本階段只產規格，不建立任何 Swift、Makefile 或腳本。

## Capabilities

### New Capabilities
- `panel-shell`: NSPanel 設定、accessory App、不搶 Focus、拖曳、透明度；level／collectionBehavior 為暫定值（待 spike 確認）。
- `status-menu`: 選單列項目、滑桿、隱藏／顯示、點穿（不跨重啟）、面板右鍵後備入口、選單展開期間計時器。
- `window-persistence`: 螢幕 UUID＋相對偏移＋透明度存檔、debounce、螢幕缺失回退與夾制、螢幕參數變更。
- `ticker-renderer`: 渲染介面、暫定 displayLink 實作（待 S4 確認）、遮蔽／隱藏凍結、bitmap 預渲染與切塊。
- `feed-client`: helper 行程管理、退避、卡死判定、睡眠喚醒寬限、不可恢復錯誤、結束流程、雙實例窗口。
- `app-packaging`: Makefile 目標、bundle 結構、Info.plist、由內而外重新簽名與驗證、helper 路徑覆寫。
- `app-acceptance`: 端到端驗收（假 helper → 真 helper）、生命週期、螢幕參數、bundle 補驗、記憶體基準、VPN／Proxy。

### Modified Capabilities
（無。）

## Impact

- 前置依賴：`show-engine-core` 已 apply（Package.swift 與 Core API）；`panel-feasibility-spikes` 已 apply 且 `RESULTS.md` 決定章節（改為「暫定實作先行」，決定章節確認前以設計文件預設值暫定，見上）；`connect-engine-fastbull` 已 apply（真 helper 驗收）；`message-contract` 的 fixtures。
- 新增（apply 階段）：`Sources/FastBullTicker/`（取代空殼）、`Resources/Info.plist`、`Makefile`、`Tests/` 內 App 層測試、假 helper 腳本（測試用）。
- 硬體／環境前提：macOS 26.5.1、Xcode 26.6、Swift 6.3.3、rustc／cargo（已實測）；外接螢幕一台；可進行睡眠喚醒與 VPN／Proxy 環境（若使用者有）。
- 風險：spike 若判定 S1 不過關，`PanelShell` 的暫定值須回頭修正（見 `spike-decisions`；暫定實作不代表可蓋過全螢幕）；簽名失效、孤兒行程、誤判卡死見設計文件第 8 節。
