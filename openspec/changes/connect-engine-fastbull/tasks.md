前置：`message-contract` 必須已 apply（`protocol/` 的 schema、fixtures、manifest 存在）。每完成一個階段，回報須附實際執行的指令與測試檔路徑（不能只說「測試綠了」）。改邏輯的項目須提供 fail-then-pass 證據（先寫測試並貼出失敗輸出，再實作並貼出通過輸出）。

## 1. 專案骨架與核心狀態機

- [x] 1.1 建立 `ticker-connect/` cargo 專案（binary＋library）、`Connector` trait、`Item`／`ConnectError` 型別與假 Connector 測試輔助。驗收：`cd ticker-connect && cargo test connector_trait`（假 Connector 可編譯並被引擎驅動，`convert` 純函式測試通過）。
- [x] 1.2 實作 seen-set 去重與增量 `items`（舊到新、tie-break、容量上限淘汰）。驗收：`cd ticker-connect && cargo test dedup`；fail-then-pass：先寫「只發新的／多則舊到新／容量淘汰」測試並確認失敗，再實作至通過，貼兩次輸出。
- [x] 1.3 實作首次成功發 `snapshot`、洪水保護（超過 10 則改發 `snapshot`，恰 10 則發 `items`），門檻與容量為可設定常數。驗收：`cd ticker-connect && cargo test snapshot_flood`；需 fail-then-pass 證據。
- [x] 1.4 實作錯誤處理：fetch 失敗、非 200、解析 0 則、首次即失敗，皆發 `status: error` 且不改 seen 狀態。驗收：`cd ticker-connect && cargo test error_keeps_state`；需 fail-then-pass 證據。
- [x] 1.5 實作 Scheduler：可注入假時鐘、退避 10→30→60 封頂、成功重置。驗收：`cd ticker-connect && cargo test backoff`（斷言假時鐘上的等待序列 10,30,60,60,60 與重置）；需 fail-then-pass 證據。

## 2. 輸出、心跳與行程生命週期

- [x] 2.1 實作單一寫入者 emitter：逐行 flush、輸出前以 `protocol/` schema 驗證、超過 1MB 不輸出、不合格改發 `status` 警告；日誌只走 stderr。驗收：`cd ticker-connect && cargo test emitter`，且該測試讀取 `protocol/fixtures/manifest.json` 對每個樣本比對 accept／reject；發送端不合格處置依 design.md 已決定的過濾規則（丟 item、另發 status error、無合法 item 不發訊息）。需 fail-then-pass 證據。
- [x] 2.2 實作心跳（含成功、失敗、退避、無新訊息期間，間隔不超過 30 秒）。驗收：`cd ticker-connect && cargo test heartbeat`（假時鐘跑 5 分鐘，斷言相鄰 `status` 間隔 ≤ 30 秒）；需 fail-then-pass 證據。
- [x] 2.3 實作 stdin 監看獨立執行緒與 EOF 立即退出，含網路請求進行中的情境。驗收：`cd ticker-connect && cargo test --test lifecycle`（整合測試：啟動 binary 對本機延遲 30 秒的假伺服器，關閉 stdin，斷言 1 秒內退出；另斷言 stdout 每行皆為合法協定 JSON）；需 fail-then-pass 證據。

## 3. FastBull 連接器

- [x] 3.1 實作 FastBull `convert`：`div.news-list[data-id]` 範圍內擷取，不解析畫面時間；解析 0 則回錯誤。驗收：`cd ticker-connect && cargo test fastbull_parse`，讀取 `docs/fixtures/express-news-2026-10-24.html`，斷言 20 則、id 不重複、前 6 則 id／`published_at_ms` 與規格相符、第一則四個欄位逐字相符、輸出通過 `protocol/` schema、空 HTML 與改名 class 回錯誤、快訊元素之外的 `title_name` 不被誤取；需 fail-then-pass 證據。
- [x] 3.2 實作 FastBull `fetch`（User-Agent、連線與總逾時、非 200 為錯誤、可覆寫 URL、不重疊請求）與守衛測試（測試不得連非 127.0.0.1）。驗收：`cd ticker-connect && cargo test fastbull_fetch`（本機假伺服器：200、403、429、500、延遲逾時、檢查 User-Agent 標頭）；並 `grep -rn "fastbull.com" ticker-connect/tests` 無請求路徑；需 fail-then-pass 證據。

## 4. 整合與收尾

- [x] 4.1 端到端整合：binary 以本機假伺服器（先快照 HTML、再加一則新快訊、再失敗、再恢復）跑完整流程，stdout 依序為 `snapshot`、`items`、`status: error`、恢復後不重發舊訊息。驗收：`cd ticker-connect && cargo test --test e2e_local`；同時 `openspec validate connect-engine-fastbull --strict` 與 `openspec validate message-contract --strict` 通過；回報須列出全部實際指令與測試檔路徑。
- [x] 4.2 記錄未驗證項目與手動驗證：於 `ticker-connect/README.md` 寫明待釐清清單（含服務條款【待使用者確認】、VPN／Proxy TLS【待驗證】、5 秒間隔【待實測】、洪水門檻【假設】），並在 VPN／Proxy 環境手動執行一次 helper 記錄結果（僅單次人工驗證，非自動化測試）。驗收：README 的清單與 `design.md` 逐項一致；手動驗證結果（成功、失敗或未執行）如實記錄，未執行則標「未驗證」。
