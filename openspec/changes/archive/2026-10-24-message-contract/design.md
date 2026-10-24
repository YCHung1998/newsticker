## Context

來源：`docs/superpowers/specs/2026-10-24-fastbull-ticker-design.md` 第 3 節（協定）與第 9 節（change 拆分）。Connect engine（Rust）與 Show engine（Swift）是兩個獨立行程，只靠 stdout JSON-lines 溝通，所以契約必須是兩種語言都能驗證的中立格式：JSON Schema 加共用 fixtures。Swift 端沒有現成的標準 JSON Schema 驗證器，因此 Swift 端靠 Codable 加手寫檢查，並以同一批 fixtures 對齊行為。

## Goals / Non-Goals

**Goals:**
- 以版本化 JSON Schema 精確定義 `snapshot`、`items`、`status` 與 `item`。
- 把 schema 無法表達的規則（順序、1MB 上限、非 UTF-8）明文化並放進 fixtures／manifest。
- 提供兩端可共用的 fixtures 與 manifest，並以參考驗證器證明契約自洽。

**Non-Goals:**
- 不實作 Rust helper 或 Swift App；不實作心跳發送，只定義義務與判定依據。
- 不為 Swift 引入第三方 JSON Schema 套件。
- 不處理 FastBull 抓取邏輯、「重要」旗標、SQLite（設計文件已排除）。

## Decisions

1. **JSON Schema 草案採 2020-12**【已決定 2026-10-24；已向官方頁面查證 2020-12 是目前最新已發布版本】。理由：現行標準、Rust `jsonschema` crate 支援。替代：draft-07（工具最普及）。若 Rust 端選定的 crate 不支援再議。
2. **每種訊息獨立 schema，頂層以 `type` 辨別**。替代：單一 `oneOf` 大 schema。選前者是因為錯誤訊息較易讀，且 Swift Codable 可依 `type` 分派。實作時可再提供一個組合入口 schema。
3. **以 manifest 為唯一預期來源**。避免 Rust 與 Swift 各自硬編預期而漂移。manifest 的原因類別（`not_json`、`schema`、`version`、`oversize`）讓兩端用同一套分類比對。
4. **非 JSON Schema 能表達的規則由「額外檢查」承擔**：順序、大小上限、UTF-8 皆列為 fixture 並由參考測試明確檢查；兩端各自實作等價檢查。
5. **超大行 fixture 以程式產生**，不入庫，避免 1MB 檔案膨脹倉庫。
6. **參考驗證器採 Python 3 `jsonschema`（本機已安裝 4.25.1，支援 2020-12，不需安裝任何套件）**【已決定 2026-10-24：選機器上已有、不需額外安裝或系統權限者】。Node 雖有 v26 但無 ajv，需 npm install，故不採。測試以標準庫 `unittest` 執行，指令 `python3 -m unittest discover -s protocol/tests`。這是工具選擇，不影響契約。
7. **額外欄位不允許**（`additionalProperties: false`）【已決定 2026-10-24】。理由：契約由同一作者控制兩端，嚴格較易抓到漂移。代價：日後加欄位須升 `v` 或放寬。替代：允許並忽略未知欄位（前向相容較佳），使用者已選擇嚴格。
8. **矛盾裁決：接收端整則拒絕，發送端先過濾並發警告**【已決定 2026-10-24】。接收端：任一 item 非法則整則拒絕；發送端：丟掉不合格 item、另發 `status`（`state: error`，`message` 描述原因），不把壞 item 混進 `items`。兩個義務互補，不衝突。
9. **order 為獨立原因類別**：順序違規（snapshot 非新到舊、items 非舊到新）一律拒絕，原因類別 `order`。相鄰同毫秒視為合法（非嚴格）——此為實作時為避免誤殺同毫秒訊息所採的最小解讀，【待確認】。

## Risks / Trade-offs

- [嚴格拒絕額外欄位使演進困難] → 以 `v` 控制演進；各 schema 的 `additionalProperties` 集中在一處，易於翻轉。
- [Swift 與 Rust 對「1MB」「空 items」「順序違規」的實作不一致] → 全部寫成 manifest 樣本，兩端測試同時卡住。
- [JSON Schema 草案版本不被 Rust crate 支援] → apply 階段第一步就用參考驗證器與 Rust 端各驗一次，不合則降草案版本。
- [心跳義務無法在本 change 驗收] → 本 change 僅定義判定依據，驗收移到 `connect-engine-fastbull`。

## Open Questions

### 已決定（使用者於 2026-10-24 確認）

- `v` 為整數 `1`。
- 空 `items[]`（snapshot 與 items）非法。
- `item` 不允許額外欄位。
- `text` 不得為空字串。
- `status.message` 在 `ok` 時可為空字串。
- 「1MB」＝1,048,576 位元組，以位元組計。
- 順序違規（snapshot 非新到舊、items 非舊到新）→ 拒絕。
- 發送端遇不合格 item：丟掉並另發 `status`，`state` 用 `error`，`message` 描述被丟棄原因。
- 心跳在退避期間仍須發送。
- JSON Schema 草案 2020-12。
- 參考驗證器：Python `jsonschema`（本機已有）。

### 仍待確認

- `text` 的長度上限（未定，不自行發明；驗收不依賴它）。
- 心跳「至少每 30 秒」的容忍度（是否允許抖動）。
- 順序檢查是否允許相鄰同毫秒（目前採允許）。
