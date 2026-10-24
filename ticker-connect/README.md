# ticker-connect —— FastBullTicker Connect engine（Rust helper）

獨立行程，輪詢 FastBull 快訊頁，以 stdout JSON-lines（`protocol/` 定義的 v1 協定）輸出 `snapshot`／`items`／`status`；日誌走 stderr；stdin EOF 立即結束。
規格：`openspec/changes/connect-engine-fastbull/`。協定與 fixtures：`../protocol/`（唯讀，本專案直接編入 schema、直接讀 manifest，不複製）。

## 建置與執行

```sh
cd ticker-connect
cargo build              # 依賴已鎖定於 Cargo.lock
cargo test               # 全套（全部只連 127.0.0.1，不連正式網站）
./target/debug/ticker-connect          # 正式執行（連 https://www.fastbull.com/tw/express-news，間隔 10 秒）
```

測試用選項（預設值即正式值）：`--url URL`、`--interval-ms N`、`--heartbeat-ms N`。

## 架構（src/）

| 檔案 | 內容 |
|---|---|
| `connector.rs` | `Connector` trait（`source_id`／`interval`／`fetch`／純函式 `convert`） |
| `engine.rs` | 與 I/O 解耦的狀態機：seen-set、snapshot／items、洪水保護、錯誤不改狀態 |
| `emitter.rs` | 單一寫入者：輸出前驗證、**發送端過濾**、逐行 flush |
| `protocol.rs` | 編入 `protocol/schema/*.json`（JSON Schema 2020-12）＋額外檢查，判定順序同 `protocol/refcheck.py` |
| `scheduler.rs` | 輪詢、退避（interval x [1,3,6] = 10→30→60 秒）、心跳（含退避期間與 fetch 進行中） |
| `fastbull.rs` | FastBull 抓取（reqwest + rustls）與解析（scraper） |
| `main.rs` | 參數、stdin 監看執行緒、啟動 |

假時鐘：使用 tokio 的虛擬時間（`#[tokio::test(start_paused = true)]`），不真的等待；等同規格所說「可注入時鐘」，未另外抽象 `Clock` trait。

## Rust JSON Schema crate 是否支援 2020-12（查證）

- 使用 `jsonschema` 0.60.1（`default-features = false`，不含網路擷取）。其 README 的 Supported drafts 列出 Draft 2020-12 並附 Bowtie 合規徽章（徽章是它的自我宣稱，我們沒有跑 Bowtie）。
- 自行驗證（`tests/jsonschema_2020_12.rs`）：2020-12 專屬的 `prefixItems`、`unevaluatedProperties` 被正確執行，且同一 schema 以 Draft 7 建構時 `prefixItems` 被忽略（對照組）；`Protocol::new()` 以 `Draft::Draft202012` 建構，並用 `$id` 互相 `$ref`（離線 registry）成功。
- 跨語言契約：`tests/emitter_contract.rs` 對 `protocol/fixtures/manifest.json` 的**每個**樣本（含程式產生的 1,048,576／+1 位元組樣本）驗證，結論與 Python 參考驗證器一致（accept／reject＋原因類別）。

```sh
cd ticker-connect && cargo test --test jsonschema_2020_12 --test emitter_contract
python3 -m unittest discover -s protocol/tests      # 參考驗證器（在 newsticker/ 根目錄執行）
```

## 測試指令與檔案

| 任務 | 指令（皆在 `ticker-connect/` 內） | 測試檔 |
|---|---|---|
| 1.1 | `cargo test connector_trait` | `tests/connector_trait.rs` |
| 1.2 | `cargo test dedup` | `tests/engine_logic.rs` |
| 1.3 | `cargo test snapshot_flood` | `tests/engine_logic.rs` |
| 1.4 | `cargo test error_keeps_state` | `tests/engine_logic.rs` |
| 1.5 | `cargo test backoff` | `tests/scheduler.rs` |
| 2.1 | `cargo test emitter` | `tests/emitter_contract.rs`（讀 manifest）；schema 查證 `tests/jsonschema_2020_12.rs` |
| 2.2 | `cargo test heartbeat` | `tests/scheduler.rs` |
| 2.3 | `cargo test --test lifecycle` | `tests/lifecycle.rs` |
| 3.1 | `cargo test fastbull_parse` | `tests/fastbull_parse.rs`（讀 `../docs/fixtures/express-news-2026-10-24.html`） |
| 3.2 | `cargo test fastbull_fetch`；`grep -rn "fastbull.com" tests`（應無輸出）；`cargo test --test no_external_network` | `tests/fastbull_fetch.rs`、`tests/no_external_network.rs`、`tests/common/mod.rs`（本機假伺服器） |
| 4.1 | `cargo test --test e2e_local` | `tests/e2e_local.rs` |

## fail-then-pass 證據（2026-10-24 實跑）

**誠實說明**：實作與測試是一起寫完後，才對每個項目做「故意破壞實作 -> 測試變紅 -> 還原 -> 測試轉綠」的突變驗證（不是先寫測試、看它在尚無實作時失敗）。突變由腳本自動套用並還原（還原後再跑一次記錄綠）。下表的紅／綠皆為實際輸出摘要。

| 任務 | 指令 | 故意破壞 | 紅 | 綠（還原後） |
|---|---|---|---|---|
| 1.1 | `cargo test connector_trait` | `src/scheduler.rs`: scheduler.run returns immediately (engine never driven) | 紅（exit 101）：FAILED 1 passed / 1 failed；`connector_trait_fake_connector_drives_engine_without_network` | 綠（exit 0）：ok 2 passed / 0 failed |
| 1.2 | `cargo test dedup` | `src/engine.rs`: remove the seen-set filter (re-emit everything) | 紅（exit 101）：FAILED 3 passed / 4 failed；`dedup_no_new_items_emits_nothing`, `dedup_equal_timestamps_tiebreak_is_reverse_page_order`, `dedup_only_new_items_are_emitted` … | 綠（exit 0）：ok 7 passed / 0 failed |
| 1.3 | `cargo test snapshot_flood` | `src/engine.rs`: off-by-one: exactly 10 treated as flood | 紅（exit 101）：FAILED 4 passed / 1 failed；`snapshot_flood_exactly_threshold_is_items` | 綠（exit 0）：ok 5 passed / 0 failed |
| 1.4 | `cargo test error_keeps_state` | `src/engine.rs`: parsed 0 items no longer an error | 紅（exit 101）：FAILED 2 passed / 2 failed；`error_keeps_state_first_poll_zero_items_then_success_still_snapshot`, `error_keeps_state_parse_zero_items_is_error_not_no_news` | 綠（exit 0）：ok 4 passed / 0 failed |
| 1.5 | `cargo test backoff` | `src/scheduler.rs`: ladder caps at 30s instead of 60s（FACTORS [1,3,6] 改 [1,3,3]） | 紅（exit 101）：FAILED 3 passed / 2 failed；`backoff_ladder_is_10_30_60_capped_and_resets`, `backoff_five_consecutive_failures_wait_10_30_60_60_60` | 綠（exit 0）：ok 5 passed / 0 failed |
| 2.1a | `cargo test emitter_filter` | `src/emitter.rs`: skip per-item validation (invalid items leak) | 紅（exit 101）：FAILED 1 passed / 1 failed；`emitter_filter_drops_bad_items_and_warns_with_status_error` | 綠（exit 0）：ok 2 passed / 0 failed |
| 2.1b | `cargo test emitter_contract` | `src/protocol.rs`: 1MB limit off by one (generated-over-limit sample) | 紅（exit 101）：FAILED 2 passed / 1 failed；`emitter_contract_all_manifest_samples_match_reference_verdict` | 綠（exit 0）：ok 3 passed / 0 failed |
| 2.1c | `cargo test emitter_contract` | `src/protocol.rs`: disable order check | 紅（exit 101）：FAILED 2 passed / 1 failed；`emitter_contract_all_manifest_samples_match_reference_verdict` | 綠（exit 0）：ok 3 passed / 0 failed |
| 2.2a | `cargo test heartbeat` | `src/scheduler.rs`: internal heartbeat period 45s (> 30s) | 紅（exit 101）：FAILED 1 passed / 3 failed；`heartbeat_five_minutes_during_backoff_gap_at_most_30s` 等 3 個 | 綠（exit 0）：ok 4 passed / 0 failed |
| 2.2b | `cargo test heartbeat` | `src/scheduler.rs`: no heartbeat while waiting for next poll/backoff | 紅（exit 101）：FAILED 1 passed / 3 failed；同上 3 個 | 綠（exit 0）：ok 4 passed / 0 failed |
| 2.3 | `cargo test --test lifecycle` | `src/main.rs`: stdin EOF no longer exits（`process::exit(0)` 改 `break`） | 紅（exit 101）：FAILED 1 passed / 2 failed；`lifecycle_exits_within_1s_when_idle_and_stdin_closes`, `lifecycle_exits_within_1s_when_stdin_closes_during_a_30s_hanging_request` | 綠（exit 0）：ok 3 passed / 0 failed |
| 3.1a | `cargo test fastbull_parse` | `src/fastbull.rs`: search whole document (70 elements) | 紅（exit 101）：FAILED 9 passed / 7 failed；含 `fastbull_parse_snapshot_has_20_unique_items`, `fastbull_parse_title_name_outside_news_list_is_not_picked_up` | 綠（exit 0）：ok 16 passed / 0 failed |
| 3.1b | `cargo test fastbull_parse` | `src/fastbull.rs`: 0 parsed items no longer an error | 紅（exit 101）：FAILED 12 passed / 4 failed；含 `fastbull_parse_zero_items_is_error`, `fastbull_parse_renamed_class_is_error` | 綠（exit 0）：ok 16 passed / 0 failed |
| 3.2a | `cargo test fastbull_fetch` | `src/fastbull.rs`: non-200 no longer an error | 紅（exit 101）：FAILED 5 passed / 1 failed；`fastbull_fetch_non_200_is_error_for_403_429_500_and_unfollowed_redirect` | 綠（exit 0）：ok 6 passed / 0 failed |
| 3.2b | `cargo test fastbull_fetch` | `src/fastbull.rs`: no User-Agent | 紅（exit 101）：FAILED 5 passed / 1 failed；`fastbull_fetch_sends_nonempty_user_agent_and_only_get` | 綠（exit 0）：ok 6 passed / 0 failed |
| 4.1 | `cargo test --test e2e_local` | `src/engine.rs`: seen-set never filled -> resend old items | 紅（exit 101）：FAILED 0 passed / 1 failed；`e2e_local_snapshot_then_items_then_error_then_recovery_without_resending` | 綠（exit 0）：ok 1 passed / 0 failed |

備註：
- 2.3 的第一輪「綠」出現過一次不穩定：`lifecycle_stdout_every_line_is_a_valid_protocol_message` 在固定 1.2 秒視窗內預期 >= 3 行而失敗一次。判斷為我方測試的固定時間窗太緊（不是 helper 行為問題）；已改為逐行耐心等待（每行最多 10 秒），之後連跑 6 次全綠，並重跑 2.3 突變確認仍會紅（上表為重跑結果）。
- 1.5 第一次突變打到註解而沒生效（紅 exit 0），已修正突變目標後重跑，上表為重跑結果。
- 突變腳本不在專案內；要重現請手動做「故意破壞」欄的單行修改，再跑對應指令。

## 發送端過濾（使用者 2026-10-24 決定）

`Emitter`：逐個 item 以 `item.schema.json` 驗證，不合格的丟掉、另發 `status`（`state: error`，`message` 描述被丟棄的 id 與原因）；過濾後無合法 item 則不發 `items`／`snapshot`，只發警告；整則序列化後再驗證（含順序、1,048,576 位元組上限），不過則不輸出並發警告。測試：`emitter_filter_*`、`emitter_oversize_*`、`emitter_wrong_order_*`、`emitter_contract_every_line_written_is_valid_even_for_reject_samples`。

## 需使用者確認的重要發現：快照有 70 個 `div.news-list[data-id]`

規格與設計文件寫「`div.news-list[data-id]` 共 20 則」。對 `docs/fixtures/express-news-2026-10-24.html` 實測：整份文件共 **70** 個——`#side_fast_news` 內 20 個、`#main-content` 內 50 個（前 20 個與側欄逐筆相同）。為符合規格要求的「恰 20 則」，本實作限定 `#side_fast_news`（`fastbull::LIST_SCOPE`）。要取側欄 20 則或主內容 50 則，請使用者決定；已更正 `specs/fastbull-connector/spec.md` 與 `design.md` 並標【假設】。測試：`fastbull_parse_fixture_has_70_news_list_elements_but_only_the_side_list_is_taken`。若頁面改版使側欄消失，解析 0 則 -> `status: error`（安全失敗）。

## 任務 4.2：手動驗證（唯一一次連正式站，2026-10-24 18:47–18:48 CST）

做法：`cd ticker-connect && (sleep 35 | ./target/debug/ticker-connect)`（間隔 10 秒、心跳 25 秒；約 35 秒後 stdin EOF 結束），僅此一次。

結果：**成功**。
- stdout 共 2 行：1 則 `snapshot`（20 則）與 1 則心跳 `status ok`（約 25 秒時）。
- stderr：`polling https://www.fastbull.com/tw/express-news every 10s`、`stdin closed, exiting`；無任何 TLS／連線錯誤；結束代碼 0。
- 約 4 次 GET（0、10、20、30 秒），之後無新訊息，所以只有 snapshot＋心跳，符合預期。
- **環境限制（如實）**：執行當下 `scutil --proxy` 顯示沒有設定系統 HTTP／HTTPS proxy，環境變數也沒有 proxy 設定；`scutil --nc list` 只有一個 Tailscale 設定且為 Disconnected。因此這次**不是**在實際的 VPN／Proxy 路徑下驗證。結論只能說「在目前這台機器的直連環境下，rustls（平台憑證驗證器）可連上正式站」；**VPN／Proxy 下 TLS 仍為【待驗證】**。reqwest 預設啟用 `system-proxy`（會讀 macOS 系統 proxy 設定），在有 proxy 的環境下的行為未測過。

## 待確認／假設清單（與 design.md 逐項一致）

已決定（使用者 2026-10-24）：發送端過濾並另發 `status error`；無合法 item 不發空訊息；退避期間仍發心跳、`status` 至少每 30 秒；snapshot 新到舊、items 舊到新、相同毫秒允許；協定以 `protocol/` 已實作 schema 為準。

仍為【假設】／待確認（使用者未反對而沿用，未升級為已確認）：
1. 服務條款未逐條閱讀【待使用者確認】；robots.txt 對此路徑無規則。
2. VPN／Proxy 下 TLS【待驗證】（見上，僅直連環境成功一次）。
3. 5 秒輪詢間隔【待實測】，預設 10 秒。
4. 洪水保護門檻 10【假設】；洪水 snapshot 內容暫定整頁 convert 結果【假設】。
5. seen-set 上限 500、FIFO 淘汰【假設】。
6. `source_id` = `fastbull`；User-Agent 為 `ticker-connect/0.1 (...)`；逾時 連線 5 秒／總 8 秒；不跟隨重新導向（3xx 視為錯誤）【假設】。
7. `text` 修剪前後空白並解碼 HTML 實體；單一元素壞掉則跳過並寫 stderr，全部被跳過視為 0 則錯誤【假設】。
8. stdin EOF 退出容忍 1 秒【假設】（實測遠低於 1 秒）；未實作可選的 `getppid` 保險。
9. 心跳內部週期 25 秒【假設】；相同毫秒的 tie-break =「頁面順序的反向（舊到新時）」【假設】。
10. 解析範圍限定 `#side_fast_news`（見上）【待使用者確認】。
