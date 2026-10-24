## ADDED Requirements

### Requirement: 協定 Codable 型別
Core SHALL 提供對應 `message-contract` 的型別：`item`（`source`、`id` 為字串，`published_at_ms` 為整數 UTC 毫秒，`text` 為字串）、`snapshot`／`items`（含 `items` 陣列）、`status`（`source`、`state` 為 `ok`／`error`、`message`）。型別 MUST NOT 含「重要」旗標。欄位名稱、型別與值域 SHALL 與 `protocol/` 的 JSON Schema 一致；兩者不一致時以 schema 與 manifest 為準，不得在 Swift 端另行發明。

#### Scenario: 解碼合法 snapshot
- **WHEN** 解碼一行合法 `snapshot` JSON
- **THEN** SHALL 得到 snapshot 值，`items` 順序與輸入相同

#### Scenario: 解碼合法 status
- **WHEN** 解碼 `state` 為 `error` 的合法 `status`
- **THEN** SHALL 得到 status 值且 `state` 為 error

### Requirement: 單行解碼器與錯誤分類
Core SHALL 提供單行解碼函式：輸入一行位元組（不含結尾換行），輸出已解碼訊息或錯誤。錯誤類別 MUST 與 `message-contract` manifest 的原因類別一一對應，至少含 `not_json`（含非 UTF-8）、`schema`、`version`、`oversize`；是否另有 `order` 類別，依 message-contract 的決定【待確認：message-contract 未決「順序違規是拒絕還是警告」，Swift 端行為依賴該決定，本規格不拍板】。單行錯誤 MUST NOT 以丟出會終止串流的方式處理（回傳錯誤值，由呼叫端決定記錄並繼續）。

#### Scenario: 非 JSON
- **WHEN** 輸入為 `not json at all`
- **THEN** 解碼器 SHALL 回傳 `not_json` 類別錯誤

#### Scenario: 非 UTF-8 位元組
- **WHEN** 輸入含無效 UTF-8 序列
- **THEN** 解碼器 SHALL 回傳 `not_json` 類別錯誤（歸類依 manifest；若 manifest 另有類別則依 manifest）【待確認：message-contract 的 manifest 是否為非 UTF-8 另立類別】

#### Scenario: 不支援的版本
- **WHEN** 輸入為語法與其餘結構合法、但 `v` 為 `2` 的訊息
- **THEN** 解碼器 SHALL 回傳 `version` 類別錯誤，且 SHALL NOT 嘗試解讀其餘欄位

### Requirement: 嚴格性由 message-contract 決定
Swift 預設的 Codable 會忽略未知欄位並接受空陣列，因此下列行為 MUST 以手寫檢查補足，並完全跟隨 `message-contract` 最終決定，而非 Swift 預設：(a) `item` 或訊息含未定義額外欄位是否拒絕【待確認：message-contract design 暫定拒絕，尚未經使用者確認】；(b) 空 `items` 是否合法【待確認：暫定非法】；(c) `text` 是否可為空字串【待確認：message-contract 未規定】；(d) `status.message` 在 `ok` 時是否可為空【待確認：暫允許】；(e) `id` 為數字、`published_at_ms` 為字串／浮點數／負數時拒絕。凡 (a)–(d) 的暫定值 MUST 集中在單一位置，使 message-contract 最終決定後可單點翻轉，且 manifest 為唯一預期來源。

#### Scenario: items 混有非法 item
- **WHEN** `items` 訊息含兩個合法 item 與一個缺少 `id` 的 item
- **THEN** 解碼器 SHALL 整則回傳 `schema` 類別錯誤，不得回傳其中合法的部分

#### Scenario: id 為數字
- **WHEN** 某 item 的 `id` 的 JSON 型別是數字
- **THEN** 解碼器 SHALL 回傳 `schema` 類別錯誤

#### Scenario: 空 items
- **WHEN** `items` 訊息的 `items` 為空陣列
- **THEN** 解碼器行為 SHALL 與 manifest 對該樣本的預期一致【待確認：依賴 message-contract 對空 items 的決定，暫定 reject】

### Requirement: 以 message-contract 的 fixtures 做契約測試
契約測試 SHALL 直接讀取倉庫 `protocol/fixtures/` 與 `protocol/fixtures/manifest.json`（唯讀，不得複製副本到 Swift 目錄、不得複製入 Swift 資源 bundle），對 manifest 中每個樣本執行解碼，結果 MUST 與 manifest 預期一致：`accept` 者成功解碼，`reject` 者失敗且原因類別相符。測試 MUST 檢查 manifest 列出的樣本都被執行（不得因找不到檔案而靜默略過）。manifest 內部欄位名稱與「程式產生樣本」的描述方式，於 `message-contract` apply 後才確定【待確認：以 message-contract 的 manifest 實際格式為準，本規格不自行發明欄位名】。契約測試 MUST 由 `message-contract` 已 apply 為前提；其 fixtures 路徑由測試以來源檔位置往上尋找 `protocol/` 目錄取得【假設：測試以 `#filePath` 定位倉庫根目錄】。

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
