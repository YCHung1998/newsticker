# connector-engine Specification

## Purpose
TBD - created by archiving change connect-engine-fastbull. Update Purpose after archive.
## Requirements
### Requirement: 遵守 message-contract 協定
`ticker-connect` 輸出的每一行 MUST 符合 `message-contract` change 定義的協定（`snapshot`、`items`、`status`、`item` 欄位、`v`、單行 1MB 上限）。本 change SHALL NOT 新增、修改或擴充任何協定欄位或訊息類型；若引擎需要協定未提供的資訊，MUST 列入 `design.md` 的待釐清而非自行擴充。引擎的契約測試 MUST 直接讀取 `protocol/fixtures/` 與 `manifest.json`，不得複製副本。

#### Scenario: 輸出通過契約 fixtures 的驗證
- **WHEN** 引擎的 emitter 以 `protocol/` 的 schema 驗證其輸出
- **THEN** emitter 對 manifest 中每個 `accept` 樣本 SHALL 判為可輸出，對每個 `reject` 樣本 SHALL 判為不可輸出

#### Scenario: 需要協定沒有的欄位
- **WHEN** 實作中發現需要 `message-contract` 未定義的欄位或訊息類型
- **THEN** 該需求 SHALL 被記入待釐清，且本 change 的輸出 SHALL NOT 包含該欄位

### Requirement: Connector trait
引擎 SHALL 定義 `Connector` trait，含 `source_id() -> &str`、`interval() -> Duration`、非同步的 `fetch() -> Result<RawPayload, ConnectError>`、`convert(raw: RawPayload) -> Result<Vec<Item>, ConnectError>`。`convert` MUST 為純函式（相同輸入得相同輸出，無 I/O、無時鐘依賴），使其可用快照 fixture 直接測試。`convert` 回傳的 `Vec<Item>` 順序 MUST 與來源頁面順序一致（新到舊），由引擎負責在發送 `items` 時反轉為舊到新。

#### Scenario: 以假 Connector 驅動引擎
- **WHEN** 測試提供一個實作 `Connector` 的假物件，其 `fetch` 與 `convert` 回傳預先設定的結果
- **THEN** 引擎 SHALL 能不經任何網路即完整執行輪詢流程

#### Scenario: convert 為純函式
- **WHEN** 以同一個 `RawPayload` 呼叫 `convert` 兩次
- **THEN** 兩次回傳 SHALL 相等

### Requirement: 輪詢排程與退避
Scheduler SHALL 依 `Connector::interval()` 輪詢；FastBull 預設間隔為 10 秒（見 `fastbull-connector`）。輪詢失敗（見「錯誤處理」）後 SHALL 退避重試，間隔序列為 10 → 30 → 60 秒，達 60 秒後封頂不再增加；任一次成功輪詢 SHALL 將退避重置回 `interval()`。Scheduler MUST 可注入時鐘，使測試不需真實等待。

#### Scenario: 連續失敗的退避序列
- **WHEN** 假 Connector 連續失敗五次
- **THEN** 假時鐘上觀察到的重試等待 SHALL 依序為 10、30、60、60、60 秒

#### Scenario: 成功後重置退避
- **WHEN** 連續失敗兩次後成功一次，隨後再失敗一次
- **THEN** 該次失敗後的等待 SHALL 回到退避序列的第一階（10 秒）

#### Scenario: 退避期間心跳（已決定 2026-10-24）
- **WHEN** 引擎處於退避重試期間（例如 60 秒等待中）
- **THEN** 引擎 SHALL 仍依「心跳」要求每 30 秒內送出 `status`（使用者 2026-10-24 已決定：退避期間仍須發送心跳）

### Requirement: 第一次成功輪詢發 snapshot
引擎 SHALL 將第一次成功的輪詢結果（`convert` 成功且至少 1 則）以 `snapshot` 訊息輸出，`items` 順序為新到舊，並將其所有 `id` 加入 seen-set。第一次成功之前 MUST NOT 輸出 `snapshot` 或 `items`。

#### Scenario: 首次成功輪詢
- **WHEN** 假 Connector 首次回傳 5 則 item
- **THEN** stdout SHALL 出現恰一則 `snapshot`，含該 5 則（新到舊），且 seen-set 含這 5 個 `id`

#### Scenario: 首次失敗後成功
- **WHEN** 第一次輪詢失敗、第二次成功
- **THEN** 第二次成功時 SHALL 才輸出 `snapshot`，之前 SHALL 只有 `status`

### Requirement: seen-set 去重與增量 items
首次成功之後，每次成功輪詢 SHALL 以 `id` 與 seen-set 比對，只將不在 seen-set 的 item 視為新訊息，並以 `items` 訊息輸出，順序為舊到新（依 `published_at_ms` 升冪；相同值時 MUST 保持來源頁面順序的反向以得到確定結果）。沒有新訊息時 MUST NOT 輸出 `items`（已決定 2026-10-24：空 `items` 依 `protocol/` 已實作 schema 為非法，`minItems: 1`）。相同 `published_at_ms` 允許（非嚴格），tie-break 暫定為保持頁面順序的反向【假設】。seen-set 上限約 500 筆，超過時 SHALL 淘汰最舊加入者。「約 500」的確切值與淘汰策略設計文件未規定【待確認】。

#### Scenario: 只發新的
- **WHEN** seen-set 已含 id A、B、C，下次輪詢結果為 D、A、B、C（新到舊）
- **THEN** 引擎 SHALL 輸出恰一則 `items` 含 D，並將 D 加入 seen-set

#### Scenario: 多則新訊息舊到新
- **WHEN** 下次輪詢結果為 E、D、A（新到舊），其中 E、D 為新
- **THEN** `items` 訊息 SHALL 依序含 D、E（舊到新）

#### Scenario: 無新訊息
- **WHEN** 輪詢結果的 id 全部已在 seen-set
- **THEN** 引擎 SHALL NOT 輸出 `items` 或 `snapshot`，但 SHALL 照常維持心跳

#### Scenario: seen-set 容量
- **WHEN** seen-set 累積超過上限
- **THEN** 最舊加入的 id SHALL 被淘汰，seen-set 大小 SHALL NOT 超過上限【待確認：上限確切值】

### Requirement: 錯誤處理不改變 seen 狀態
fetch 失敗、HTTP 非 200、`convert` 回傳錯誤、或 `convert` 解析出 0 則，引擎 MUST 一律視為錯誤：輸出 `status`（`state: error`，`message` 說明原因），進入退避重試，並且 MUST NOT 修改 seen-set 與「是否已發過 snapshot」的狀態，也 MUST NOT 將其當成「沒有新訊息」。

#### Scenario: 解析 0 則視為錯誤
- **WHEN** `fetch` 成功但 `convert` 回傳空清單
- **THEN** 引擎 SHALL 輸出 `status: error`、進入退避，且 seen-set SHALL 與輪詢前相同

#### Scenario: 失敗後恢復不重發舊訊息
- **WHEN** seen-set 含 A、B；一次 fetch 失敗；下一次成功，結果為 C、A、B
- **THEN** 引擎 SHALL 只輸出含 C 的 `items`，不重發 A、B

#### Scenario: 首次輪詢解析 0 則
- **WHEN** 尚未發過 snapshot，且第一次輪詢解析 0 則
- **THEN** 引擎 SHALL 視為錯誤，且之後第一次成功輪詢仍 SHALL 發 `snapshot`

### Requirement: 洪水保護
單次輪詢得到超過 10 則「新」訊息時，引擎 SHALL NOT 以 `items` 當即時訊息輸出，而 SHALL 改發一則新的 `snapshot`（新到舊）重設基準，並將這些 id 加入 seen-set【假設：10 為暫定值，設計文件標為假設，未經使用者確認】。恰為 10 則 SHALL 視為未超過。此 `snapshot` 中應包含的內容（僅新訊息，或整頁最新 N 則）設計文件未規定【待確認：本規格暫定為該次輪詢 `convert` 的整頁結果】。

#### Scenario: 超過門檻改發 snapshot
- **WHEN** 一次輪詢有 11 則新訊息
- **THEN** 引擎 SHALL 輸出一則 `snapshot` 而非 `items`，且這 11 個 id 皆進入 seen-set【假設】

#### Scenario: 恰為門檻
- **WHEN** 一次輪詢有 10 則新訊息
- **THEN** 引擎 SHALL 輸出 `items`（舊到新）而非 `snapshot`【假設】

### Requirement: stdin EOF 立即退出
引擎 SHALL 以獨立執行緒監看 stdin；讀到 EOF 時 MUST 立即結束行程（不等待輪詢週期、不等待進行中的網路請求完成）。此監看 MUST NOT 被阻塞中的 `fetch` 卡住。可選加入 `getppid` 檢查作為保險。

#### Scenario: 閒置時 EOF
- **WHEN** 測試啟動 helper 並關閉其 stdin
- **THEN** 行程 SHALL 在 1 秒內結束【1 秒為本規格的測試門檻，設計文件僅要求「立即」；待確認】

#### Scenario: 網路請求進行中 EOF
- **WHEN** 本機假伺服器刻意延遲回應 30 秒，helper 正在等待該回應時 stdin 被關閉
- **THEN** 行程 SHALL 在 1 秒內結束，不等待該請求逾時

### Requirement: stdout 只輸出協定 JSON，日誌走 stderr
stdout MUST 只含協定訊息，每行恰一個 JSON 物件；任何日誌、除錯字串、panic 訊息 MUST 寫入 stderr。輸出 MUST 逐行 flush，使 App 即時收到。

#### Scenario: stdout 每行皆可解析
- **WHEN** 在整合測試中執行 helper 一段時間並擷取 stdout
- **THEN** stdout 的每一行 SHALL 是通過 `protocol/` schema 的 JSON 物件，不含其他文字

#### Scenario: 日誌不污染 stdout
- **WHEN** 引擎遇到錯誤並寫日誌
- **THEN** 日誌 SHALL 出現在 stderr，stdout SHALL 只多一則 `status`

### Requirement: 輸出前 schema 驗證與發送端過濾
引擎 SHALL 在輸出每則訊息前以 `protocol/` 的 schema 驗證（JSON Schema 2020-12，`v` = 1、不允許額外欄位、`text` 不得為空、單行 <= 1,048,576 位元組，以 `protocol/` 已實作 schema 為準）。已決定（使用者 2026-10-24）：接收端（Swift）整則所有 item 都合法才接受；**發送端（本 change 的 Rust helper）自己負責過濾**：不合格的 item MUST 被丟棄、MUST NOT 混進 `items`／`snapshot`，並 SHALL 另發一則 `status`（`state: "error"`，`message` 描述丟棄原因）；過濾後若沒有任何合法 item，MUST NOT 發出空的 `items`／`snapshot`，只發警告 `status`。

#### Scenario: 不合格 item 被過濾
- **WHEN** 組出的 `items` 含一個 `id` 為空字串的 item 與兩個合法 item
- **THEN** 引擎 SHALL 輸出只含兩個合法 item 的 `items`，並另輸出一則 `status`（`state: error`），`message` 說明丟棄原因

#### Scenario: 過濾後無合法 item
- **WHEN** 所有 item 皆不合格
- **THEN** 引擎 SHALL NOT 輸出 `items` 或 `snapshot`，只輸出警告 `status`

#### Scenario: 超過 1MB 的行
- **WHEN** 組出的訊息序列化後超過 1,048,576 位元組
- **THEN** 引擎 SHALL NOT 輸出該行，並 SHALL 輸出 `status` 警告

### Requirement: 心跳
引擎 SHALL 至少每 30 秒輸出一則 `status`，兼作心跳（已決定 2026-10-24）；此義務 MUST NOT 因輪詢成功或失敗而中止（含退避期間）。正常運作時 `status` 使用 `state: ok`，錯誤時使用 `state: error`。判定依據為相鄰 `status` 間隔 <= 30 秒（不另訂容忍值）；引擎 SHALL 以小於 30 秒的內部週期 25 秒發送以留餘裕【內部週期 25 秒為暫定，使用者未反對，沿用，維持假設】。是否每次輪詢成功都額外發 `status: ok` 設計文件未規定，本規格僅要求不晚於 30 秒。

#### Scenario: 心跳間隔
- **WHEN** 以假時鐘執行引擎 5 分鐘（含成功與失敗輪詢）
- **THEN** 任兩則相鄰 `status` 的間隔 SHALL NOT 超過 30 秒

#### Scenario: 長時間無新訊息仍有心跳
- **WHEN** 連續多次輪詢皆無新訊息
- **THEN** stdout SHALL 仍每 30 秒內至少出現一則 `status`

### Requirement: 測試策略與禁止連線
輪詢、退避、去重、洪水保護 MUST 以假 Connector 與假時鐘測試。HTTP 抓取 MUST 以本機假伺服器（綁定 127.0.0.1）測試。任何自動化測試 MUST NOT 連到正式網站（`fastbull.com` 及任何外部主機）。

#### Scenario: 測試不連外
- **WHEN** 執行 `cd ticker-connect && cargo test`
- **THEN** 測試 SHALL 不對 127.0.0.1 以外的主機發出連線；正式 URL 只能出現在非測試的預設設定中

#### Scenario: 保護測試被破壞時會失敗
- **WHEN** 有測試嘗試把連線目標設為非本機位址
- **THEN** 守衛測試或測試輔助程式 SHALL 使其失敗

