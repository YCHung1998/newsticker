## Why

FastBullTicker 由 Rust helper（Connect engine）與 Swift App（Show engine）兩個獨立行程組成，兩端只靠 stdout JSON-lines 溝通。若沒有先把訊息格式、版本、心跳與錯誤處理期望定成可機器驗證的契約，兩端會各自解讀、各自漂移。後續四個 change（Rust helper、spike、Swift core、App shell）都依賴這份契約，因此它必須最先完成。

## What Changes

- 新增 `protocol/` 的版本化 JSON Schema 契約，涵蓋三種訊息：`snapshot`、`items`、`status`，以及共用的 `item` 結構（`source`、`id`、`published_at_ms`、`text`）與協定版本欄位 `v`。
- 定義 `status` 的心跳義務（至少每 30 秒一次）、單行上限 1MB，以及接收端遇到非法訊息時的處理期望。
- 新增驗證用 fixtures（合法與非法樣本）與一份 manifest，描述每個樣本應被接受或拒絕。
- 定義兩端共用的契約測試方式：Rust 與 Swift 後續各自用同一批 fixtures 與 manifest 驗證；本 change 只定義 fixtures 與驗證方式，並以一個參考驗證器證明 schema 與 fixtures 自洽。
- 本 change 不實作任何 Rust 或 Swift 程式；`protocol/*.json` 等實體檔案在 apply 階段才建立。

## Capabilities

### New Capabilities
- `message-protocol`: JSON-lines 訊息契約——三種訊息的結構、`item` 欄位、版本欄位 `v`、心跳義務、單行上限與非法訊息處理期望。
- `contract-fixtures`: 驗證用 fixtures（合法／非法樣本）、manifest 格式，以及兩端共用的契約測試與 fail-then-pass 證據要求。

### Modified Capabilities
（無；`openspec/specs/` 目前沒有既有 spec。）

## Impact

- 新增目錄：`protocol/`（schema、fixtures、manifest、參考驗證測試）。
- 下游依賴：`connect-engine-fastbull`（Rust emitter 輸出前驗證）、`show-engine-core`（Swift Codable 型別與 LineBuffer）。兩者必須使用本 change 的 fixtures。
- 無執行期依賴、無對外 API；不影響既有程式碼（專案尚無程式碼）。
