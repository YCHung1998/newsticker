## ADDED Requirements

### Requirement: 來源清單檔的格式
App SHALL 使用 `~/Library/Application Support/FastBullTicker/sources.json`（可由環境變數 `FASTBULL_TICKER_SOURCES`【假設名稱，測試用】覆寫路徑）記錄來源。內容為 JSON 物件：`version`（整數，目前 `1`）、`selected`（字串，上次選的來源 `id`）、`sources`（陣列，順序即選單順序）。每筆含必填 `id`（小寫字母開頭、小寫英數與底線、2–32 字元，與 helper 登錄的來源 id 同規則）與 `name`（顯示名稱，修剪後 1–24 字）、選填 `label`（左側標籤文字，修剪後 1–16 字，規則同 `style.json` 的 `labelText`）。`id` 重複時 SHALL 只保留第一筆。未知鍵 SHALL 被忽略並寫日誌警告。

#### Scenario: 合法檔案
- **WHEN** 檔案含 `selected: "jin10"` 與兩筆合法來源
- **THEN** 讀入後清單有兩筆且順序與檔案相同

#### Scenario: 重複 id
- **WHEN** 兩筆來源的 `id` 相同
- **THEN** 只保留第一筆，日誌記一行警告

#### Scenario: 單筆非法
- **WHEN** 某筆缺少 `name` 或 `id` 不合規則
- **THEN** 該筆被略過並寫日誌，其餘照常載入

### Requirement: 預設內容與自動建立
檔案不存在時，App SHALL 以預設內容建立它：`selected` 為 `fastbull`，清單含 `fastbull`（`name`「FastBull 快訊」，`label`「即時財經快訊」）與 `jin10`（`name`「金十數據」，`label`「金十數據」）。寫入 MUST 為原子（暫存檔後取代）。無法建立（唯讀、權限）時 App MUST 仍可使用記憶體中的預設清單，並寫日誌，不得崩潰。

#### Scenario: 第一次啟動
- **WHEN** 檔案不存在
- **THEN** 啟動後檔案存在，內容為預設，且目前來源為 `fastbull`

#### Scenario: 無法寫入
- **WHEN** 目錄不可寫
- **THEN** App 正常運作，選單仍可切換（本次執行有效），日誌有一行錯誤

### Requirement: 檔案損毀時的容錯
檔案不是合法 JSON、或沒有任何合法來源時，App MUST 退回預設清單、MUST NOT 覆寫使用者的檔案（先複製為 `sources.json.bak` 再以預設取代，與 `style.json` 的處理一致），並在選單顯示提示行。

#### Scenario: 損毀
- **WHEN** 檔案內容是 `{ oops`
- **THEN** 使用預設清單，原檔被備份為 `sources.json.bak`，選單有提示

### Requirement: 記住上次選擇
切換來源後，App SHALL 把新的 `selected` 寫回檔案（保留其他來源的順序、名稱與標籤）。`selected` 指向不存在或停用的來源時，啟動 SHALL 退回 `fastbull`（不修改檔案）。

#### Scenario: 切換後重開
- **WHEN** 使用者切到 `jin10` 後結束再啟動（未設環境變數）
- **THEN** 啟動時使用 `jin10`

#### Scenario: selected 指向不存在的來源
- **WHEN** `selected` 為 `nope`
- **THEN** 啟動使用 `fastbull`，檔案內容不變
