## MODIFIED Requirements

### Requirement: 遵守 message-contract 協定
`ticker-connect` 輸出的每一行 MUST 符合 `message-contract` change 定義的協定（`snapshot`、`items`、`status`、`item` 欄位、`v`、單行 1MB 上限）。引擎 SHALL NOT 自行新增、修改或擴充任何協定欄位或訊息類型（協定欄位以 `protocol/` 為準；選填欄位 `url` 已由 change `ticker-navigation-link` 納入契約，引擎 MUST 原樣序列化 `Item.url`，不得改寫其值）；若引擎需要協定未提供的資訊，MUST 列入 `design.md` 的待釐清而非自行擴充。引擎的契約測試 MUST 直接讀取 `protocol/fixtures/` 與 `manifest.json`，不得複製副本。

#### Scenario: 輸出通過契約 fixtures 的驗證
- **WHEN** 引擎的 emitter 以 `protocol/` 的 schema 驗證其輸出
- **THEN** emitter 對 manifest 中每個 `accept` 樣本 SHALL 判為可輸出，對每個 `reject` 樣本 SHALL 判為不可輸出

#### Scenario: 需要協定沒有的欄位
- **WHEN** 實作中發現需要 `message-contract` 未定義的欄位或訊息類型
- **THEN** 該需求 SHALL 被記入待釐清，且引擎的輸出 SHALL NOT 包含該欄位

#### Scenario: url 原樣輸出
- **WHEN** 假 Connector 回傳含 `url` 的 item
- **THEN** 引擎輸出的 `snapshot`／`items` 中該 item SHALL 含相同的 `url`，且整行 SHALL 通過 `protocol/` schema

#### Scenario: 不含 url 的 item 不輸出 url 欄位
- **WHEN** 假 Connector 回傳不含 `url` 的 item
- **THEN** 輸出的 JSON SHALL 不含 `url` 鍵（不得輸出 `null`）

