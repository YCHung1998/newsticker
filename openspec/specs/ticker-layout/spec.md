# ticker-layout Specification

## Purpose
TBD - created by archiving change show-engine-core. Update Purpose after archive.
## Requirements
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

### Requirement: 有連結的訊息保留連結欄位寬度
版面計算 SHALL 接受注入的 `linkSlotWidth`（單位與 tape 座標相同，大於等於 0，預設 0）。當 `item.url` 不為 `nil` 且 `linkSlotWidth` 大於 0 時：截斷預算 MUST 為 `maxWidth − linkSlotWidth`（以含時間之顯示字串量測，截斷規則同「以量測寬度截斷並加『…』」），訊息 `width` MUST 為 `measurer(顯示字串) + linkSlotWidth`，因此總寬不超過 `maxWidth`；`ItemLayout`（與 `PlacedItem`）SHALL 以旗標 `hasLinkSlot` 標示。連結欄位位於訊息最右側，其在訊息本地座標（以訊息左緣為 0）的命中區為 `[width − linkSlotWidth, width)`。無 `url` 或 `linkSlotWidth` 為 0 時，輸出 MUST 與既有行為完全相同（`hasLinkSlot` 為 false）。連結欄位與「…」都放不下的極端情況沿用既有規則（寬度可能超過 `maxWidth`）。迴紋針的實際繪製屬 `ticker-link`。

#### Scenario: 有連結者寬度加欄位
- **WHEN** 假 measurer 回傳字元數乘以 10，`linkSlotWidth` 為 26，某未被截斷且含 `url` 的訊息顯示字串有 20 字元
- **THEN** `width` SHALL 為 226，`hasLinkSlot` SHALL 為 true，命中區 SHALL 為 `[200, 226)`

#### Scenario: 有連結者的截斷預算
- **WHEN** `maxWidth` 為 300、`linkSlotWidth` 為 26，含 `url` 的訊息需要截斷
- **THEN** 截斷後顯示字串的量測寬度 SHALL 小於等於 274，`width` SHALL 小於等於 300

#### Scenario: 無連結者不變
- **WHEN** 訊息不含 `url`，或 `linkSlotWidth` 為 0
- **THEN** 輸出 SHALL 與本 change 之前完全相同，`hasLinkSlot` SHALL 為 false

### Requirement: 時間字串粗體的量測與繪製一致
App 層的 measurer 與繪製 SHALL 對顯示字串開頭的時間字串（`HH:mm:ss`，8 個字元）使用粗體字重，其餘文字（空白與訊息本文）為一般字重【假設：具體粗體字型為 PingFang TC Semibold 或同系列粗體，需人工目視】。measurer MUST 以與繪製完全相同的字型與字重量測（時間部分以粗體量測），使 Core 的 `width` 與預渲染 bitmap 寬度一致；Core 仍只呼叫 `measurer(顯示字串)`，不得知道字重或引入字型 API。是否帶時間前綴由 measurer 以固定格式判斷：字串以 `dd:dd:dd` 加一個空白開頭者，前 8 個字元視為時間字串【假設：時間格式固定為 `HH:mm:ss`，由既有測試保證】；不符者整串以一般字重量測。

#### Scenario: 時間粗體其餘一般
- **WHEN** 對顯示字串 `16:56:41 沙烏地…` 建立繪製用的屬性字串
- **THEN** 前 8 個字元 SHALL 為粗體字重，其餘字元 SHALL 為一般字重（自動測試以屬性區段斷言）

#### Scenario: 量測寬度等於 bitmap 寬度
- **WHEN** 對同一則訊息分別取 measurer 的寬度與預渲染 bitmap 的寬度（pt）
- **THEN** 兩者差 SHALL 不超過 1px（含 `linkSlotWidth` 後仍成立）

#### Scenario: 不帶時間前綴
- **WHEN** 對不以時間格式開頭的字串量測
- **THEN** 整串 SHALL 以一般字重量測

