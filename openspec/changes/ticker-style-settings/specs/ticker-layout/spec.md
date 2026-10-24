## MODIFIED Requirements

### Requirement: 時間字串格式與時區注入
每則訊息的時間字串 SHALL 為由 `published_at_ms` 轉換、以注入的時區表示的 24 小時制 `HH:mm:ss`【假設 A4：本機時區；時區由注入提供以便測試】。格式化 MUST 不隨系統語系或 12/24 小時設定改變。預設（`showTime` 為 true）的顯示字串（供 measurer 量測）為「時間字串、一個空白、`text`」【假設：設計文件僅以 `16:56:41 沙烏地…` 為例（TASKS-feed-and-modes.md A4），未明定分隔】。即時（LIVE）與重播（REPLAY）兩種樣式的文字都含時間字串【已決定 2026-10-24：使用者要求「自動拿到有時間的即時訊息」，即時訊息也顯示時間】；兩種樣式皆以含時間的顯示字串量測。`showTime` 設定（`SchedulerConfig.showTime`，預設 true，由 `TickerStyle.showTime` 提供）為 false 時，顯示字串 MUST 僅為 `text`（不含時間字串與分隔空白），`ItemLayout.timeString` 與 `PlacedItem.timeString` 為空字串，量測與截斷以此顯示字串為準；預設行為與上述完全相同，不改變已決定的「兩種樣式都含時間」【假設：把使用者「文字內容可調」的回饋詮釋為可關閉時間，使用者尚未確認】。

#### Scenario: UTC+8 格式化
- **WHEN** 以 UTC+8 時區格式化 `published_at_ms = 1792832201957`
- **THEN** 結果 SHALL 為 `16:56:41`

#### Scenario: 不同時區
- **WHEN** 以 UTC 時區格式化同一值
- **THEN** 結果 SHALL 為 `08:56:41`

#### Scenario: 補零與跨午夜
- **WHEN** 時間為當地 `00:05:09`
- **THEN** 結果 SHALL 為 `00:05:09`（時、分、秒皆補零，不是 `0:5:9` 或 `12:05:09`）

#### Scenario: 關閉時間
- **WHEN** `showTime` 為 false，對 `published_at_ms = 1792832201957` 且 `text` 為 `T` 的訊息做版面計算
- **THEN** 顯示字串 SHALL 為 `T`，`timeString` SHALL 為空字串，`width` SHALL 等於 measurer 對 `T` 的回傳值（未被截斷時）

#### Scenario: 預設含時間
- **WHEN** 未設定 `showTime`（預設 true）
- **THEN** 輸出 SHALL 與本 change 之前完全相同（顯示字串為時間、空白、`text`）

#### Scenario: 關閉時間時的截斷
- **WHEN** `showTime` 為 false 且 `text` 量測寬度超過最大寬度
- **THEN** 截斷結果 SHALL 為不含時間的最長可行前綴加「…」，量測寬度 SHALL 小於等於最大寬度

