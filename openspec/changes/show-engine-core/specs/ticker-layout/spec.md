## ADDED Requirements

### Requirement: 寬度由注入的 measurer 提供
版面計算 SHALL 透過注入的 measurer（輸入字串，輸出寬度，單位與 tape 座標相同）取得文字寬度；Core MUST NOT 自行使用任何字型或文字量測 API，也 MUST NOT 以字元數推算寬度。測試 SHALL 使用假 measurer（例如每個字元固定寬度、CJK 字元加倍）。

#### Scenario: 寬度來自 measurer
- **WHEN** 假 measurer 對任何字串回傳其字元數乘以 10
- **THEN** 一則未被截斷的訊息的 `width` SHALL 等於 measurer 對該訊息顯示字串的回傳值

### Requirement: 以量測寬度截斷並加「…」
單則訊息顯示字串的量測寬度超過最大寬度時，系統 SHALL 截斷 `text` 並在尾端加「…」，使最終顯示字串的量測寬度不超過最大寬度；MUST 在保留最多文字的前提下截斷（取最長的可行前綴）。截斷以量測寬度為準，不得以字元數為準【假設 A8，使用者尚未確認】。截斷單位 SHALL 為 Character（grapheme cluster），不得切斷 emoji 或組合字元。最大寬度由設定參數 `maxItemWidth` 注入【已決定 2026-10-24：做成注入參數；預設值 600（與 `viewportWidth` 預設 620 同量級）為【假設】常數，未經使用者確認，`app-shell` 可依實際視窗覆寫】。時間字串不被截斷。需截斷與不需截斷的訊息 SHALL 在輸出中以旗標區分。

#### Scenario: 不需截斷
- **WHEN** 顯示字串量測寬度小於等於最大寬度
- **THEN** 輸出的 `text` SHALL 與輸入相同，截斷旗標為 false

#### Scenario: 需截斷
- **WHEN** 顯示字串量測寬度大於最大寬度
- **THEN** 輸出的 `text` SHALL 以「…」結尾，其顯示字串量測寬度 SHALL 小於等於最大寬度，且再多保留一個 Character 就會超過最大寬度

#### Scenario: CJK 與拉丁字元寬度不同
- **WHEN** 同樣 20 個字元的 CJK 文字與拉丁文字在同一最大寬度下，假 measurer 對 CJK 回傳雙倍寬度
- **THEN** 兩者保留的字元數 SHALL 不同，證明截斷依量測寬度而非字元數

#### Scenario: 連「…」都放不下
- **WHEN** 最大寬度小於只含時間字串加「…」的寬度
- **THEN** 系統 SHALL 輸出僅含時間字串與「…」的結果且不崩潰【假設：此極端情況設計文件未規定，由本規格暫定】

### Requirement: 時間字串格式與時區注入
每則訊息的時間字串 SHALL 為由 `published_at_ms` 轉換、以注入的時區表示的 24 小時制 `HH:mm:ss`【假設 A4：本機時區；時區由注入提供以便測試】。格式化 MUST 不隨系統語系或 12/24 小時設定改變。顯示字串（供 measurer 量測）為「時間字串、一個空白、`text`」【假設：設計文件僅以 `16:56:41 沙烏地…` 為例（TASKS-feed-and-modes.md A4），未明定分隔】。即時（LIVE）與重播（REPLAY）兩種樣式的文字都含時間字串【已決定 2026-10-24：使用者要求「自動拿到有時間的即時訊息」，即時訊息也顯示時間】；兩種樣式皆以含時間的顯示字串量測。

#### Scenario: UTC+8 格式化
- **WHEN** 以 UTC+8 時區格式化 `published_at_ms = 1792832201957`
- **THEN** 結果 SHALL 為 `16:56:41`

#### Scenario: 不同時區
- **WHEN** 以 UTC 時區格式化同一值
- **THEN** 結果 SHALL 為 `08:56:41`

#### Scenario: 補零與跨午夜
- **WHEN** 時間為當地 `00:05:09`
- **THEN** 結果 SHALL 為 `00:05:09`（時、分、秒皆補零，不是 `0:5:9` 或 `12:05:09`）
