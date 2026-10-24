## ADDED Requirements

### Requirement: 啟動初期偵測其他實例
App MUST 在 `applicationDidFinishLaunching` 最前段（早於建立面板、早於啟動 `FeedClient`／helper、早於讀寫 pid 檔）執行單一實例檢查。偵測 MUST 使用同 bundle identifier（`local.fastbull.FastBullTicker`）的執行中實例清單，且 MUST 排除自己的 pid。無 bundle identifier（非 bundle 啟動）時 MUST 視為無其他實例。

#### Scenario: 無其他實例
- **WHEN** 清單只含自己
- **THEN** 檢查 SHALL 回傳繼續啟動，且 SHALL NOT 顯示任何對話框、SHALL NOT 對任何 pid 呼叫 terminate

#### Scenario: 排除自己
- **WHEN** 清單含自己與另一個實例
- **THEN** `terminate` 與 `forceTerminate` SHALL 只會對另一個實例的 pid 呼叫，SHALL NOT 對自己的 pid 呼叫

### Requirement: 重複實例時詢問使用者
偵測到另一個實例且自己為「較晚啟動者」時，App MUST 顯示模態 `NSAlert`（繁體中文）：標題「FastBullTicker 已在執行」、說明「要關閉先前開啟的那個，改用這個嗎？」，按鈕依序為「關閉舊的並繼續」（預設）與「取消」。選「取消」時，新實例 MUST 立即結束，MUST NOT 啟動 helper、MUST NOT 建立面板，且 MUST NOT 對舊實例呼叫 `terminate`。

#### Scenario: 選取消
- **WHEN** 有其他實例且使用者選「取消」
- **THEN** 結果 SHALL 為結束新實例，舊實例的 terminate／forceTerminate 呼叫次數 SHALL 為零

#### Scenario: 預設按鈕
- **WHEN** 檢視對話框設定
- **THEN** 第一個按鈕（預設）SHALL 為「關閉舊的並繼續」

### Requirement: 關閉舊實例的流程
使用者選「關閉舊的並繼續」時，App MUST 對舊實例呼叫 `terminate()`，輪詢等待最多 5 秒；仍存活則呼叫 `forceTerminate()` 再等最多 2 秒；確認舊實例已消失後才繼續正常啟動【假設：時限】。若 `forceTerminate` 後仍存活，MUST 顯示第二個對話框（說明「無法關閉舊的實例，請手動關閉」）並結束新實例。不得在舊實例仍存活時繼續啟動。

#### Scenario: 正常結束
- **WHEN** 使用者選關閉，且 `terminate` 後舊實例在 5 秒內消失
- **THEN** SHALL 繼續啟動，SHALL NOT 呼叫 `forceTerminate`

#### Scenario: 需要強制結束
- **WHEN** `terminate` 後 5 秒仍存活
- **THEN** SHALL 呼叫 `forceTerminate`；若 2 秒內消失 SHALL 繼續啟動

#### Scenario: 關不掉
- **WHEN** `forceTerminate` 後 2 秒仍存活
- **THEN** SHALL 顯示第二個失敗提示並結束新實例，SHALL NOT 繼續啟動

#### Scenario: 不提前繼續
- **WHEN** 舊實例在 `terminate` 後仍存活且尚未滿 5 秒
- **THEN** 檢查 SHALL NOT 回傳繼續啟動

### Requirement: 同時啟動競態只有一邊詢問
兩個實例幾乎同時啟動時，只有「較晚啟動者」MUST 詢問；較早者 MUST NOT 顯示對話框、MUST NOT 呼叫 terminate，照常執行【假設：以 `launchDate` 判斷】。兩者 `launchDate` 皆存在且不同時，較大者為較晚；`launchDate` 相同或任一缺漏時，pid 較大者為較晚。自己要詢問，當且僅當自己對所有其他實例皆為較晚。

#### Scenario: 對方較晚
- **WHEN** 其他實例的 launchDate 晚於自己
- **THEN** 自己 SHALL 不詢問、不呼叫 terminate，並繼續啟動

#### Scenario: launchDate 相同以 pid 判斷
- **WHEN** launchDate 相同（或缺漏）
- **THEN** pid 較大者 SHALL 詢問，pid 較小者 SHALL 繼續啟動且不詢問

### Requirement: 跳過開關
環境變數 `FASTBULL_TICKER_ALLOW_MULTIPLE` 等於 `1` 時【假設：名稱】，MUST 略過整個檢查（不查詢實例、不顯示對話框、不 terminate），直接繼續啟動。其他值 MUST NOT 跳過。README MUST 記載此開關。

#### Scenario: 開關為 1
- **WHEN** 環境變數為 `1` 且有其他實例
- **THEN** SHALL 繼續啟動且無任何詢問或 terminate

#### Scenario: 開關為其他值
- **WHEN** 環境變數為 `0` 或空字串且有其他實例
- **THEN** SHALL 照常進入詢問流程

### Requirement: 決策邏輯可測且測試不碰真實系統
決策邏輯 MUST 經由可注入介面實作：`RunningInstancesProvider`、`AlertPresenter`、`InstanceTerminator`（terminate／forceTerminate／isRunning）、`Sleeper`。自動測試 MUST 只用假物件，MUST NOT 建立真實 `NSAlert`、MUST NOT 呼叫真實 `terminate`、MUST NOT 開視窗；測試原始碼 MUST NOT 引用真實實作類別（`NSAlertPresenter`、`SystemInstanceTerminator`、`RunLoopSleeper`）。

#### Scenario: 靜態檢查
- **WHEN** 掃描 `Tests/` 是否出現 `NSAlert(`、`NSAlertPresenter`、`SystemInstanceTerminator`、`RunLoopSleeper`
- **THEN** SHALL 無結果（守衛檔自身以拼接避開）

### Requirement: 對話框是唯一允許啟用本 App 的地方
`NSApp.activate` MUST 只出現在 `Sources/FastBullTickerApp/SingleInstanceGuard.swift`，且 MUST 只在要顯示本檢查的對話框時呼叫、整個程序最多一次（accessory App 必須啟用才能把對話框帶到前面）。其他任何路徑（點擊迴紋針、`<`／`>`、拖曳、選單、面板）仍 MUST NOT 啟用本 App。守衛測試 MUST 放行且僅放行此檔，並驗證該檔內恰有一處呼叫。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/` 搜尋 `NSApp.activate` 與 `activate(ignoringOtherApps`
- **THEN** SHALL 只在 `SingleInstanceGuard.swift` 出現，且該檔恰一處

#### Scenario: 守衛抓得到其他檔案
- **WHEN** 在其他檔案植入 `NSApp.activate`
- **THEN** 守衛測試 SHALL 失敗

### Requirement: 結束新實例不留下 helper
決定結束新實例時 MUST 在啟動 `FeedClient` 之前結束（不建面板、不啟動 helper、不寫 pid 檔），因此不得有殘留的 helper 行程。

#### Scenario: 接線順序
- **WHEN** 檢查 `AppDelegate.applicationDidFinishLaunching`
- **THEN** 單一實例檢查 SHALL 位於建立 `PanelShell` 與 `startFeed` 之前，結果為結束時 SHALL 立即 return
