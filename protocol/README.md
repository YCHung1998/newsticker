# protocol/ —— FastBullTicker 訊息契約 v1

helper（Rust，Connect engine）到 App（Swift，Show engine）的單向 stdout JSON-lines 協定。
規格來源：`openspec/changes/message-contract/`（`specs/message-protocol`、`specs/contract-fixtures`、`design.md`）。

## 目錄

| 路徑 | 內容 |
|---|---|
| `schema/item.schema.json` | 單則訊息：`source`、`id`、`published_at_ms`、`text`，不允許額外欄位 |
| `schema/snapshot.schema.json` | `{v:1, type:"snapshot", items:[…]}`，items 新到舊、非空 |
| `schema/items.schema.json` | `{v:1, type:"items", items:[…]}`，items 舊到新、非空 |
| `schema/status.schema.json` | `{v:1, type:"status", source, state:ok\|error, message}` |
| `fixtures/valid/`, `fixtures/invalid/` | 每檔恰一行（結尾一個 `\n`）的樣本 |
| `fixtures/manifest.json` | 每個樣本的預期（`accept`／`reject`＋原因類別），**兩端預期的唯一來源** |
| `refcheck.py` | 參考驗證器（schema＋額外檢查＋超大行產生器） |
| `tests/test_contract.py` | 參考驗證測試 |

JSON Schema 草案：2020-12（已決定 2026-10-24）。Schema 以 `$id`（`https://fastbull-ticker.local/protocol/v1/*.schema.json`）互相 `$ref`，無需網路。

## 工具與如何執行

參考驗證器 = 本機已有的 Python 3.9 + `jsonschema` 4.25.1（支援 2020-12；`referencing` 為其相依，已隨附）。**不需安裝任何套件、不需 sudo、不需任何系統權限。**
（Node v26 雖存在但沒有 ajv，需 `npm install`，故不採用。）

檢查環境：`python3 -c "import jsonschema; print(jsonschema.__version__)"` 應為 4.x 且 >= 4.18。若換機器沒有，退路是 `python3 -m pip install --user "jsonschema==4.25.1"`（版本鎖定；`--user` 不需 sudo）。

```sh
cd /Users/eason.hung/Documents/github/newsticker
python3 -m unittest discover -s protocol/tests -v
```

## 判定規則（參考驗證器 `refcheck.check_line`）

單行輸入（不含結尾 `\n`）依序判定，第一個不通過者決定原因類別：

| 順序 | 檢查 | 失敗原因類別 |
|---|---|---|
| 1 | 位元組長度 > 1,048,576（以位元組計，恰為上限仍合法） | `oversize` |
| 2 | 非 UTF-8、非 JSON（含空行、`NaN`／`Infinity`） | `not_json` |
| 3 | `v` 是整數但不等於 1（例如 2） | `version` |
| 4 | 缺 `type`／未知 `type`／schema 不符（缺欄位、型別錯、空字串、空 `items`、額外欄位、`state` 非法、`v` 非整數 1…） | `schema` |
| 5 | 順序違規：snapshot 的 `published_at_ms` 非遞增、items 非遞減（相鄰相等視為合法） | `order` |

### 暫不處理的情況
- `v` 缺失或型別不是整數 -> 歸類 `schema`（不是 `version`）。
- 同一則訊息內 `id` 重複不檢查（契約未規定）。

## 兩端接入方式（供 `connect-engine-fastbull`、`show-engine-core` 引用）

兩端 MUST 直接讀取 `protocol/fixtures/manifest.json` 與其指向的檔案，不得複製副本，也不得在程式內另寫預期。

manifest 欄位：`max_line_bytes`、`reasons`、`samples[]`。每個樣本：`name`、`expect`（`accept`／`reject`）、`reason`（reject 時必有）、`covers`（涵蓋標籤），以及 `file`（相對 `fixtures/`）或 `generate`（程式產生，目前 `kind: padded_items`，`total_bytes` 為 `limit` 或 `limit+1`，產生合法 `items` 訊息並以 ASCII `text` 補到恰好該位元組數）。載入 `file` 時：內容須恰為一行，去掉結尾一個 `\n` 後即為待判定的位元組。

### Rust（發送端，`connect-engine-fastbull`）

對照 `message-protocol` 的「非法訊息的處理期望」：
1. 每則要輸出的訊息，序列化後以 2020-12 驗證器（例如 `jsonschema` crate，需確認支援 2020-12）驗證；另做額外檢查：位元組長度 <= 1,048,576、順序。
2. **先過濾**：逐個 item 驗證，不合格的 item 丟掉，不得混進 `items`／`snapshot`，並另發 `status`：`state: "error"`，`message` 描述被丟棄原因。過濾後若無任何合法 item，不得發空 `items`／`snapshot`，只發警告 `status`。
3. 契約測試：對 manifest 每個 `accept` 樣本，解析成型別後再序列化應仍通過；每個 `reject` 樣本，驗證器應回報與 `reason` 相符的類別（`order`／`oversize` 由額外檢查負責）。
4. 心跳：至少每 30 秒一則 `status`，退避期間亦然（此義務在 `connect-engine-fastbull` 驗收，本 change 只定義）。

### Swift（接收端，`show-engine-core`）

1. `LineBuffer` 以 0x0A 切行；單行 > 1,048,576 位元組 -> 丟棄、回報 `oversize`，繼續讀後續行。
2. 每行：先檢查 UTF-8，再 JSON 解析（失敗 -> `not_json`）；`v` 為整數且 != 1 -> `version`；用 Codable 解碼加手寫檢查實現 schema 規則（必填欄位、型別、`minLength`、`minimum`、`items` 非空、`state` 僅 `ok`／`error`、**拒絕未知欄位**——`Codable` 預設會忽略，須用 `allKeys` 檢查）-> `schema`；最後順序檢查 -> `order`。
3. **整則拒絕**：`items`／`snapshot` 只要有一個 item 非法，整則丟棄，不得取其中合法部分。
4. 任何單行失敗只影響該行：記錄錯誤、繼續下一行，不終止串流。
5. 契約測試：以 manifest 驅動，對每個樣本比對 accept／reject 與原因類別。

## fail-then-pass 證據（2026-10-24 實跑）

做法：在 `refcheck.py`／schema／manifest 上**故意讓規則失效**（或讓非法樣本通過），執行測試確認變紅，再還原確認變綠。每次皆執行：

```sh
python3 -m unittest discover -s protocol/tests
```

基準（未動任何東西）：`Ran 11 tests ... OK`。

| # | 規則 | 故意破壞的做法 | 紅（失敗輸出摘要） | 還原後 |
|---|---|---|---|---|
| R1 | 缺欄位 | `item.schema.json` 的 `required` 拿掉 `"id"` | `FAIL: test_all_samples_match_manifest (sample='item-missing-id')`、`'items-mixed-invalid-item'`、`'snapshot-mixed-invalid-item'`；`FAILED (failures=3)` | `Ran 11 tests … OK` |
| R2 | 空 items | 刪掉 `snapshot`／`items` schema 的 `"minItems": 1` | `FAIL … (sample='snapshot-empty-items')`、`'items-empty-items'`；`FAILED (failures=2)` | `OK` |
| R3 | `state` 非法 | `status.schema.json` 的 `state` 由 `enum` 改為 `{"type":"string"}` | `FAIL … (sample='status-bad-state')`；`FAILED (failures=1)` | `OK` |
| R4 | 順序違規 | `refcheck.py` 的順序檢查改成 `if False and …` | `FAIL … 'snapshot-ascending-order'`、`'items-descending-order'`；`FAILED (failures=2)` | `OK` |
| R5 | 額外欄位 | `item.schema.json` 的 `additionalProperties` 改 `true` | `FAIL … (sample='item-extra-field')`；`FAILED (failures=1)` | `OK` |
| R6 | 1MB 上限 | `len(raw) > max_bytes` 改成 `> max_bytes + 1` | `FAIL … (sample='generated-over-limit')`；`FAILED (failures=1)` | `OK` |
| R7 | manifest 與目錄一一對應 | 從 manifest 刪掉 `status-ok` 條目 | `FAIL: test_fixtures_dir_matches_manifest`（另 `test_coverage_complete`、`test_coverage_check_detects_missing_category`）；`FAILED (failures=3)` | `OK` |
| R8 | 涵蓋清單 | 刪掉 `status-bad-state` 檔與條目（目錄與 manifest 仍一致） | `FAIL: test_coverage_complete`（缺涵蓋類別：bad_state）；`FAILED (failures=1)` | `OK` |

還原後以 `diff` 確認 schema、`refcheck.py`、`manifest.json` 與備份完全相同。
另有自動化的「檢查器本身會失敗」測試：`test_integrity_check_detects_deleted_entry`、`test_integrity_check_detects_phantom_entry`、`test_coverage_check_detects_missing_category`。

## 待確認清單與暫定值

已於 2026-10-24 由使用者決定的項目不再列入。仍待確認：

| 待確認項目 | 目前採用的暫定值 | 影響的 fixture／位置 | 翻轉方式 |
|---|---|---|---|
| `text` 長度上限 | **無上限**（刻意不發明；驗收不依賴） | 無 fixture 依賴；僅 1MB 單行上限間接限制 | 在 `item.schema.json` 加 `maxLength`，加對應非法樣本 |
| 心跳 30 秒的容忍度（是否允許抖動） | 不訂容忍值；判定依據為「相鄰 status 間隔 <= 30 秒」 | 本 change 無 fixture（驗收在 `connect-engine-fastbull`） | 在該 change 定義容忍值 |
| 順序檢查是否允許相鄰同毫秒 | **允許**（非嚴格單調） | `valid/items-equal-timestamps`；`refcheck._order_ok` | 改 `>=`／`<=` 為 `>`／`<`，並改該樣本為 reject／`order` |
| 設計文件【假設】：洪水保護門檻 10、A1–A8 等 | 不屬契約，由後續 change 處理 | — | — |

## 驗證結果（收尾）

見下方「最終驗證」小節（執行於 apply 結束時）。

## 最終驗證

```sh
python3 -m unittest discover -s protocol/tests -v
openspec validate message-contract --strict
openspec validate --all --strict
```

輸出摘要：見 apply 回報（以實際執行結果為準，可自行重跑上列三條指令）。
