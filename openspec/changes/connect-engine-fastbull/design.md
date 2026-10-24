## Context

來源：`docs/superpowers/specs/2026-10-24-fastbull-ticker-design.md` 第 4 節（Connect engine）、第 8 節（風險 7）、第 9 節（change 拆分，本 change 為第 2 個）。本 change 依賴第 1 階段 `message-contract`（協定與 fixtures）。引擎為獨立 Rust 行程，與 Swift App 只靠 stdout JSON-lines 溝通。本 change 只寫規格，不實作。

## Goals / Non-Goals

**Goals:**
- 以 `Connector` trait 把「來源專屬」（fetch／convert）與「引擎共用」（排程、去重、退避、輸出、心跳、退出）分開。
- 讓輪詢、去重、退避、洪水保護都能用假 Connector＋假時鐘做確定性測試，不需網路。
- 讓 FastBull 解析可用快照 fixture 精確驗證，抓取可用本機假伺服器驗證。

**Non-Goals:**
- 不重新定義協定、不擴充欄位；不做 Swift、視窗、SQLite、WebSocket、其他網站連接器。
- 不實作任何程式；不選定具體 crate 之外的架構細節，以下僅為建議。

## Decisions

1. **引擎核心為與 I/O 解耦的狀態機**：輸入為「一次輪詢結果（`Ok(Vec<Item>)` 或錯誤）」，輸出為「要發的訊息清單＋下次等待時間」，seen-set 與是否已發 snapshot 是其內部狀態。理由：去重、洪水、錯誤不改狀態等規則全成為純函式測試，不需執行緒或網路。替代：直接在 async 迴圈內寫邏輯（較難測）。
2. **時鐘注入**：Scheduler 依賴一個 `Clock`（取得現在、等待至某時刻）抽象，測試用假時鐘推進。心跳與退避都由同一時鐘驅動。
3. **stdin 監看用獨立 OS 執行緒**，讀到 EOF 直接 `process::exit`，不經過 async 執行環境，因此不會被卡住的網路請求阻擋。替代：在 async 內 select（若執行環境被阻塞同步呼叫卡住會失效）。
4. **輸出單一寫入者**：所有訊息（snapshot／items／status）經單一 emitter 序列化、驗證、逐行 flush，避免多執行緒交錯寫出破壞行格式。
5. **schema 驗證在 emitter 內**，直接使用 `protocol/` 的 schema 檔（與 `message-contract` 的 `$schema` 草案一致；其草案版本為該 change 的【假設】，若 Rust crate 不支援需回頭協調，不在本 change 自行更改）。
6. **HTML 解析函式庫的選擇留給 apply 階段**（需能以 CSS 選擇器或等價方式限定元素範圍）。重點是規格的行為：`span.title_name` 必須限定在 `div.news-list` 元素內。我對快照的核對顯示：整份文件 115 個 `class="title_name"`，快訊元素外尚有其他區塊，若全文搜尋會誤取。
7. **洪水保護門檻與 seen-set 容量為可設定常數**（預設 10 與 500），便於使用者確認後翻轉。
8. **HTTP 用單一重用的 client**；同一時間僅一個進行中的請求（以序列迴圈保證，不另開並行輪詢）。

## Risks / Trade-offs

- [VPN／Proxy 下 Rust TLS 行為未知] → apply 階段須以實際網路手動驗證並記錄，自動化測試不涵蓋；未驗證前不宣稱可用（design 風險 7）。
- [服務條款未確認] → 標【待使用者確認】；10 秒間隔為保守預設，不降到 5 秒。
- [頁面改版使解析 0 則] → 視為錯誤並發 `status: error`，不誤判為「沒新訊息」。
- [洪水保護閾值 10 為假設] → 可設定常數；誤判時代價是少一次即時效果、多一次重播基準重設。
- [發送端對不合格 item 的處置] → 已決定（2026-10-24）：發送端過濾，見「與 message-contract 相關的決定」。
- [測試誤連正式網站] → 守衛測試＋規格禁止；預設 URL 只在非測試設定出現。

## 與 message-contract 相關的決定（使用者 2026-10-24 已決定）

1. **矛盾裁決（已決定）**：接收端（Swift）整則所有 item 都合法才接受；發送端（本 change 的 Rust helper）自己負責過濾：不合格 item 丟掉，另發一則 `status`（`state: error`，`message` 描述丟棄原因）；過濾後若無合法 item，不得發空 `items`／`snapshot`，只發警告。
2. **警告 `status` 的 `state`（已決定）**：用 `error`。
3. **空 `items`（已決定）**：依 `protocol/` 已實作 schema 為非法（`minItems: 1`），引擎不得發空 `items`／`snapshot`。
4. **退避期間仍發心跳（已決定）**；`status` 至少每 30 秒。
5. **心跳容忍度**：判定為相鄰 `status` 間隔 <= 30 秒；本 change 內部週期 25 秒為暫定、使用者未反對，沿用【假設】。
6. **順序與 tie-break（已決定部分）**：snapshot 新到舊、items 舊到新；相同 `published_at_ms` 允許（非嚴格）；tie-break 暫定「保持頁面順序的反向（舊到新時）」【假設】。
7. **協定細節以 `protocol/` 已實作 schema 為準（已決定）**：`v` = 1、不允許額外欄位、`text` 不得為空、單行 <= 1,048,576 位元組、JSON Schema 2020-12。

## 其餘暫定值（使用者未反對，沿用，維持【假設】標示，未升級為已確認）

本 change 自己的待釐清：
8. 洪水保護的 snapshot 內容（整頁結果或僅新訊息）；門檻 10 為【假設】。
9. seen-set 上限確切值與淘汰策略。
10. `source_id` 字串（暫定 `fastbull`）、User-Agent 字串、逾時秒數（暫定 8 秒）、是否跟隨重新導向。
11. `text` 是否修剪空白與解碼 HTML 實體；單一元素壞掉時是跳過或整頁失敗。
12. stdin EOF 退出的容忍時間（測試暫以 1 秒為門檻）。
13. 服務條款（【待使用者確認】）、VPN／Proxy 下 TLS 行為（【待驗證】）、5 秒輪詢可行性（【待實測】）。
14. **快照實測更正（apply 階段，2026-10-24）**：`div.news-list[data-id]` 在快照中共 70 個（`#side_fast_news` 20 個＋`#main-content` 50 個，前 20 個相同），非 20 個。為符合規格「恰 20 則」，解析限定 `#side_fast_news`；要取側欄 20 則或主內容 50 則【待使用者確認】。若頁面結構改變導致側欄消失，解析 0 則會成為錯誤並發 `status: error`（安全失敗）。
