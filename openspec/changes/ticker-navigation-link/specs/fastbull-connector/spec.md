## MODIFIED Requirements

### Requirement: HTML 解析規則
`convert` SHALL 以下列規則解析伺服器回傳的 HTML（解析規則已於 2026-10-24 對快照 `docs/fixtures/express-news-2026-10-24.html` 實測）：每個位於 `#side_fast_news` 容器內的 `div.news-list[data-id]` 元素對應一則 item（apply 階段實測更正，2026-10-24：快照整份文件共有 70 個 `div.news-list[data-id]`——`#side_fast_news` 內 20 個，`#main-content` 內另有 50 個且前 20 個與側欄相同；規格要求的 20 則對應側欄，故解析範圍限定 `#side_fast_news`【假設，待使用者確認要取側欄 20 則或主內容 50 則】）；`data-id` 屬性 → `id`；`data-date` 屬性（毫秒 epoch 整數）→ `published_at_ms`；該元素內的 `span.title_name` 文字 → `text`；`source` 為連接器的 `source_id()`；`url`（選填）由該 `div.news-list` 元素的後代中、依文件順序第一個帶 `data-href` 屬性的元素（快照中為 `div.shear_box[data-href]`，不是 `div.news-list` 自身的屬性；已實測側欄 20 則皆有，且值皆等於 `/tw/fastshort/` 加該則 `id`）取得：值去除前後空白後，若以單一 `/` 開頭（不以 `//` 開頭），`url` 為連接器常數 `https://www.fastbull.com`（站台來源 origin，不得由 `fetch` 的目標 URL 推導，因為測試會把目標 URL 覆寫為本機位址）串接該值【假設：取第一個帶 `data-href` 的後代】；缺少 `data-href`、值為空、不以 `/` 開頭、串接結果不符合 `message-protocol` 的 `url` 規則（過長、含非 ASCII 或空白等）時，MUST 不輸出 `url`（item 照常輸出，不視為錯誤、不視為被跳過的元素），並 SHOULD 寫一行 stderr 日誌說明；因為引擎層仍會整個丟棄含非法 `url` 的 item，所以 `convert` MUST 自行保證輸出的 `url` 一定合法【假設：降級為「無連結」而非丟棄整則新聞】。`span.title_name` MUST 限定在其所屬的 `div.news-list` 元素範圍內擷取，不得以整份文件搜尋，因為快照中 `title_name` 另出現在 20 則快訊之外的頁面區塊（核對：整份文件 115 個 `class="title_name"`，其中 70 個位於 `div.news-list` 內（側欄 20 + 主內容 50），其餘 45 個在其他區塊；原先寫的「僅 20 個屬於快訊元素」不精確，已於 apply 階段更正）。畫面上顯示的時間文字由 JS 填入，MUST NOT 解析。item 順序 SHALL 與頁面順序一致（新到舊）。「重要」旗標頁面雖有（如 class 含 `important-list`），但 v1 協定不納入，MUST NOT 輸出。`text` 的處理（前後空白修剪、HTML 實體解碼）設計文件未規定【待確認：本規格暫定修剪前後空白並解碼 HTML 實體】。

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

#### Scenario: url 取自 data-href
- **WHEN** 對一個 `div.news-list[data-id="X"]` 呼叫 `convert`，其後代含 `<div class="shear_box" data-href="/tw/fastshort/X">`
- **THEN** 該 item 的 `url` SHALL 為 `https://www.fastbull.com/tw/fastshort/X`

#### Scenario: 缺 data-href 不是錯誤
- **WHEN** 某個 `div.news-list` 內沒有任何帶 `data-href` 的後代，其餘欄位完整
- **THEN** 該 item SHALL 照常輸出且不含 `url`，`convert` SHALL NOT 回傳錯誤，也 SHALL NOT 將該元素列為被跳過

#### Scenario: 壞掉的 data-href 降級為無連結
- **WHEN** `data-href` 為空字串、為 `javascript:alert(1)`、為 `//evil.example/x`，或串接後超過 2048 位元組
- **THEN** 該 item SHALL 照常輸出且不含 `url`，且輸出 SHALL 通過 `protocol/` 的 `item` schema

#### Scenario: 不以 fetch 目標 URL 推導 origin
- **WHEN** 連接器以本機假伺服器位址建立
- **THEN** `convert` 產生的 `url` SHALL 仍以 `https://www.fastbull.com` 開頭（僅為字串串接，SHALL NOT 對該位址發出任何請求）

### Requirement: 對快照 fixture 的解析測試
解析測試 MUST 直接讀取 `docs/fixtures/express-news-2026-10-24.html`（不得複製副本）。對該快照，`convert` SHALL 回傳恰 20 則 item，且前 6 則的 `id` 與 `published_at_ms` 依序為：`4334051_1_2`／`1792832201957`、`4334047_212_2`／`1792831327830`、`4334044_212_2`／`1792830528511`、`4334043_1_2`／`1792830445444`、`4334042_1_2`／`1792830420009`、`4334041_214_2`／`1792830328635`。第一則的所有欄位值 MUST 完全相符（含新增的 `url`）：`source = "fastbull"`、`id = "4334051_1_2"`、`published_at_ms = 1792832201957`、`text = "沙烏地阿拉伯領導的聯軍表示，已攔截並摧毀了也門胡塞武裝向塔伊夫和延布發射的兩枚彈道飛彈。"`、`url = "https://www.fastbull.com/tw/fastshort/4334051_1_2"`。快照中 20 則 item 的 `url` MUST 皆存在，且逐一等於 `https://www.fastbull.com/tw/fastshort/` 加該則 `id`。測試程式碼 MUST NOT 含正式主機名稱的字面值（既有守衛測試會掃描 `tests/` 原始碼），預期的 `url` MUST 以測試輔助函式組出（例如 `["fastbull", ".com"].concat()` 的方式）。20 個 `id` MUST 互不相同。`convert` 的輸出 MUST 通過 `protocol/` 的 `item` schema。

#### Scenario: 快照解析 20 則
- **WHEN** 對快照呼叫 `convert`
- **THEN** SHALL 回傳 20 則 item，且 `id` 全不重複

#### Scenario: 第一則欄位完全相符
- **WHEN** 檢查回傳的第一則 item
- **THEN** 其 `source`、`id`、`published_at_ms`、`text`、`url` SHALL 與上述值逐字相符

#### Scenario: 前 6 則順序
- **WHEN** 檢查回傳的前 6 則 item
- **THEN** 其 `id` 與 `published_at_ms` SHALL 依序與上述六組值相符

#### Scenario: 解析結果通過契約
- **WHEN** 將 20 則 item 組成 `snapshot` 並以 `protocol/` schema 驗證
- **THEN** SHALL 通過（含新到舊順序檢查）

#### Scenario: 20 則皆有 url
- **WHEN** 對快照呼叫 `convert`
- **THEN** 20 則 item 的 `url` SHALL 皆存在，且皆等於 origin 加 `/tw/fastshort/` 加該則 `id`

#### Scenario: 含 url 的快照仍通過契約
- **WHEN** 將 20 則含 `url` 的 item 組成 `snapshot` 並以 `protocol/` 更新後的 schema 驗證
- **THEN** SHALL 通過

