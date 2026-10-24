## Why

兩個 App 實例會共用同一個 helper pid 檔（`~/Library/Application Support/FastBullTicker/helper.pid`），互相回收對方的 helper，造成 helper 反覆重啟、日誌混亂（已發生的真實問題）。目前沒有任何單一實例防護。使用者明確要求：「有開兩個就跳視窗問我是否要幫我把第一個關掉」。

## What Changes

- App 啟動最前段（啟動 `FeedClient`／helper、建立面板**之前**）偵測是否已有另一個同 bundle identifier（`local.fastbull.FastBullTicker`）的實例。
- 有則跳模態對話框（繁體中文）：「關閉舊的並繼續」（預設）／「取消」。取消 → 新實例立即結束；關閉 → 對舊實例 `terminate()`，最多等 5 秒，仍在則 `forceTerminate()` 再等最多 2 秒，確認消失才繼續；仍關不掉 → 第二個提示並結束新實例。
- 同時啟動競態：以 `launchDate`（相同或缺漏時以 pid 較大者）決定「較晚啟動」者負責詢問，較早者不詢問、照常執行【假設】。
- 開發／測試跳過開關：環境變數 `FASTBULL_TICKER_ALLOW_MULTIPLE=1`【假設：名稱】。
- 決策邏輯以可注入協定實作（`RunningInstancesProvider`、`AlertPresenter`、`InstanceTerminator`、`Sleeper`），自動測試全程使用假物件。
- **例外（修改既有規定）**：全專案「不得呼叫 `NSApp.activate`」改為「唯一例外：`SingleInstanceGuard.swift`，且只為顯示本對話框」。其餘路徑仍不得啟用本 App。守衛測試同步修改。

## Capabilities

### New Capabilities
- `single-instance`: 單一實例防護的偵測、詢問、關閉舊實例、競態、跳過開關、可測性與接線。

### Modified Capabilities
- `ticker-link`: 「開啟連結不啟用本 App、不搶鍵盤焦點」——靜態檢查改為放行 `SingleInstanceGuard.swift` 這個唯一例外。
- `ticker-navigation`: 「切換操作不啟用 App、不搶鍵盤焦點」——同上。

## Impact

- 新增 `Sources/FastBullTickerApp/SingleInstanceGuard.swift`；修改 `AppDelegate.swift`（最前段呼叫）。
- 修改守衛測試：`LinkOpenerGuardTests.swift`（`OpenerGuard.activationViolations`）、`PanelShellTests.swift`（`sourcesNeverCallApplicationActivation`）。
- 新增 `Tests/FastBullTickerAppTests/SingleInstanceGuardTests.swift`、`Tests/g1-mutations.py`；更新 `README.md`、`Tests/README.md`。
- 不改 helper、協定、Core；不改 `ShellConfig.swift`。
