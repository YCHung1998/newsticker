## ADDED Requirements

### Requirement: FastBull 連接器身分與設定
FastBull 連接器 SHALL 實作 `Connector`，`source_id()` 為固定字串 `fastbull`【識別值為本規格暫定，設計文件未指定，待確認】，目標 URL 為 `https://www.fastbull.com/tw/express-news`，預設 `interval()` 為 10 秒。URL MUST 可由設定覆寫（供本機假伺服器測試使用）。輪詢間隔在實測連續請求會拿到新資料之前 SHALL NOT 宣稱可降到 5 秒；降到 5 秒須另行驗證後再決定。

#### Scenario: 預設間隔
- **WHEN** 建立預設設定的 FastBull 連接器
- **THEN** `interval()` SHALL 回傳 10 秒，`source_id()` SHALL 回傳 `fastbull`

#### Scenario: URL 可覆寫
- **WHEN** 以本機假伺服器位址建立連接器
- **THEN** `fetch` SHALL 只對該位址發出請求

### Requirement: HTML 解析規則
`convert` SHALL 以下列規則解析伺服器回傳的 HTML（解析規則已於 2026-10-24 對快照 `docs/fixtures/express-news-2026-10-24.html` 實測）：每個位於 `#side_fast_news` 容器內的 `div.news-list[data-id]` 元素對應一則 item（apply 階段實測更正，2026-10-24：快照整份文件共有 70 個 `div.news-list[data-id]`——`#side_fast_news` 內 20 個，`#main-content` 內另有 50 個且前 20 個與側欄相同；規格要求的 20 則對應側欄，故解析範圍限定 `#side_fast_news`【假設，待使用者確認要取側欄 20 則或主內容 50 則】）；`data-id` 屬性 → `id`；`data-date` 屬性（毫秒 epoch 整數）→ `published_at_ms`；該元素內的 `span.title_name` 文字 → `text`；`source` 為連接器的 `source_id()`。`span.title_name` MUST 限定在其所屬的 `div.news-list` 元素範圍內擷取，不得以整份文件搜尋，因為快照中 `title_name` 另出現在 20 則快訊之外的頁面區塊（核對：整份文件 115 個 `class="title_name"`，其中 70 個位於 `div.news-list` 內（側欄 20 + 主內容 50），其餘 45 個在其他區塊；原先寫的「僅 20 個屬於快訊元素」不精確，已於 apply 階段更正）。畫面上顯示的時間文字由 JS 填入，MUST NOT 解析。item 順序 SHALL 與頁面順序一致（新到舊）。「重要」旗標頁面雖有（如 class 含 `important-list`），但 v1 協定不納入，MUST NOT 輸出。`text` 的處理（前後空白修剪、HTML 實體解碼）設計文件未規定【待確認：本規格暫定修剪前後空白並解碼 HTML 實體】。

#### Scenario: 解析欄位來源
- **WHEN** 對一個含 `<div class="news-list ..." data-id="X" data-date="1792832201957">` 且內含 `<span class="title_name">T</span>` 的 HTML 呼叫 `convert`
- **THEN** 回傳的 item SHALL 為 `id = "X"`、`published_at_ms = 1792832201957`、`text = "T"`、`source = "fastbull"`

#### Scenario: 不解析畫面時間文字
- **WHEN** 元素內含畫面時間文字且與 `data-date` 不一致
- **THEN** `published_at_ms` SHALL 取自 `data-date`

#### Scenario: title_name 限定範圍
- **WHEN** 文件在最後一則快訊元素之後仍含其他 `span.title_name`
- **THEN** 這些額外的 `span.title_name` SHALL NOT 成為任何 item 的 `text`，也 SHALL NOT 產生額外 item

#### Scenario: 重要旗標不輸出
- **WHEN** 元素 class 含 `important-list`
- **THEN** 該 item SHALL 與一般 item 欄位相同，不含任何旗標欄位

### Requirement: 對快照 fixture 的解析測試
解析測試 MUST 直接讀取 `docs/fixtures/express-news-2026-10-24.html`（不得複製副本）。對該快照，`convert` SHALL 回傳恰 20 則 item，且前 6 則的 `id` 與 `published_at_ms` 依序為：`4334051_1_2`／`1792832201957`、`4334047_212_2`／`1792831327830`、`4334044_212_2`／`1792830528511`、`4334043_1_2`／`1792830445444`、`4334042_1_2`／`1792830420009`、`4334041_214_2`／`1792830328635`。第一則的所有欄位值 MUST 完全相符：`source = "fastbull"`、`id = "4334051_1_2"`、`published_at_ms = 1792832201957`、`text = "沙烏地阿拉伯領導的聯軍表示，已攔截並摧毀了也門胡塞武裝向塔伊夫和延布發射的兩枚彈道飛彈。"`。20 個 `id` MUST 互不相同。`convert` 的輸出 MUST 通過 `protocol/` 的 `item` schema。

#### Scenario: 快照解析 20 則
- **WHEN** 對快照呼叫 `convert`
- **THEN** SHALL 回傳 20 則 item，且 `id` 全不重複

#### Scenario: 第一則欄位完全相符
- **WHEN** 檢查回傳的第一則 item
- **THEN** 其 `source`、`id`、`published_at_ms`、`text` SHALL 與上述值逐字相符

#### Scenario: 前 6 則順序
- **WHEN** 檢查回傳的前 6 則 item
- **THEN** 其 `id` 與 `published_at_ms` SHALL 依序與上述六組值相符

#### Scenario: 解析結果通過契約
- **WHEN** 將 20 則 item 組成 `snapshot` 並以 `protocol/` schema 驗證
- **THEN** SHALL 通過（含新到舊順序檢查）

### Requirement: 解析 0 則為錯誤
`convert` 在 HTML 中找不到任何 `#side_fast_news div.news-list[data-id]`（例如頁面改版、被導向驗證頁、空字串）時 MUST 回傳 `ConnectError`，不得回傳空清單。單一元素缺少 `data-id`、`data-date` 不是整數或缺少 `span.title_name` 時的處置（跳過該元素，或整頁視為錯誤）設計文件未規定【待確認：本規格暫定跳過該元素並寫 stderr 日誌，且若全部元素皆被跳過則視為 0 則錯誤】。

#### Scenario: 空 HTML
- **WHEN** 對空字串或不含快訊元素的 HTML 呼叫 `convert`
- **THEN** SHALL 回傳錯誤，而不是空清單

#### Scenario: 頁面改版
- **WHEN** HTML 仍為 200 內容，但 `div.news-list` 的 class 已改名
- **THEN** `convert` SHALL 回傳錯誤，使引擎發出 `status: error`

#### Scenario: 單一元素壞掉【待確認】
- **WHEN** 20 個元素中有一個 `data-date` 不是整數
- **THEN** `convert` SHALL 回傳其餘 19 則並將該筆記入 stderr【待確認：跳過或整頁失敗】

### Requirement: HTTP 抓取行為
`fetch` SHALL 以 HTTP GET 取得頁面本文，並 MUST 設定 `User-Agent` 標頭、連線與整體請求逾時。具體 User-Agent 字串與逾時秒數設計文件未規定【待確認：本規格暫定使用可辨識本工具的 User-Agent，總逾時小於輪詢間隔（暫定 8 秒）】。回應狀態碼非 200（含 3xx 未跟隨、403、429、5xx）MUST 視為錯誤並回傳 `ConnectError`；逾時、DNS／連線失敗同樣為錯誤。重新導向的處置設計文件未規定【待確認：是否跟隨】。`fetch` MUST NOT 發送會改變伺服器狀態的請求，且同一時間 MUST NOT 有多個進行中的請求（上一個未完成前不得開始下一個輪詢）。

#### Scenario: 200 回應
- **WHEN** 本機假伺服器對 GET 回 200 與快照 HTML
- **THEN** `fetch` SHALL 回傳本文，`convert` 之後 SHALL 解析出 20 則

#### Scenario: 帶 User-Agent
- **WHEN** 假伺服器檢查收到的請求標頭
- **THEN** SHALL 含非空的 `User-Agent`

#### Scenario: 非 200 為錯誤
- **WHEN** 假伺服器回 403、429 或 500
- **THEN** `fetch` SHALL 回傳錯誤，且不改變 seen 狀態

#### Scenario: 逾時
- **WHEN** 假伺服器延遲回應超過逾時設定
- **THEN** `fetch` SHALL 在逾時設定內回傳錯誤，且 SHALL NOT 無限期阻塞

#### Scenario: 不重疊的請求
- **WHEN** 上一次請求仍在進行中，輪詢時間點已到
- **THEN** 引擎 SHALL 等待該請求結束（或逾時）後才開始下一次

### Requirement: 禁止連線正式網站與待驗證事項
所有 FastBull 相關自動化測試 MUST 只對本機假伺服器或本地 fixture 檔案進行，MUST NOT 向 `fastbull.com` 發送請求。下列事項 MUST 在規格中維持未確認狀態，不得宣稱已解決：(1) 服務條款尚未逐條閱讀【待使用者確認】，robots.txt 僅限制 Baiduspider／Googlebot，對此路徑無規則；(2) 在 VPN／Proxy 環境下 Rust TLS 與 proxy 行為未驗證，須在 apply 階段以實際網路另行手動驗證並記錄【待驗證】；(3) 輪詢間隔 5 秒是否可行未驗證，預設 10 秒。WebSocket（STOMP over SockJS）來源不在本 change 範圍。

#### Scenario: 測試程式碼不含正式 URL 的請求
- **WHEN** 檢查 `ticker-connect` 的測試與測試輔助程式
- **THEN** SHALL 找不到對 `fastbull.com` 發出請求的路徑（正式 URL 只能作為預設設定常數出現）

#### Scenario: 未確認事項保持標記
- **WHEN** 閱讀本 change 的 spec 與 design
- **THEN** 服務條款、VPN／Proxy TLS 與 5 秒間隔 SHALL 仍標示為待使用者確認／待驗證，不得出現「已確認可行」的敘述
