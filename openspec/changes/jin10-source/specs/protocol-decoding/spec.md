## MODIFIED Requirements

### Requirement: 協定 Codable 型別
Core SHALL 提供對應 `message-contract` 的型別：`item`（`source`、`id` 為字串，`published_at_ms` 為整數 UTC 毫秒，`text` 為字串，選填 `url` 為字串或 `nil`，`nil` 表示無連結）、`snapshot`／`items`（含 `items` 陣列）、`status`（`source`、`state` 為 `ok`／`error`、`message`）。`item` 另含選填 `title`（字串或 `nil`）與選填 `important`（布林或 `nil`；`nil` 視為非重要）【change `jin10-source`】；`title` 為空字串、`important` 非布林時 MUST 解碼失敗。欄位名稱、型別與值域 SHALL 與 `protocol/` 的 JSON Schema 一致；兩者不一致時以 schema 與 manifest 為準，不得在 Swift 端另行發明。

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

#### Scenario: 解碼含 title 與 important 的 item
- **WHEN** 解碼 item 含 `"title":"標題"` 與 `"important":true`
- **THEN** SHALL 得到 `title == "標題"` 且 `important == true`

#### Scenario: 缺少 title 與 important
- **WHEN** 解碼的 item 不含這兩個欄位
- **THEN** SHALL 得到 `title == nil`，且視為非重要
