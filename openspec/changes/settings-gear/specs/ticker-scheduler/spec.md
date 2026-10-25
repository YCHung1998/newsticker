## ADDED Requirements

依賴：「執行期重新設定」與 `SchedulerTunables` 目前存在於進行中的 change `ticker-style-settings`（`specs/ticker-scheduler/spec.md`），尚未同步到主 specs；本 requirement 在其之上增加第七個欄位，故以 ADDED 提出。

### Requirement: seekHoldSeconds 可於執行期調整
`SchedulerTunables` SHALL 新增第七個欄位 `seekHoldSeconds`（秒，`>= 0`），`SchedulerTunables.init(config:)` MUST 帶入目前的 `config.seekHoldSeconds`；`reconfigure` MUST 把 `config.seekHoldSeconds` 更新為該值，且 MUST NOT 改動進行中的 `holdRemaining`（目前已在保持中的暫停依原剩餘秒數期滿，下一次成功 `seek` 才使用新值）。`reconfigure` 的前置條件增加 `seekHoldSeconds >= 0`（呼叫端先夾制）。既有的其他不變量（速度保持視覺連續、已排入訊息不變、隱藏／指標停留／即時佇列／歷史／模式不受影響）MUST 維持。`SchedulerTunables` 的欄位 MUST 恰為 `speed`、`viewportWidth`、`maxItemWidth`、`replayCount`、`showTime`、`timeZone`、`seekHoldSeconds`。

#### Scenario: 之後的 seek 使用新值
- **WHEN** `seekHoldSeconds` 預設為 1，呼叫 `reconfigure` 將其改為 5，然後 `seek(.next)` 成功
- **THEN** `holdRemaining` SHALL 為 5

#### Scenario: 進行中的保持不變
- **WHEN** seek 成功後保持剩餘 1 秒，此時 `reconfigure` 將 `seekHoldSeconds` 改為 5
- **THEN** `holdRemaining` SHALL 仍為 1；期滿後 SHALL 從原位置接著捲動、無跳動

#### Scenario: 不改 seekHoldSeconds 時行為不變
- **WHEN** 以 `SchedulerTunables(config:)` 只改 `speed` 後 `reconfigure`
- **THEN** `config.seekHoldSeconds` SHALL 保持原值

#### Scenario: 欄位清單
- **WHEN** 檢查 `SchedulerTunables` 的欄位
- **THEN** SHALL 恰為上述七個，不含 `gap`、`liveQueueLimit`、`historyLimit`、`rebaseThreshold`
