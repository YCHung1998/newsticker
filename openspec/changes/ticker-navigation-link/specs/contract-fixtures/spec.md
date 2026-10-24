## MODIFIED Requirements

### Requirement: fixtures 涵蓋合法與非法樣本
`protocol/fixtures/` SHALL 提供合法樣本與非法樣本，每個樣本是一行 JSON（或可程式化產生的單行）。合法樣本 MUST 至少涵蓋：含 `url` 的 `items` 與 `snapshot`（至少各一）、有 `url` 與無 `url` 的 item 混合於同一則訊息、`url` 恰為上限 2048 位元組（以實體檔存放，約 2KB，不使用 `generate`）、`snapshot`（多筆、新到舊）、`items`（多筆、舊到新）、`status` 的 `ok` 與 `error`、CJK 文字、含 JSON 跳脫字元的文字、`published_at_ms` 的典型值。非法樣本 MUST 至少涵蓋：`url` 非 http(s)（`javascript:`、`ftp:` 各一）、`url` 為空字串、`url` 為 2049 位元組、`url` 為 `null`、`url` 為數字、`url` 為相對路徑、`url` 含空白、`url` 含結尾換行、缺少 `v`、缺少 `type`、未知 `type`、不支援的 `v`、item 缺欄位、欄位型別錯誤、`state` 非法值、空 `items`、空字串 `text`、`item` 額外欄位、非 UTF-8、順序違規（snapshot 升冪、items 降冪）、`items` 混有非法 item、非 JSON 文字、超過 1MB 的行、恰為上限（1,048,576 位元組）的行（合法邊界）。超過上限的樣本 MAY 由測試程式產生而不存實體檔，以避免倉庫膨脹。

#### Scenario: 樣本覆蓋清單完整
- **WHEN** 契約測試讀取 manifest
- **THEN** manifest SHALL 包含上述每一類合法與非法樣本，缺任一類則測試失敗

#### Scenario: url 樣本覆蓋完整
- **WHEN** 契約測試讀取 manifest
- **THEN** manifest SHALL 含上述每一類 `url` 合法與非法樣本，缺任一類則測試失敗；既有不含 `url` 的合法樣本 SHALL 全數保留且仍為 `accept`

