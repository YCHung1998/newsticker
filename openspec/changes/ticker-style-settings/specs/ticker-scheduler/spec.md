## ADDED Requirements

### Requirement: 執行期重新設定
排程器 SHALL 提供 `reconfigure(_ tunables: SchedulerTunables, measurer: TextMeasurer)`，供 App 在不重建排程器的情況下套用 `TickerStyle` 的變更。`SchedulerTunables` MUST 僅含可在執行期變更的欄位：`speed`、`viewportWidth`、`maxItemWidth`、`replayCount`、`showTime`、`timeZone`；`gap`、`liveQueueLimit`、`historyLimit`、`rebaseThreshold` 等 MUST NOT 可變更（維持建構時的值）。前置條件與建構時相同（`speed ≥ 0`、`viewportWidth > 0`、`1 ≤ replayCount ≤ historyLimit`），呼叫端 MUST 先夾制。語意：(1) `speed` 改變時 MUST 保持視覺連續：`baseOffset` 調整為 `baseOffset + (舊速度 − 新速度) × tapeTime`，使呼叫前後 `scrollOffset` 相同，之後依新速度前進；(2) 所有已排入訊息的 `tapeX`、`width`、`seq`、樣式、文字 MUST 不變（不重排、不重新量測、不重新截斷）；(3) `viewportWidth`、`maxItemWidth`、`showTime`、`timeZone` 與新的 `measurer` 只影響呼叫之後才排入的訊息；`viewportWidth` 同時影響之後的補料判斷（右緣為 `scrollOffset + viewportWidth`）；(4) `replayCount` 改變時，之後的重播取料使用新的 `latestItems`（歷史最新 N 則）；重播游標以取模處理，MUST NOT 越界或崩潰，進行中的一輪不重排；(5) 保持（hold）、指標停留凍結、隱藏凍結、即時佇列、歷史、模式 MUST 不受影響；(6) 隱藏中呼叫 MUST 合法且不解除凍結。與 `ticker-navigation-link` 相關：該 change 若已 apply，其 `seek`、閱讀位置與 rebase 皆只依賴 `baseOffset` 與 `viewportWidth`，與本操作相容。

#### Scenario: 改速度不跳動
- **WHEN** 速度 90 時跑了 10 秒（`scrollOffset` 為 900），呼叫 `reconfigure` 將速度改為 180，再前進 1 秒
- **THEN** 呼叫當下 `scrollOffset` SHALL 仍為 900，所有訊息視覺位置 SHALL 不變；1 秒後 `scrollOffset` SHALL 為 1080

#### Scenario: 已排入訊息不變
- **WHEN** 已排入若干訊息後呼叫 `reconfigure` 變更 `maxItemWidth`、`showTime`、`measurer`
- **THEN** 既有訊息的 `tapeX`、`width`、`text`、`timeString` SHALL 不變；之後排入的訊息 SHALL 使用新設定，且與前一則的間距 SHALL 仍為 `gap`

#### Scenario: 縮小重播則數
- **WHEN** 重播進行到第 7 則時將 `replayCount` 由 10 改為 5
- **THEN** SHALL 不崩潰、不越界；之後的重播 SHALL 只循環歷史最新 5 則

#### Scenario: 放大可視寬度
- **WHEN** `viewportWidth` 由 470 改為 620
- **THEN** 下一次 `tick()` SHALL 依新右緣補料至尾端超出右緣，間距 SHALL 仍為 `gap`

#### Scenario: 隱藏中重新設定
- **WHEN** 隱藏中呼叫 `reconfigure`
- **THEN** 凍結的 tape 時間 SHALL 不變，恢復後位置 SHALL 不跳動

#### Scenario: 不可變欄位
- **WHEN** 檢查 `SchedulerTunables` 的欄位
- **THEN** SHALL 不含 `gap`、`liveQueueLimit`、`historyLimit`、`rebaseThreshold`

### Requirement: SchedulerConfig 增加 showTime
`SchedulerConfig` SHALL 增加 `showTime`（預設 `true`），語意見 `ticker-layout` 的「時間字串格式與時區注入」。預設值下既有行為與測試 MUST 不變。`layoutItem` 以 `showTime` 參數（預設 true）接收此值。

#### Scenario: 預設不變
- **WHEN** 以預設 `SchedulerConfig` 執行既有的全部 Core 測試
- **THEN** SHALL 全數通過且行為不變

#### Scenario: showTime 為 false 時排入的訊息
- **WHEN** `showTime` 為 false，排入一則訊息
- **THEN** `PlacedItem.timeString` SHALL 為空字串，`text` SHALL 為不含時間的文字
