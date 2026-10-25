## ADDED Requirements

### Requirement: 金十連接器取得並轉換快訊
連接器 `jin10`（`source` 為 `jin10`）SHALL 以 HTTP GET 取得金十快訊 JSON 清單（預設位址 `https://flash-api.jin10.com/get_flash_list?channel=-8200&vip=1`，附網站前端公開常數標頭），並把 `data` 陣列的每個元素轉成一則 `item`（順序為新到舊）：`id` ← 元素 `id`（字串，穩定且來源內唯一）；`published_at_ms` ← `time`（無時區的民用時間字串）以 UTC+8 解讀後的 UTC 毫秒【假設：依網站 config 推定】；`url` ← `data.source_link`（不合格則不輸出 `url`，item 照常輸出）；`text`／`title` 依下一條。`convert` SHALL 為純函式。預設輪詢間隔 MUST 不小於 10 秒。解析出 0 則 MUST 視為錯誤而非「沒有新訊息」。

#### Scenario: 轉換一般快訊
- **WHEN** 元素 `time` 為 `2026-10-25 20:18:06`、`id` 為 `20261025201806546800`
- **THEN** item 的 `id` 為該字串，`published_at_ms` 等於 UTC `2026-10-25T12:18:06Z` 的毫秒值

#### Scenario: source_link 不合格
- **WHEN** `source_link` 含空白或非 http(s)
- **THEN** item 不含 `url` 但仍輸出

#### Scenario: 整頁解析為零則
- **WHEN** 回應不是 JSON 或沒有可用元素
- **THEN** `convert` 回傳解析錯誤

### Requirement: 標題與本文拆分、重要旗標
內文去除 HTML 標籤、解常見實體並收斂空白後，若以 `【…】` 開頭且括號內非空，連接器 SHALL 把括號內文字放入 `title`（不含括號），其後文字放入 `text`；若括號之後沒有本文，則 SHALL 不輸出 `title`，`text` 為完整內容（含括號文字），以維持 `text` 非空。元素的 `important` 為 `1`（或 `true`）時 SHALL 輸出 `"important": true`；其餘情況 MUST 不輸出該欄位。

#### Scenario: 有標題有本文
- **WHEN** 內容為 `【武契奇：以負責任的態度面對選舉結果】金十數據10月25日訊，……`
- **THEN** `title` 為 `武契奇：以負責任的態度面對選舉結果`，`text` 為 `金十數據10月25日訊，……`

#### Scenario: 只有標題
- **WHEN** 內容為 `【某某】` 且沒有後續文字
- **THEN** 不輸出 `title`，`text` 為 `【某某】`

#### Scenario: 重要訊息
- **WHEN** 元素 `important` 為 `1`
- **THEN** item 含 `"important": true`

### Requirement: 略過廣告與無內容元素
連接器 MUST 略過 `extras.ad` 為 `true` 的元素（站內廣告，如 VIP 橫幅）、內容在清理後為空的元素（PLUS 鎖定快訊、純圖片）、缺 `id` 或時間無法解析的元素，並對每個略過寫一行 stderr；其餘元素照常輸出。

#### Scenario: 廣告被略過
- **WHEN** 元素 `extras.ad` 為 `true`
- **THEN** 輸出中不含該元素，stderr 有略過原因

#### Scenario: 鎖定快訊
- **WHEN** 元素內容為空字串
- **THEN** 不輸出該元素，其他元素不受影響

### Requirement: 登錄與選用
`jin10` SHALL 登錄於來源登錄表，`ticker-connect --list-sources` MUST 列出 `fastbull` 與 `jin10`；以 `--source jin10`（App 以環境變數 `FASTBULL_TICKER_SOURCE`【假設名稱，實作時以程式為準】）選用。未指定時預設仍為 `fastbull`。自動測試 MUST 只連本機 `127.0.0.1`。

#### Scenario: 列出來源
- **WHEN** 執行 `ticker-connect --list-sources`
- **THEN** 輸出包含 `fastbull` 與 `jin10`

#### Scenario: 預設不變
- **WHEN** 不帶 `--source`
- **THEN** 行為與本 change 之前相同（fastbull）
