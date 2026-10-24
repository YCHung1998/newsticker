## Why

Connect engine 是 FastBullTicker 的資料來源端：獨立 Rust 行程 `ticker-connect`，負責輪詢網頁、去重、退避，並依 `message-contract` 定義的協定在 stdout 輸出 JSON-lines。沒有它，Swift App 沒有任何資料可顯示。把「所有來源共用的引擎行為」與「FastBull 專屬的解析與抓取」分開規格化，日後新增來源只需新增一個 Connector。

## What Changes

- 新增 Rust helper `ticker-connect`（獨立 cargo 專案），含 `Connector` trait（`source_id`、`interval`、`fetch`、`convert`，`convert` 為純函式）。
- 引擎共用行為：Scheduler 輪詢與退避（10→30→60 秒封頂）、第一次成功輪詢發 `snapshot`、seen-set（上限約 500）去重並只發新 `items`（舊到新）、解析 0 則／fetch 失敗／非 200 一律視為錯誤且不改 seen 狀態、單次超過 10 則新訊息改發新 `snapshot`【假設】、stdin EOF 立即退出、stdout 只輸出協定 JSON（日誌走 stderr）、輸出前過 schema 驗證、`status` 至少每 30 秒心跳。
- FastBull 連接器：解析規則（`div.news-list[data-id]` → `id`、`data-date` 毫秒 → `published_at_ms`、`span.title_name` → `text`）、對快照 fixture 的解析測試、HTTP 抓取（User-Agent、逾時、非 200 為錯誤）。
- 測試策略：輪詢與去重用假 Connector／假時鐘；抓取用本機假伺服器；嚴禁測試連到正式網站。
- 不在範圍：Swift 端、視窗、SQLite、WebSocket 來源、其他網站連接器。
- 本 change 只產規格，不建立任何 Rust 程式碼；`ticker-connect/` 在 apply 階段才建立。

## Capabilities

### New Capabilities
- `connector-engine`: 所有來源共用的引擎行為——Connector trait、輪詢／退避、snapshot／items／洪水保護、seen-set、錯誤處理、stdin EOF 退出、stdout／stderr 紀律、輸出前 schema 驗證、心跳、測試策略。
- `fastbull-connector`: FastBull 連接器——HTML 解析規則、對快照 fixture 的解析測試、HTTP 抓取行為、輪詢間隔與待驗證／待確認事項。

### Modified Capabilities
（無。協定由 `message-contract` 定義，本 change 只引用、不修改。）

## Impact

- 依賴 `message-contract`（第 1 階段，需先 apply）：使用其 `protocol/` schema、fixtures、manifest；本 change 不得重新定義協定，也不得修改該 change 的任何檔案。
- 新增目錄（apply 階段）：`ticker-connect/`（Cargo 專案、測試）。
- 下游：`app-shell` 的 `FeedClient` 啟動此 helper 並消費其 stdout。
- 對外網路：僅 FastBull 連接器的正式執行會連 `https://www.fastbull.com/tw/express-news`；測試一律不連。
- 風險：服務條款未確認；VPN／Proxy 下 TLS 行為未驗證（見 design.md）。
