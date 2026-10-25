# 新增資料來源手冊（給沒有背景的 LLM／工程師）

只讀這份文件就能把一個新網站（例如即時快訊頁）接進跑馬燈。路徑皆相對於 repo 根目錄（clone 下來的 `newsticker/`）。

## 0. 目標與成功標準

**目標**：新增一個 Rust 連接器 + fixture + 測試，並在登錄表加幾行。**Swift App、`protocol/`、引擎共用邏輯零改動。**

**完成時應看到**（全部要實際跑過）：

1. `cd ticker-connect && cargo run --quiet -- --list-sources` 印出 `fastbull` 與你的來源 id（一行一個）。
2. `cd ticker-connect && cargo test` 全綠，數量比開工前多（你的解析與抓取測試）；`cargo build` 0 warning。
3. `python3 -m unittest discover -s protocol/tests` 全綠（你沒改 `protocol/`，應與開工前相同）。
4. 一次低頻手動實測（第 3 章 步驟 h）：stdout 有 1 則 `snapshot`，約 25 秒後有 1 則 `status`（`state: ok`）；每行都通過協定驗證。
5. `git status` 只出現第 1 章「你要新增／小改」的檔案。

## 先決條件

```sh
rustc --version      # 驗證時為 1.98.0；Cargo.toml 用 edition = "2024"，需要 >= 1.85
cargo --version
python3 -c "import jsonschema; print(jsonschema.__version__)"   # 4.x，協定測試用
curl --version
```
`cargo` 第一次建置要下載相依套件（需要網路，之後離線可用）。macOS 沒有 `timeout` 指令，不要用它。

## 本專案的工作規則（精簡版）

- **TDD 有證據**：先寫測試並看到它失敗（紅），再實作到綠。回報要附指令與輸出摘要，不能只說「測試綠了」。
- **不得放寬斷言**：測試失敗就修程式或 fixture，不是改測試讓它過。偶發失敗要重跑並如實記錄。
- **失敗誠實**：做不到、沒驗證的就寫「未驗證」。不要宣稱沒跑過的東西通過。
- 自動測試**只准連 `127.0.0.1`**，不准連真實網站；真實網站只在步驟 h 打一次。
- **不要 commit／push／切分支／merge**，除非被明確要求。分支與合併規則見 `CLAUDE.md` 的 Git workflow（一個 change 一個 `change/<name>` 分支）。
- 不要動第 1 章列為「絕不能動」的檔案。需要動它們代表你誤解了需求，請停下來回報（第 5 章）。

## 1. 架構一頁圖

```
 目標網站 ──HTTP GET──▶ ticker-connect（Rust，獨立行程）                    Swift App
                          ┌──────────────────────────────────────┐        ┌────────────────────┐
                          │ 來源專屬：src/<id>.rs                 │        │ 只認協定，不認來源  │
                          │   Connector::fetch()  抓文字          │ stdout │ 顯示 item.text      │
                          │   Connector::convert() 純函式→Vec<Item>│ JSON   │ 點擊開 item.url     │
                          │ 共用（不要動）：                      │ lines  │ 標籤文字來自        │
                          │   scheduler 輪詢/退避/心跳            │───────▶│ style.json labelText│
                          │   engine    去重/基準/洪水保護         │        └────────────────────┘
                          │   emitter   輸出前 schema 驗證+過濾    │
                          └──────────────────────────────────────┘
                          stdin EOF = 結束；日誌走 stderr；stdout 只有協定行
```

| 類別 | 檔案 |
|---|---|
| **你要新增** | `ticker-connect/src/<id>.rs`、`ticker-connect/tests/<id>_parse.rs`、`ticker-connect/tests/<id>_fetch.rs`、`ticker-connect/tests/fixtures/<id>/*` |
| **你要小改（各加幾行）** | `ticker-connect/src/lib.rs`（一行 `pub mod <id>;`）、`ticker-connect/src/sources.rs`（`use`、`REGISTRY` 一行、`dispatch` 一個 match 分支） |
| **可選** | `ticker-connect/README.md`（記錄你的來源）、style.json 的 `labelText`（使用者本機設定，不是 repo 檔案） |
| **絕不能動** | `protocol/**`、`Sources/**`、`Tests/**`（Swift）、`ticker-connect/src/{engine,scheduler,emitter,protocol,model,connector,http,timeutil,main}.rs`、`openspec/specs/**`、`ticker-connect/src/fastbull.rs`、其他來源的檔案 |
| **可以用（共用工具）** | `crate::http::HttpFetcher`（GET、逾時、User-Agent、自訂標頭）、`crate::timeutil::parse_datetime`／`civil_to_unix_ms`（民用時間 + 固定位移 → UTC 毫秒） |

## 2. 協定契約速查（與程式逐條核對過）

來源：`protocol/schema/*.json`、`ticker-connect/src/{model,protocol,engine,emitter,scheduler}.rs`。helper 的 stdout 每行是一個 JSON 物件（`\n` 結尾，UTF-8），三種：

```json
{"v":1,"type":"snapshot","items":[ ...新到舊... ]}
{"v":1,"type":"items","items":[ ...舊到新... ]}
{"v":1,"type":"status","source":"<id>","state":"ok","message":""}
```

`item` 欄位（`additionalProperties: false`，不得有其他欄位；`title`、`important` 為 jin10 加入的選填欄位）：

| 欄位 | 必填 | 規則 |
|---|---|---|
| `source` | 是 | 非空字串；**必須等於你的 `SOURCE_ID`**（範本已處理） |
| `id` | 是 | 非空字串；**穩定**（同一則訊息每次輪詢都相同）且**在該來源內唯一**；引擎只用它去重 |
| `published_at_ms` | 是 | 整數 >= 0，**UTC epoch 毫秒**（不是秒、不是字串、不是浮點） |
| `text` | 是 | 非空字串；協定**沒有長度上限**（只受單行 1 MiB 限制）；請去掉 HTML 標籤、把連續空白與換行收斂成單一空格 |
| `url` | 否 | 缺少 = 無連結；**絕不輸出 `null`**。存在時：1–2048 位元組、只含可見 ASCII（`0x21`–`0x7E`，非 ASCII 要 percent-encode）、scheme 為小寫 `http`／`https`、`://` 後第一個字元為英數或 `[`、不得含空白或結尾換行。違規會讓**整則 item 被丟棄** |
| `title` | 否 | 缺少 = 無標題；**絕不輸出 `null` 或空字串**。顯示時粗體，位於時間與 `text` 之間；不要把同一段標題再放進 `text`（change `jin10-source` 新增） |
| `important` | 否 | 布林；只在來源標示為重要時輸出 `true`，其餘不要輸出（App 以紅色顯示該則的標題；`null`、非布林會讓整則被丟棄） |

其他規則：

- 單行上限 1,048,576 位元組；超過不輸出並發 `status: error`。
- `snapshot` 的 `published_at_ms` 非遞增（新到舊）、`items` 非遞減（舊到新）；相鄰相等合法。`items`／`snapshot` 的 `items` 不可為空。
- 心跳：helper 至少每 30 秒（內部 25 秒）發一則 `status`，含失敗退避期間。這是引擎做的，你不用管。
- 接收端（Swift）只要有一個 item 非法就**整則丟棄**；所以 helper 的 `emitter` 會先過濾不合格 item 並另發 `status: error`——但這代表你的壞資料會變成「少了訊息」，要在你自己的 `convert` 就處理好。

**引擎自動做的事（你不用寫）**：第一次成功輪詢發 `snapshot`；之後只發 id 不在 seen-set（上限 500，FIFO 淘汰）的新 item，用 `items`（舊到新）；單次新訊息 > 10 則改發新的 `snapshot`（洪水保護）；沒有新訊息就不發；`convert` 回空清單或錯誤 → `status: error` + 退避 10→30→60 秒（interval × 1、3、6），**且不改變 seen-set**；同頁重複 id 只保留第一個；`snapshot`／`items` 內部再依 `published_at_ms` 排序（相同值保持頁面順序）。

**Connector 必須負責的事**：

1. `convert` 是**純函式**（相同輸入相同輸出，不讀時鐘、不做 I/O）。
2. 回傳順序＝來源頁面順序，且為**新到舊**。
3. `id` 穩定且來源內唯一（不要用陣列索引、不要用每次會變的值）。
4. 時間轉成 UTC 毫秒。
5. 壞資料降級原則：**單一元素壞掉 → 跳過它並寫 stderr，其餘照常輸出**；**可選欄位（`url`）壞掉 → 只丟那個欄位，item 照常輸出**；**解析出 0 則 → 回傳 `Err(ConnectError::Parse(..))`**（絕不回傳空 `Vec`，也不當成「沒有新訊息」）。
6. `DEFAULT_INTERVAL` >= 10 秒（`cargo test --test sources_registry` 會檢查）。對對方網站要客氣：預設就好，不要調快。
7. 不得在 repo 內放 cookie、token、帳號密碼；需要這些的來源 v1 不支援（第 5 章）。

## 3. 逐步流程

以下以 `ID=jin10`、`TYPE=Jin10` 為例（`ID`：小寫字母開頭、小寫英數與底線、2–32 字元；`TYPE`：CamelCase，用在 Rust 型別名）。指令都在 repo 根目錄開始；進入 `ticker-connect/` 的步驟會明寫 `cd`。

### 步驟 a：勘查目標網站（先確認可不可以抓）

```sh
curl -sS https://目標網域/robots.txt | head -40          # 有沒有 Disallow 你要抓的路徑？
```
並閱讀網站的使用條款（Terms）。**把結果記在你的回報中**：robots 規則、條款是否禁止自動抓取、你怎麼判斷。條款禁止或 robots 明確禁止 → 停下來回報（第 5 章）。

**條款在哪裡找**：看首頁頁尾連結（「使用條款」「用戶協議」「版權聲明」「About」「Terms」「Privacy」）；單頁應用（SPA）的連結常藏在 JS bundle 裡，可 `grep -o 'about[^"]*\|terms[^"]*\|agreement[^"]*'` 找路徑。

**判準（誠實且保守）**：
- robots.txt 只有註解、沒有 `Disallow`：視為沒有限制，但仍要讀條款。
- 條款**明文禁止**自動抓取／機器存取 → 停止並回報。
- 條款只有一般性的**版權聲明**（禁止轉載、複製、摘編）、沒有提到自動抓取：可以繼續做，**但必須在回報中標註「有版權聲明，是否合規請人類最終裁決」**，並維持：低頻（≥10 秒）、只顯示標題文字與連回原文的連結、不在 repo 內存放大量第三方內容。
- 看不到任何條款：在回報中說明「找不到條款」，同樣標註風險，交由人類決定。

**單頁應用（SPA）／沒有瀏覽器時如何找資料端點**：首頁 HTML 若只有 `<div id="app">` 之類空殼，資料是由 JS 呼叫 API 取得。沒有瀏覽器開發者工具時：`curl` 下載首頁，從 `<script src=...>` 取出該站自己的 JS bundle（只下載首頁引用的幾個檔案，算作勘查請求），用 `grep -o 'https\?://[^"'"'"' ]*api[^"'"'"' ]*\|/get_[a-z_]*\|/api/[a-zA-Z0-9_/]*'` 找 API 網域與路徑，再用 `curl` 試打一次確認回應是 JSON。勘查請求都要克制（個位數次）。

接著看資料怎麼來。開瀏覽器開發者工具的 Network 分頁（或用 `curl`）找出載入清單的請求：

```sh
curl -sS -A "Mozilla/5.0" -o /tmp/probe.out -w "%{http_code} %{content_type} %{size_download}\n" "https://目標網址"
head -c 1500 /tmp/probe.out
```
判斷屬於哪一型：

| 型別 | 特徵 | 作法 |
|---|---|---|
| A. 伺服器渲染 HTML | 原始碼直接含清單與文字 | 用 `scraper`（CSS 選擇器），參考 `src/fastbull.rs` |
| B. 內嵌 JSON | HTML 內有 `<script>` 裡的 JSON（如 `__NEXT_DATA__`、`window.__INITIAL_STATE__`） | 先取出該段文字再用 `serde_json` |
| C. 公開 JSON API | Network 分頁看得到不需登入的 `GET` 回傳 JSON | 直接 `serde_json`；範本就是這型（需要標頭就填 `EXTRA_HEADERS`） |
| D. 需要 WebSocket／登入／簽章／驗證碼 | 清單只透過 WS 推送、或請求帶一次性 token | **v1 不支援**，停下來回報（第 5 章），不要硬做 |

找出三樣東西並記錄：**穩定的 `id` 欄位**、**時間欄位**（毫秒？秒？字串？哪個時區？）、**文字欄位**，以及是否有可用的原文連結。確認新舊順序（第一筆是最新還是最舊）。**只請求少數幾次，不要迴圈、不要高頻。**

### 步驟 b：儲存最小化 fixture

```sh
mkdir -p ticker-connect/tests/fixtures/jin10
# 把步驟 a 的回應存成 ticker-connect/tests/fixtures/jin10/sample.json（HTML 來源用 sample.html）
```
- 只留解析所需：JSON 就只留清單前 3–20 筆、刪掉用不到的欄位與大型區塊；HTML 就保留清單容器與 3–20 筆，並**保留會干擾解析的結構**（例如清單外的相同 class，見第 4 章陷阱 1）。縮減後用 `python3 -m json.tool` 或瀏覽器確認仍是合法 JSON／HTML。
- 這是第三方內容：不要存個資、cookie、token、完整頁面（動輒數百 KB）。數 KB 即可。
- 保持檔案是原始回應的子集合（不要手編造值），這樣日後頁面改版才看得出差異。

### 步驟 c：從範本建立來源

範本在 `docs/templates/`，佔位符 `{{id}}`、`{{Type}}`：

```sh
cd ticker-connect
ID=jin10; TYPE=Jin10; T=../docs/templates
sed -e "s/{{id}}/$ID/g" -e "s/{{Type}}/$TYPE/g" $T/source.rs.tmpl        > src/$ID.rs
sed -e "s/{{id}}/$ID/g" -e "s/{{Type}}/$TYPE/g" $T/source_parse_test.rs.tmpl > tests/${ID}_parse.rs
sed -e "s/{{id}}/$ID/g" -e "s/{{Type}}/$TYPE/g" $T/source_fetch_test.rs.tmpl > tests/${ID}_fetch.rs
mkdir -p tests/fixtures/$ID
[ -e tests/fixtures/$ID/sample.json ] || cp $T/sample.json.tmpl tests/fixtures/$ID/sample.json   # 步驟 b 已存就不覆蓋
```
產生的 `src/$ID.rs` 內有可運作的**玩具** JSON 實作與 `TODO(source)` 標記。**建議順序：a → b → c → e（只做登錄並編譯，確認 `--list-sources` 看得到新 id）→ d（先寫解析測試、先紅）→ f → g → h → i → j。** 步驟 c 產生的檔案要先在步驟 e 登錄才編得到，所以 e 排在 d 之前。

### 步驟 d：先寫解析測試（先紅）

編輯 `tests/${ID}_parse.rs`：把 `TODO(source)` 的數量與「第一則精確值」換成你 fixture 的真實值（`id`、`published_at_ms`、`text`、`url`——每個欄位都精確比對）。跑：

```sh
cargo test --test ${ID}_parse        # 預期：失敗（紅），因為 parse_payload 還是玩具實作
```
再實作 `src/$ID.rs` 的 `parse_payload`（以及 `DEFAULT_URL`、`EXTRA_HEADERS`、時區）直到：

```sh
cargo test --test ${ID}_parse        # 預期：全綠，數量至少 6（你可以多加案例；不要用「恰好 6 個」做機械比對）
```
測試至少要涵蓋（範本已有骨架）：fixture 數量與唯一 id、新到舊、第一則精確值、輸出通過 `Protocol`、空／壞輸入 → 錯誤、壞元素被跳過、純函式。**時間欄位用 fixture 的真實值驗證**（例如 `published_at_ms > 1_000_000_000_000`）。

### 步驟 e：登錄來源

三處修改（都是加幾行，照 FastBull 的樣子）：

```rust
// ticker-connect/src/lib.rs —— 加一行
pub mod jin10;

// ticker-connect/src/sources.rs
use crate::jin10::{self, Jin10Connector};                       // 檔頭
pub const REGISTRY: &[SourceEntry] = &[
    SourceEntry { id: fastbull::SOURCE_ID, default_url: fastbull::DEFAULT_URL },
    SourceEntry { id: jin10::SOURCE_ID, default_url: jin10::DEFAULT_URL },   // 新增
];
// dispatch() 的 match 內，放在 `_ =>` 之前：
        jin10::SOURCE_ID => Ok(visitor.call(Jin10Connector::new(url, opts.interval.unwrap_or(jin10::DEFAULT_INTERVAL)).map_err(DispatchError::Build)?)),
```
```sh
cargo run --quiet -- --list-sources      # 預期兩行：fastbull、jin10
cargo run --quiet -- --source nope; echo "exit=$?"   # 預期 stderr 列出可用 id，exit=2
```

### 步驟 f：抓取測試與守衛規則

編輯 `tests/${ID}_fetch.rs`：把 `PATH` 換成真實 API 的**路徑與查詢字串**。

**守衛規則（最容易踩）**：`cargo test --test no_external_network` 會從登錄表的每個 `default_url` 取出「最後兩段網域」（如 `jin10.com`），掃描 `tests/*.rs` 與 `tests/common/*.rs` 的**原始文字**（含註解、字串）。出現就失敗。因此：

```rust
// 錯：任何地方寫出網域（包含註解）
let u = "https://flash-api.jin10.com/get_flash_list";        // 守衛會抓到
// 對：測試只寫路徑，網域由假伺服器提供
const PATH: &str = "/get_flash_list?max_time=&channel=-8200";
let url = server.url_for(PATH);                              // http://127.0.0.1:<port>/get_flash_list?...
// 對：若斷言需要絕對連結，網域用拼接組出
let origin = format!("https://www.{}", ["jin10", ".com"].concat());
```
`FakeServer`、`spawn_helper_with`、`fixture()` 都在 `tests/common/mod.rs`。`FakeServer` 的 200 回應固定帶 `Content-Type: text/html; charset=utf-8`（對 JSON 內容也可用；只在你的來源依賴 Content-Type 時才需要改 `common`，通常不需要）。

```sh
cargo test --test ${ID}_fetch
cargo test --test no_external_network
```

### 步驟 g：跨語言契約與全套測試

```sh
cargo test                                            # ticker-connect 全套（含 emitter_contract：讀 protocol/fixtures/manifest.json）
cd .. && python3 -m unittest discover -s protocol/tests   # Python 參考驗證器；你沒改 protocol/，應與開工前結果相同
grep -rn "TODO(source)" ticker-connect/src ticker-connect/tests   # 預期：無輸出（範本標記都處理完）
```

### 步驟 h：一次低頻手動實測

```sh
cd ticker-connect && cargo build
(sleep 35 | ./target/debug/ticker-connect --source jin10) > /tmp/jin10.out 2> /tmp/jin10.err
cat /tmp/jin10.err ; wc -l /tmp/jin10.out ; cut -c1-200 /tmp/jin10.out
```
預期：`/tmp/jin10.err` 含 `source jin10: polling <URL> every 10s` 與 `stdin closed, exiting`；`/tmp/jin10.out` 恰有 1 則 `{"v":1,"type":"snapshot",...}`，約 25 秒時再多 1 則 `"type":"status"`、`"state":"ok"`（35 秒內約打 4 次 GET）。逐行驗證：

```sh
cd .. && python3 -c "
import sys; sys.path.insert(0,'protocol'); import refcheck
for l in open('/tmp/jin10.out'): print(refcheck.check_line(l.rstrip('\n').encode()))"
# 預期每行都是 (True, None)
```
**只做這一次**，不要用迴圈、不要縮短間隔去打真實網站。若出現 `status: error`（403、解析 0 則等），不要硬調到通過——記錄 stderr 原文並依第 5 章處理。

### 步驟 i：在 App 中使用

App 只認協定，所以不用改 Swift。選來源用環境變數（`open` 不會傳環境變數，直接執行 App 內的程式）：

```sh
make helper app sign          # 組出含新 helper 的 build/FastBullTicker.app
NEWSTICKER_SOURCE=jin10 build/FastBullTicker.app/Contents/MacOS/FastBullTicker &
```
未設定 `NEWSTICKER_SOURCE` 時行為與以前相同（FastBull）。填了未登錄的 id，helper 會以退出碼 2 結束，App 會依既有退避機制反覆重啟，日誌在 `~/Library/Application Support/FastBullTicker/app.log`。

跑馬燈左側標籤預設寫「即時財經快訊」，與來源無關。要改成新來源的名稱，編輯 `~/Library/Application Support/FastBullTicker/style.json` 的 `labelText`（1–16 字；測試時用 `FASTBULL_TICKER_STYLE=/path/to/tmp.json` 指向暫存檔，不要動真實設定）。若你是 agent，**不要啟動 App**，把這段指令留給人類執行。

### 步驟 j：完整驗證指令清單

```sh
cd ticker-connect && cargo build 2>&1 | grep -c warning      # 預期 0（grep 退出碼 1 是正常的）
cd ticker-connect && cargo test
python3 -m unittest discover -s protocol/tests
openspec validate --all --strict                              # 你沒動 openspec/，應仍通過
git status --short                                            # 只應有第 1 章「你要新增／小改」的檔案
```
（若改了 Swift 才需要 `swift build && swift test`；新增來源不需要。）

## 4. 常見陷阱（都是這個專案踩過或差點踩到的）

1. **選擇器抓到清單以外的區塊**：FastBull 的 `span.title_name` 在整份文件出現 115 次，只有 70 個在 `div.news-list` 內；`div.news-list[data-id]` 整份文件 70 個，側欄只有 20 個（其餘在主內容）。解析一律限定在清單容器內（`#side_fast_news div.news-list[data-id]`），元素內再用 `el.select(...)`，不要用 `doc.select` 找文字。
2. **時間單位**：FastBull 的 `data-date` 是**毫秒**，不是秒。用秒當毫秒會得到 1970 年的時間，協定不會擋（>= 0 就合法），畫面順序會全錯。測試要斷言毫秒值的量級（>= 10^12）。
3. **時區**：來源給「2026-10-25 12:30:45」這類民用時間時，要寫死時區位移（如 UTC+8）轉成 UTC。用 `crate::timeutil::parse_datetime(s, 8*3600)`，並在程式註明依據。`timeutil` 不處理夏令時間。
4. **新到舊的順序**：`convert` 必須維持來源頁面順序且最新在前。有些 API 回傳舊到新，要在 `convert` 內反轉；引擎雖會再按時間排序，但相同毫秒的 tie-break 依賴頁面順序。
5. **解析 0 則必須是錯誤**：改版、驗證碼頁、空回應都會得到 0 則。回傳空 `Vec` 引擎也會當錯誤，但請在 `convert` 就回 `Err(ConnectError::Parse(..))` 並寫清楚原因，錯誤會顯示在 `status` 訊息。範本與 FastBull 都這樣做。
6. **`id` 不穩定**：用陣列索引、用「現在時間」、或含會變動的後綴，會讓每次輪詢都被當成新訊息而洪水（> 10 則改發 snapshot）。用來源的原生 id。若來源沒有 id，退而用「時間毫秒 + 文字雜湊」，並在回報註明風險。
7. **`url` 拼接與結尾換行**：`url` 含空白、換行、非 ASCII 或相對路徑會讓整則 item 被丟棄。拼接前 `trim()`，自行驗證（參考 `fastbull::is_valid_url`／`build_link`），不合格就降級為 `url: None` 並寫 stderr，不要丟掉整則。連結的 origin 用連接器常數，不要由 `fetch` 的目標 URL 推導（測試會把目標改成 127.0.0.1）。
8. **zsh 下 glob 無匹配會中止指令**：`rm tests/fixtures/x/*.bak` 找不到檔案時 zsh 會報 `no matches found` 並中止整個指令列。不確定時用 `ls` 先確認，或在 sh 內跑（`sh -c '...'`）。
9. **守衛掃描的是原始文字**：測試（含註解）出現登錄網域（如 `jin10.com`）就紅。只寫路徑，或用 `["jin10", ".com"].concat()`（步驟 f）。fixture 檔不在掃描範圍，但 `.rs` 測試檔內的字串在。
10. **非 UTF-8 回應**：`HttpFetcher::get_text` 依回應宣告的字元集解碼，壞位元組變成替代字元，不會報錯。若來源是 GBK／Big5，要確認回應標頭有宣告字元集，並用 fixture 測一次中文是否正確。
11. **輪詢間隔下限 10 秒**：`DEFAULT_INTERVAL` < 10 秒會讓 `sources_registry` 測試失敗。逾時（連線 5 秒／總 8 秒）必須小於間隔。`--interval-ms` 只供本機測試用。
12. **重新導向不跟隨**：`HttpFetcher` 把 3xx 當錯誤（`HttpStatus(302)`）。若目標網址會 301/302，直接把 `DEFAULT_URL` 改成最終網址，不要去改共用程式。
13. **HTML 實體與標籤**：JSON 的 `text` 常夾 `<b>`、`&nbsp;`、`\n`。`scraper` 會解碼 HTML 實體；JSON 來源要自己去標籤並收斂空白。空字串（trim 後）要跳過，因為 `text` 不得為空。

### 補充陷阱（來自冷啟動驗證）

14. **過濾類元素**：來源清單裡常混有「合法但不是新聞」的元素：廣告（例如 `extras.ad: true`）、付費鎖定而內容為空的項目、只有圖片沒有文字的項目。原則：**略過這類元素，在 stderr 寫一行原因，且 fixture 必須包含這些元素的樣本、測試要斷言它們被略過且順序不受影響**；不要把它們當成錯誤，也不要輸出空 `text`（協定不允許）。因為每輪輪詢都會重複略過，stderr 會每輪重複同樣幾行，這是正常的。
15. **固定標頭常數 vs. 憑證**：有些公開 API 要求前端固定送出的標頭（例如 `x-app-id`、`x-version`，值寫死在公開 JS 裡）。這類**公開、固定、不隨請求變化**的常數可以放進 `EXTRA_HEADERS`，並在回報中註明「這是公開的固定常數、不是憑證，以及你如何判斷」。**逐次產生的 token、簽章、cookie、登入狀態、驗證碼**才是第 5 章要停下來回報的情況。你若沒有測試「不帶該標頭是否可行」，要在回報中說明這是推測。
16. **斷言額外標頭有送出**：`FakeServer.requests` 記錄每個請求的**原始請求頭文字**（請求行加所有標頭）。要驗證 `EXTRA_HEADERS` 真的送出，可斷言 `server.requests.lock().unwrap()[0].to_lowercase().contains("x-app-id: <值>")`。
17. **時間欄位沒有時區標記**（例如 `"2026-10-25 20:18:06"`）：必須在回報中寫明你依什麼推定時區（網站的前端程式、頁面標示、與已知事件的對照），並用測試固定「這個字串 → 這個 UTC 毫秒」的對應；推定不是事實，要標註。

## 5. 何時停下來回報人類

```
robots.txt 或使用條款禁止自動抓取？ ──是──▶ 停止，回報條款原文位置
需要登入／cookie／token／簽章／驗證碼？ ──是──▶ 停止（v1 不支援），回報需要什麼
只有 WebSocket／Server-Sent Events 推送？ ──是──▶ 停止（v1 的 Connector 是 HTTP 輪詢），回報
回應被反爬蟲擋（403/429、Cloudflare 挑戰頁）？ ──是──▶ 停止；不要偽裝瀏覽器、不要換 IP、不要加快頻率
找不到穩定 id 或時間欄位？ ──是──▶ 回報你的替代方案與風險，等人決定
需要改 protocol/、Sources/（Swift）、引擎共用檔才能做？ ──是──▶ 停止：規格矛盾，回報
既有測試因你的改動而紅，且你無法在來源專屬檔案內解決？ ──是──▶ 停止並貼出輸出
```
回報格式：做了什麼、跑過的指令與輸出摘要（紅／綠）、robots／條款結論、無法完成的部分與原因。**不要為了讓流程「看起來成功」而放寬斷言、偽造 fixture 或略過步驟。**

## 6. 驗收檢查表

- [ ] 步驟 a 的 robots／條款結論已寫進回報。
- [ ] fixture 是原始回應的最小子集合，無個資／token，位於 `ticker-connect/tests/fixtures/<id>/`。
- [ ] 解析測試先紅後綠，回報附兩次輸出。
- [ ] `src/<id>.rs` 與 `SOURCE_ID` 符合 id 規則；`REGISTRY`、`dispatch`、`lib.rs` 三處都已加。
- [ ] `cargo run --quiet -- --list-sources` 含新 id；`--source nope` 退出碼 2。
- [ ] `grep -rn "TODO(source)" ticker-connect/src ticker-connect/tests` 無輸出；範本玩具欄位名稱（`time_ms` 等）已換成真實的。
- [ ] 測試只連 127.0.0.1；`cargo test --test no_external_network` 綠；測試原始碼無來源網域。
- [ ] `cargo test` 全綠且 `cargo build` 0 warning；`python3 -m unittest discover -s protocol/tests` 綠。
- [ ] 只打了**一次**真實網站（步驟 h），輸出每行 `check_line` 為 `(True, None)`，已附 stdout／stderr 摘要。
- [ ] `git status` 只有允許的檔案；沒有 commit／push；沒動 `protocol/`、`Sources/`、`openspec/specs/`。
- [ ] 回報列出所有假設與未驗證項目（例如：App 實機顯示未驗證）。

## 7. 參考實作導覽：`ticker-connect/src/fastbull.rs`

| 區段 | 內容與要學的點 |
|---|---|
| 常數（檔頭） | `DEFAULT_URL` 是正式網址的**唯一**出處；`LINK_ORIGIN` 與 fetch 目標分開（測試時目標是 127.0.0.1，連結仍要是正式 origin）；`SOURCE_ID`、`DEFAULT_INTERVAL`（10 秒）、逾時（5／8 秒）、`USER_AGENT` |
| `FastBullConnector` + `with_timeouts` | `reqwest::Client`：固定 UA、逾時、`redirect(Policy::none())`。新來源改用 `HttpFetcher` 即可得到相同行為 |
| `LIST_SCOPE` | 解析範圍限定在 `#side_fast_news`（陷阱 1）。註解記錄了實測數字 |
| `is_valid_url` / `build_link` | 與 `item.schema.json` 的 `url` 規則一一對應；壞連結回 `Err(原因)`，由呼叫端降級 |
| `parse_html` | 純函式，回傳 `(items, skipped)`。逐元素：`data-id` → `id`、`data-date`（毫秒）→ `published_at_ms`、元素內的 `span.title_name` → `text`；任一必要欄位壞 → 記原因並跳過；`url` 壞 → 降級為 `None`。**頁面順序不動** |
| `impl Connector` | `fetch`：GET，非 200 → `HttpStatus`，其餘傳輸錯誤 → `Fetch`；`convert`：呼叫 `parse_html`、把 skipped 寫 stderr、**0 則 → `Err(Parse)`** |
| 測試 | `tests/fastbull_parse.rs`（fixture 解析、精確值、清單外干擾、壞元素、0 則、純函式、protocol 驗證）、`tests/fastbull_fetch.rs`（假伺服器：200／非 200／逾時／拒絕連線）、`tests/e2e_local.rs`（真 binary 端到端） |

你的 `src/<id>.rs` 與它的對應關係：`parse_payload` ≈ `parse_html`，`HttpFetcher` ≈ `FastBullConnector` 的 client，其餘結構相同。

## 8. 範本內容速查

`docs/templates/`：`source.rs.tmpl`（連接器骨架 + 玩具 JSON 解析 + `TODO(source)`）、`source_parse_test.rs.tmpl`（解析測試）、`source_fetch_test.rs.tmpl`（假伺服器抓取 + 以 `--source <id>` 啟動真 binary 的端到端）、`sample.json.tmpl`（玩具 fixture）。範本已用臨時來源實際實例化、編譯並跑過測試（全套 `cargo test` 綠，`--list-sources` 出現臨時來源），驗證後臨時來源已刪除、未留在 repo。
