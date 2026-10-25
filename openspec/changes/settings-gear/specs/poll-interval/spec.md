## ADDED Requirements

依賴：`app-shell` 的 `feed-client`（進行中；`FeedClient` 已在程式中實作）、`connector-engine`「第一次成功輪詢發 snapshot」（主 specs）、Core 的 `TickerScheduler.receive(.snapshot)`（主 specs `ticker-scheduler`「REPLAY／LIVE 狀態機」）。

### Requirement: helper 輪詢間隔參數
App MUST 以 helper 既有的 `--interval-ms N` 參數傳遞輪詢間隔：`FeedClientConfig.helperArguments(pollIntervalSeconds:)` 為純函式，間隔為預設的 10 秒時 MUST 回傳空陣列（命令列與加入本設定之前完全相同），其他值 MUST 回傳 `["--interval-ms", "<秒 × 1000>"]`（例如 30 → `["--interval-ms", "30000"]`）。啟動時 `FeedClientConfig.arguments` MUST 由載入的 `TickerStyle.pollIntervalSeconds` 計算。App MUST NOT 提供 10、30、60 以外的值（5 秒未實測，`fastbull-connector` 已規定在實測前不得宣稱可降到 5 秒）。

#### Scenario: 預設不帶參數
- **WHEN** `pollIntervalSeconds` 為 10
- **THEN** `helperArguments` SHALL 為 `[]`

#### Scenario: 30 與 60
- **WHEN** `pollIntervalSeconds` 為 30、60
- **THEN** `helperArguments` SHALL 依序為 `["--interval-ms", "30000"]`、`["--interval-ms", "60000"]`

#### Scenario: 啟動套用
- **WHEN** 載入的樣式 `pollIntervalSeconds` 為 60 並啟動 helper
- **THEN** helper 的命令列參數 SHALL 為 `--interval-ms 60000`（以假 helper 腳本記錄參數驗證）

### Requirement: 輪詢間隔變更時計畫性重啟 helper
`FeedClient` SHALL 提供 `reconfigure(arguments:)`。語意：(1) 新參數與目前相同 MUST 為 no-op；(2) helper 執行中：MUST 以與 `shutdown` 相同的優雅方式結束目前 helper（關閉 stdin；`terminateTimeout` 後 SIGTERM；再逾時 SIGKILL），該 generation 結束後 MUST 立即以新參數啟動新的 helper，且此次結束 MUST NOT 進入退避、MUST NOT 改變退避狀態（計畫性重啟不是崩潰）；對外事件為 `.exited(generation:, status:, restartIn: 0)` 後接 `.started`；(3) 重啟進行中再次呼叫 MUST 只更新參數（合併，不產生額外重啟）；(4) 退避等待中、`idle`、`failed`、`stopped`：只更新參數，下一次啟動使用新參數；(5) 已進入 `shutdown`（`stopping`）後 MUST 忽略；(6) 重啟 MUST 不留下孤兒 helper（沿用 pid file 與 generation token 機制），舊 generation 的延遲輸出 MUST 被忽略。重啟期間 Core／渲染 MUST 不被觸碰：帶子持續捲動，已排入與即時佇列中的訊息不受影響。

#### Scenario: 重啟並帶新參數
- **WHEN** helper 執行中呼叫 `reconfigure(arguments: ["--interval-ms", "30000"])`
- **THEN** 舊 helper SHALL 結束、新 helper SHALL 以該參數啟動（`startedCount` 為 2、pid 不同），且 SHALL 無 `.exited` 事件帶有大於 0 的 `restartIn`

#### Scenario: 不進退避
- **WHEN** 計畫性重啟連續進行兩次
- **THEN** 退避延遲 SHALL 不累計（之後一次真正崩潰的 `restartIn` SHALL 仍是退避序列第一階）

#### Scenario: 相同參數不重啟
- **WHEN** 以目前參數呼叫 `reconfigure`
- **THEN** SHALL 不重啟（`startedCount` 不變）

#### Scenario: 重啟進行中再次呼叫
- **WHEN** 舊 helper 忽略 stdin EOF、重啟尚未完成時又以另一組參數呼叫 `reconfigure`
- **THEN** 最終只 SHALL 再啟動一個新 helper，且其參數 SHALL 為最後一次呼叫的值

#### Scenario: 退避中與已結束
- **WHEN** helper 崩潰後處於退避等待時呼叫 `reconfigure`，或 `shutdown` 之後呼叫
- **THEN** 前者 SHALL 在下一次啟動時使用新參數且不額外啟動；後者 SHALL 無任何效果

#### Scenario: 忽略 EOF 的 helper
- **WHEN** 舊 helper 忽略 stdin EOF
- **THEN** SHALL 在 `terminateTimeout` 後以 SIGTERM 結束並啟動新 helper，不留下孤兒行程

### Requirement: 重啟後 snapshot 重送不誤觸即時模式
新 helper 的第一次成功輪詢必送 `snapshot`，所以每次計畫性重啟後 Core 都會再收到一次中途 snapshot。Core MUST 維持：中途 `snapshot` 只取代歷史並設定基準，MUST NOT 變更 `mode`、MUST NOT 清除或改動即時佇列、MUST NOT 移除或重排已排入帶子的訊息、MUST NOT 使 `(n/N)` 的進行中清單總數改變；重發的 snapshot 內已存在的訊息 id 之後再以 `items` 出現時 MUST 視為重複（`duplicatesSkipped`），只有真正不在 snapshot 歷史中的新訊息才進即時佇列並觸發 LIVE。已知取捨【假設】：舊 helper 最後一次輪詢到新 helper 首次輪詢之間出現的新訊息，會直接進入 snapshot 歷史而不以 LIVE 播報；重播清單（`latestItems`）隨新 snapshot 內容更新。

#### Scenario: REPLAY 中重發 snapshot
- **WHEN** 排程器在 REPLAY、帶子上有若干訊息，收到內容與歷史相同的第二次 `snapshot`
- **THEN** `mode` SHALL 仍為 `.replay`、即時佇列 SHALL 為空、`placed` SHALL 不變、事件 SHALL 為空

#### Scenario: LIVE 中重發 snapshot
- **WHEN** 排程器在 LIVE、即時佇列有 2 則，收到第二次 `snapshot`
- **THEN** `mode` SHALL 仍為 `.live`、即時佇列 SHALL 仍為 2 則且順序不變、`placed` SHALL 不變

#### Scenario: snapshot 之後的重複與新訊息
- **WHEN** 重發的 snapshot 含 id 1–10，之後 `items` 先帶 id 10（重複）再帶 id 11（新）
- **THEN** id 10 SHALL 不進即時佇列且回報 `duplicatesSkipped(1)`；id 11 SHALL 進即時佇列並使 `mode` 變為 `.live`

#### Scenario: 整條路徑
- **WHEN** 假 helper 啟動即送 snapshot，`FeedClient` 經 `reconfigure` 重啟後再送一次 snapshot，事件經 `AppCoordinator` 進 `TickerDriver`
- **THEN** `AppCoordinator.snapshots` SHALL 為 2、`modesSeen` SHALL 不含 `.live`、已排入訊息數 SHALL 不減少
