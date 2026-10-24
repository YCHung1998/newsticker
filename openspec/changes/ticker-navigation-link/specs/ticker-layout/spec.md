## ADDED Requirements

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
