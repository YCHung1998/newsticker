# contract-fixtures Specification

## Purpose
TBD - created by archiving change message-contract. Update Purpose after archive.
## Requirements
### Requirement: 協定檔案配置
`protocol/` 目錄 SHALL 含：訊息 schema（涵蓋 `snapshot`、`items`、`status` 與共用 `item`）、`fixtures/` 目錄、`fixtures/manifest.json`，以及參考驗證測試。schema 所用的 JSON Schema 草案版本 MUST 在 schema 內以 `$schema` 明示，採 JSON Schema 2020-12（`https://json-schema.org/draft/2020-12/schema`）【已決定 2026-10-24：已向官方頁面查證 2020-12 是目前最新已發布版本】。

#### Scenario: schema 自我宣告版本
- **WHEN** 檢查任一 schema 檔
- **THEN** 該檔 SHALL 含 `$schema` 欄位，且能被所選草案的 meta-schema 驗證為合法 schema

### Requirement: fixtures 涵蓋合法與非法樣本
`protocol/fixtures/` SHALL 提供合法樣本與非法樣本，每個樣本是一行 JSON（或可程式化產生的單行）。合法樣本 MUST 至少涵蓋：`snapshot`（多筆、新到舊）、`items`（多筆、舊到新）、`status` 的 `ok` 與 `error`、CJK 文字、含 JSON 跳脫字元的文字、`published_at_ms` 的典型值。非法樣本 MUST 至少涵蓋：缺少 `v`、缺少 `type`、未知 `type`、不支援的 `v`、item 缺欄位、欄位型別錯誤、`state` 非法值、空 `items`、空字串 `text`、`item` 額外欄位、非 UTF-8、順序違規（snapshot 升冪、items 降冪）、`items` 混有非法 item、非 JSON 文字、超過 1MB 的行、恰為上限（1,048,576 位元組）的行（合法邊界）。超過上限的樣本 MAY 由測試程式產生而不存實體檔，以避免倉庫膨脹。

#### Scenario: 樣本覆蓋清單完整
- **WHEN** 契約測試讀取 manifest
- **THEN** manifest SHALL 包含上述每一類合法與非法樣本，缺任一類則測試失敗

### Requirement: manifest 描述預期結果
`fixtures/manifest.json` SHALL 為每個樣本記錄：樣本識別名、檔案路徑或產生方式、預期結果（`accept` 或 `reject`）、以及拒絕時的原因類別（至少區分：`not_json`、`schema`、`version`、`oversize`、`order`）。兩端的契約測試 MUST 以 manifest 為唯一的預期來源，不得在各自程式碼中另行硬編預期。

#### Scenario: 預期結果可被機器讀取
- **WHEN** 任一端的測試載入 manifest
- **THEN** 每個樣本 SHALL 有明確的 `accept` 或 `reject`，`reject` 者 SHALL 帶有原因類別

#### Scenario: 樣本與 manifest 不一致
- **WHEN** fixtures 目錄中存在 manifest 未列出的樣本，或 manifest 列出不存在的樣本
- **THEN** 契約測試 SHALL 失敗

### Requirement: 參考驗證器證明契約自洽
本 change SHALL 提供一個參考驗證測試，以標準 JSON Schema 驗證器對所有 fixtures 執行，結果 MUST 與 manifest 的預期一致。順序語意（snapshot 新到舊、items 舊到新）與大小上限、非 UTF-8／非 JSON 檢查非 JSON Schema 能表達者，參考測試 MUST 以額外的明確檢查補足，並同樣以 manifest 為預期。

#### Scenario: 所有樣本與預期一致
- **WHEN** 執行參考驗證測試
- **THEN** 每個 `accept` 樣本 SHALL 通過、每個 `reject` 樣本 SHALL 被拒絕且原因類別相符

#### Scenario: 順序違規被抓到
- **WHEN** 一個 `snapshot` 樣本的 `published_at_ms` 由小到大排列
- **THEN** 參考測試 SHALL 將其判為 reject（原因類別為 `order`）【已決定 2026-10-24：順序違規一律拒絕，不是警告】

### Requirement: 兩端共用同一批 fixtures
Rust（`connect-engine-fastbull`）與 Swift（`show-engine-core`）的後續 change SHALL 直接讀取 `protocol/fixtures/` 與 manifest，不得複製出各自的副本。本 change 不實作 Rust 或 Swift 程式，但 MUST 在文件中寫明兩端的接入方式：Rust 端以 schema 驗證輸出（發送端角色）、Swift 端以 Codable 解碼加手寫檢查驗證輸入（接收端角色）。

#### Scenario: 接入方式有文件
- **WHEN** 閱讀 `protocol/` 的說明文件
- **THEN** SHALL 能找到兩端如何載入 manifest、如何對應原因類別的說明

### Requirement: 契約變更需 fail-then-pass 證據
任何對 schema 或 fixtures 的邏輯變更，SHALL 先新增或調整 fixture 使參考測試失敗，再修改 schema 使其通過，並記錄兩次執行的指令與結果。沒有此證據時只能宣稱「已修改、未驗證」。

#### Scenario: 新增規則時先有失敗證據
- **WHEN** 為新規則（例如拒絕空 `items`）修改 schema
- **THEN** 變更紀錄 SHALL 包含「新增非法樣本後測試失敗」與「修改 schema 後測試通過」的指令輸出

