## ADDED Requirements

### Requirement: 以 Process 與 Pipe 啟動 helper
`FeedClient` MUST 以 `Process`＋`Pipe` 啟動 helper，stdout 位元組交給 Core 的 `LineBuffer` 與解碼器。helper 路徑 MUST 以 `Bundle.main.url(forAuxiliaryExecutable:)` 尋找；環境變數可覆寫路徑（僅開發用，覆寫的環境變數名稱【待確認】）。stderr MUST 一律讀走（寫入日誌或丟棄），MUST NOT 讓 stderr 管線塞滿而阻塞 helper。

#### Scenario: stderr 灌滿
- **WHEN** 假 helper 向 stderr 持續輸出數十 MB
- **THEN** helper SHALL 不被阻塞，stdout 訊息 SHALL 仍持續被消費

#### Scenario: 路徑覆寫
- **WHEN** 設定覆寫環境變數指向假 helper
- **THEN** `FeedClient` SHALL 啟動該路徑而非 bundle 內的 helper

### Requirement: generation token
每次啟動 helper MUST 遞增 generation token；`terminationHandler`、`readabilityHandler`、卡死計時器的回呼 MUST 帶 token，與目前 generation 不符者 MUST 被忽略。

#### Scenario: 舊行程事件
- **WHEN** 第 1 代行程在第 2 代啟動後才送出終止事件
- **THEN** 該事件 SHALL 不改變目前狀態、不觸發額外重啟

### Requirement: readabilityHandler 的 EOF 處理
`readabilityHandler` 收到空資料（EOF）時 MUST 清除該 handler（設為 nil）並關閉檔案描述符，避免 busy loop。

#### Scenario: helper 結束
- **WHEN** 假 helper 結束造成 EOF
- **THEN** handler SHALL 被清除，CPU SHALL 不因空轉升高（測試以呼叫次數斷言）

### Requirement: 指數退避重啟
helper 非預期結束時 MUST 以指數退避重啟：1 秒起、倍增、上限 60 秒，加 jitter（比例【待確認】，暫定 ±20%）。僅當 helper 穩定運行超過 60 秒才重置退避。退避時間計算 MUST 為可注入時鐘與亂數源的純函式並有單元測試。

#### Scenario: 連續快速崩潰
- **WHEN** 假 helper 連續啟動即崩潰
- **THEN** 重啟間隔 SHALL 依序約 1、2、4…最多 60 秒（注入假時鐘斷言）

#### Scenario: 穩定後重置
- **WHEN** helper 運行 61 秒後崩潰
- **THEN** 下一次退避 SHALL 回到 1 秒

#### Scenario: 短暫運行不重置
- **WHEN** helper 運行 30 秒後崩潰
- **THEN** 退避 SHALL 不被重置

### Requirement: 卡死判定
卡死閾值 MUST 至少為心跳間隔的 3 倍（心跳至少每 30 秒，故閾值至少 90 秒）。**任何 stdout 輸出（含半行位元組）都算活著**並重置計時。判定卡死時 MUST 終止該 generation 行程並依退避重啟。

#### Scenario: 無輸出逾時
- **WHEN** 假 helper 啟動後完全無輸出超過閾值
- **THEN** SHALL 判定卡死並重啟

#### Scenario: 只有非心跳輸出
- **WHEN** helper 只輸出 `items` 而無 `status` 且間隔小於閾值
- **THEN** SHALL 不判定卡死

#### Scenario: 半行不是死
- **WHEN** helper 持續輸出無換行位元組
- **THEN** SHALL 視為活著（行長上限由 `LineBuffer` 處理）

### Requirement: 睡眠喚醒寬限
收到 `NSWorkspace.didWakeNotification` 後 MUST 給寬限期（長度【待確認】，暫定重新起算一個完整卡死閾值），寬限期內 MUST NOT 因無輸出而判定卡死，以避免睡眠喚醒與 VPN 重連的誤判（風險 3）。

#### Scenario: 喚醒後
- **WHEN** 系統睡眠 5 分鐘後喚醒
- **THEN** 喚醒後寬限期內 SHALL 不重啟 helper（單元測試以假時鐘與模擬通知驗證；真機睡眠為需人工驗收）

### Requirement: 不可恢復的錯誤不無限重啟
若啟動失敗屬不可恢復（找不到執行檔、無執行權限、簽名失敗被系統拒絕），MUST NOT 無限重啟；MUST 停止重啟並讓 UI 顯示錯誤狀態（呈現方式【待確認】）。完整分類【待確認】；可恢復錯誤（網路、helper 崩潰）依退避重啟。

#### Scenario: 執行檔缺失
- **WHEN** helper 路徑不存在
- **THEN** SHALL 回報不可恢復錯誤且嘗試啟動次數 SHALL 為 1

#### Scenario: 無執行權限
- **WHEN** 假 helper 檔案無 +x
- **THEN** SHALL 回報不可恢復錯誤，不進入退避迴圈

### Requirement: App 正常結束流程
App 正常結束時 MUST 關閉 helper 的 stdin（觸發其 EOF 退出），等待短暫逾時（長度【待確認】，暫定 2 秒）仍未結束則送 SIGTERM。

#### Scenario: helper 配合
- **WHEN** 關閉 stdin
- **THEN** helper SHALL 在逾時內結束且不送 SIGTERM

#### Scenario: helper 不配合
- **WHEN** 假 helper 忽略 stdin EOF
- **THEN** 逾時後 SHALL 收到 SIGTERM

### Requirement: 雙實例窗口
為處理 App 被 `kill -9` 或快速重啟時舊 helper 尚未退出的窗口，MUST 使用 lock／pid file（位置【待確認】）：新 App 啟動 helper 前，若 pid file 指向仍存活的舊 helper，MUST 先終止它（或等待其退出）再啟動；同一時刻 MUST NOT 有兩個 helper 同時輪詢。

#### Scenario: 快速重啟
- **WHEN** `kill -9` App 後立即重啟
- **THEN** 數秒內 SHALL 只剩一個 helper 行程（`pgrep ticker-connect` 計數為 1）

### Requirement: 資料落地
`FeedClient` 解出的 `snapshot`／`items`／`status` MUST 以 Core 型別交給排程層；單行解析失敗 MUST 不終止串流（沿用 `LineBuffer` 與解碼器行為）。

#### Scenario: 半行與壞行
- **WHEN** 假 helper 輸出半行後再補完、中間夾一行壞 JSON
- **THEN** 完整行 SHALL 被正確交付，壞行 SHALL 被記錄並略過
