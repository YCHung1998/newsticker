# protocol-decoding Specification

## Purpose
TBD - created by archiving change show-engine-core. Update Purpose after archive.
## Requirements
### Requirement: 協定 Codable 型別
Core SHALL 提供對應 `message-contract` 的型別：`item`（`source`、`id` 為字串，`published_at_ms` 為整數 UTC 毫秒，`text` 為字串，選填 `url` 為字串或 `nil`，`nil` 表示無連結）、`snapshot`／`items`（含 `items` 陣列）、`status`（`source`、`state` 為 `ok`／`error`、`message`）。型別 MUST NOT 含「重要」旗標。欄位名稱、型別與值域 SHALL 與 `protocol/` 的 JSON Schema 一致；兩者不一致時以 schema 與 manifest 為準，不得在 Swift 端另行發明。

#### Scenario: 解碼合法 snapshot
- **WHEN** 解碼一行合法 `snapshot` JSON
- **THEN** SHALL 得到 snapshot 值，`items` 順序與輸入相同

#### Scenario: 解碼合法 status
- **WHEN** 解碼 `state` 為 `error` 的合法 `status`
- **THEN** SHALL 得到 status 值且 `state` 為 error

#### Scenario: 解碼含 url 的 item
- **WHEN** 解碼一行含 `url` 的合法 `items` JSON
- **THEN** 該 item 的 `url` SHALL 等於輸入字串

#### Scenario: 解碼不含 url 的 item
- **WHEN** 解碼一行不含 `url` 的合法 `items` JSON
- **THEN** 該 item 的 `url` SHALL 為 `nil`，且 `Item` 的既有四欄位值不受影響

### Requirement: 單行解碼器與錯誤分類
Core SHALL 提供單行解碼函式：輸入一行位元組（不含結尾換行），輸出已解碼訊息或錯誤。錯誤類別 MUST 與 `message-contract` manifest 的原因類別一一對應，至少含 `not_json`（含非 UTF-8）、`schema`、`version`、`oversize`；另有 `order` 類別（順序違規：`snapshot` 的 `published_at_ms` 非遞增、`items` 非遞減，相鄰相等視為合法）【已決定 2026-10-24，以 `protocol/` 已實作內容為準】。判定順序依 `protocol/README.md`：oversize → not_json → version → schema → order。單行錯誤 MUST NOT 以丟出會終止串流的方式處理（回傳錯誤值，由呼叫端決定記錄並繼續）。

#### Scenario: 非 JSON
- **WHEN** 輸入為 `not json at all`
- **THEN** 解碼器 SHALL 回傳 `not_json` 類別錯誤

#### Scenario: 非 UTF-8 位元組
- **WHEN** 輸入含無效 UTF-8 序列
- **THEN** 解碼器 SHALL 回傳 `not_json` 類別錯誤【已決定 2026-10-24：manifest 的 `reasons` 無獨立的非 UTF-8 類別，樣本 `non-utf8` 預期為 `not_json`】

#### Scenario: 不支援的版本
- **WHEN** 輸入為語法與其餘結構合法、但 `v` 為 `2` 的訊息
- **THEN** 解碼器 SHALL 回傳 `version` 類別錯誤，且 SHALL NOT 嘗試解讀其餘欄位

### Requirement: 嚴格性由 message-contract 決定
Swift 預設的 Codable 會忽略未知欄位並接受空陣列，因此下列行為 MUST 以手寫檢查補足，並完全跟隨 `message-contract` 的決定，而非 Swift 預設【已決定 2026-10-24】：(a) `item` 或訊息含未定義額外欄位 MUST 拒絕（`schema`）；(b) 空 `items` 非法（`schema`）；(c) `text` 不得為空字串（`schema`）；(d) `status.message` 在 `ok` 時可為空；(e) `id` 為數字、`published_at_ms` 為字串／浮點數／負數時拒絕；(f) `url`（選填）：缺少合法、`null`／非字串／空字串／超過 2048 位元組／不以 `http://` 或 `https://` 開頭（含主機首字元為英數字或 `[`）／含 `0x21`–`0x7E` 以外的位元組（含結尾換行）一律拒絕（`schema`），規則逐項與 `message-protocol` 的 `item 結構` 及 `protocol/` schema 相同。接收端「整則所有 item 都合法才接受，任一非法整則非法」；發送端（Rust helper）負責先過濾不合格 item 並另發 `status`（`state: error`）警告，因此 Core 不需處理混有非法 item 的容錯。(a)–(d) 與 (f) 的值 MUST 集中在單一位置（`ProtocolRules`，`url` 的上限與允許 scheme 為其中的常數與單一驗證函式），manifest 為唯一預期來源。

#### Scenario: items 混有非法 item
- **WHEN** `items` 訊息含兩個合法 item 與一個缺少 `id` 的 item
- **THEN** 解碼器 SHALL 整則回傳 `schema` 類別錯誤，不得回傳其中合法的部分

#### Scenario: id 為數字
- **WHEN** 某 item 的 `id` 的 JSON 型別是數字
- **THEN** 解碼器 SHALL 回傳 `schema` 類別錯誤

#### Scenario: 空 items
- **WHEN** `items` 訊息的 `items` 為空陣列
- **THEN** 解碼器 SHALL 回傳 `schema` 類別錯誤【已決定 2026-10-24；與 manifest 樣本 `items-empty-items`、`snapshot-empty-items` 一致】

#### Scenario: url 規則與契約一致
- **WHEN** 對 manifest 中所有含 `url` 的合法與非法樣本執行解碼
- **THEN** 合法樣本 SHALL 成功且 `url` 值逐字保留；非法樣本 SHALL 回傳 `schema` 類別錯誤

#### Scenario: url 為結尾換行
- **WHEN** 某 item 的 `url` 為 `"https://example.com/\n"`（JSON 跳脫的換行）
- **THEN** 解碼器 SHALL 回傳 `schema` 類別錯誤

#### Scenario: url 非法使整則被拒
- **WHEN** `items` 訊息含兩個合法 item 與一個 `url` 為 `javascript:alert(1)` 的 item
- **THEN** 解碼器 SHALL 整則回傳 `schema` 類別錯誤，不得回傳其中合法的部分

### Requirement: 以 message-contract 的 fixtures 做契約測試
契約測試 SHALL 直接讀取倉庫 `protocol/fixtures/` 與 `protocol/fixtures/manifest.json`（唯讀，不得複製副本到 Swift 目錄、不得複製入 Swift 資源 bundle），對 manifest 中每個樣本執行解碼，結果 MUST 與 manifest 預期一致：`accept` 者成功解碼，`reject` 者失敗且原因類別相符。測試 MUST 檢查 manifest 列出的樣本都被執行（不得因找不到檔案而靜默略過）。manifest 欄位【已決定 2026-10-24，以 `protocol/fixtures/manifest.json` 實際格式為準】：頂層 `manifest_version`、`max_line_bytes`、`reasons`、`samples[]`；樣本含 `name`、`expect`（`accept`／`reject`）、`reason`（reject 時必有）、`covers`，以及 `file`（相對 `fixtures/`，內容恰一行）或 `generate`（`kind: padded_items`、`total_bytes` 為 `limit` 或 `limit+1`，產生合法 `items` 並以 ASCII `text` 補到恰好該位元組數）。契約測試 MUST 由 `message-contract` 已 apply 為前提；其 fixtures 路徑由測試以來源檔位置往上尋找 `protocol/` 目錄取得【假設：測試以 `#filePath` 定位倉庫根目錄】。

#### Scenario: 所有合法樣本可解碼
- **WHEN** 執行契約測試
- **THEN** manifest 中每個 `accept` 樣本 SHALL 成功解碼

#### Scenario: 所有非法樣本被拒絕且分類相符
- **WHEN** 執行契約測試
- **THEN** manifest 中每個 `reject` 樣本 SHALL 失敗，且錯誤類別與 manifest 記錄的原因類別相同

#### Scenario: 找不到 fixtures
- **WHEN** 倉庫中找不到 `protocol/fixtures/manifest.json`
- **THEN** 契約測試 SHALL 失敗並指出缺少檔案，而非通過

#### Scenario: manifest 與目錄不一致
- **WHEN** manifest 列出不存在的樣本，或目錄中有 manifest 未列出的樣本
- **THEN** 契約測試 SHALL 失敗

