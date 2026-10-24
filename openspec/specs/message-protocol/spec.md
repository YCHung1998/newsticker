# message-protocol Specification

## Purpose
TBD - created by archiving change message-contract. Update Purpose after archive.
## Requirements
### Requirement: 傳輸格式為單向 JSON-lines
helper 與 App 之間的協定 SHALL 為單向（helper 到 App）、以 UTF-8 編碼、每行恰好一個 JSON 物件、以 0x0A 結尾的文字串流。每個物件 MUST 含整數欄位 `v`（協定版本）與字串欄位 `type`。`type` 的合法值 MUST 僅為 `snapshot`、`items`、`status`。本協定第一版的 `v` 為 JSON 整數 `1`（字串 `"1"`、浮點數、布林皆非法）【已決定 2026-10-24：使用者確認 `v` 為整數 1】。

#### Scenario: 合法的單行訊息
- **WHEN** 一行文字是 UTF-8 的 JSON 物件，含 `v: 1` 與合法的 `type`，且其餘欄位符合該 type 的 schema
- **THEN** 該行 SHALL 通過驗證

#### Scenario: 缺少 v 或 type
- **WHEN** 一行 JSON 物件缺少 `v` 或缺少 `type`
- **THEN** 該行 SHALL 驗證失敗

#### Scenario: 未知的 type
- **WHEN** 一行 JSON 物件的 `type` 不是 `snapshot`、`items`、`status` 之一
- **THEN** 該行 SHALL 驗證失敗

#### Scenario: 不支援的協定版本
- **WHEN** 一行 JSON 物件的 `v` 不是接收端支援的版本（例如 `2`）
- **THEN** 該行 SHALL 驗證失敗，且接收端 MUST 將其視為單行錯誤而不終止串流

### Requirement: item 結構
`item` SHALL 含四個必填欄位與一個選填欄位。必填欄位：`source`（非空字串，來源識別）、`id`（非空字串，於同一 `source` 內唯一）、`published_at_ms`（整數，UTC epoch 毫秒）、`text`（字串，訊息本文，MUST NOT 為空字串【已決定 2026-10-24】；長度上限未定【待確認：不得自行發明上限，驗收不依賴它】）。選填欄位 `url`（【新增，change `ticker-navigation-link`】完整頁面連結）：缺少該欄位即「無連結」，MUST 合法；存在時 MUST 為字串，且 MUST 同時滿足：(i) 非空；(ii) 長度不超過 2048 位元組【假設：2048 為暫定上限，使用者未確認】；(iii) 以小寫 `http://` 或 `https://` 開頭，其後緊接的字元 MUST 為英數字或 `[`（即主機部分不得為空，不接受相對路徑、`javascript:`、`ftp:`、`file:` 等）【假設：scheme 僅接受小寫】；(iv) 全部字元 MUST 落在可見 ASCII 範圍 `0x21`–`0x7E`（因此不得含空白、控制字元、換行、非 ASCII；非 ASCII 位址 MUST 由發送端先做 percent-encoding），使「字元數」與「位元組數」相等，JSON Schema 的 `maxLength` 即可精確表達位元組上限。`url` 為 `null`、數字或其他非字串型別 MUST 非法（缺少才表示無連結）【假設】。協定版本 `v` 維持 `1`：理由為 helper 與 App 同倉庫同時建置並隨同一個 `.app` 發行、尚無外部消費者，且 `url` 為選填；代價是「舊版嚴格接收端」會因 `additionalProperties: false` 拒絕含 `url` 的 item，故兩端 MUST 同步更新【假設，需使用者確認；若日後出現外部消費者，改為 `v: 2`】。`item` MUST NOT 含「重要」旗標欄位；v1 契約不納入該旗標。`item` MUST NOT 含未定義的額外欄位（schema 以 `additionalProperties: false` 表達，`url` 已明列於 `properties`，此限制維持不變）【已決定 2026-10-24】。`status` 與 `snapshot`／`items` 頂層同樣不允許額外欄位。

#### Scenario: 合法 item
- **WHEN** item 含 `source`、`id`、`published_at_ms`、`text` 且型別皆正確
- **THEN** 該 item SHALL 通過驗證

#### Scenario: 缺少必填欄位
- **WHEN** item 缺少 `source`、`id`、`published_at_ms`、`text` 其中任一個
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: published_at_ms 型別錯誤
- **WHEN** `published_at_ms` 是字串、浮點數或負數
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: text 為空字串
- **WHEN** `text` 是空字串 `""`
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: item 含額外欄位
- **WHEN** item 含未定義欄位（例如 `important`）
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: id 為數字而非字串
- **WHEN** `id` 的 JSON 型別是數字
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: 合法 item 含 url
- **WHEN** item 含四個必填欄位與 `url` 為 `https://www.example.com/news/1`
- **THEN** 該 item SHALL 通過驗證

#### Scenario: 缺少 url 即無連結
- **WHEN** item 含四個必填欄位且不含 `url`
- **THEN** 該 item SHALL 通過驗證（既有不含 `url` 的樣本 MUST 仍然合法）

#### Scenario: url 不是 http 或 https
- **WHEN** `url` 為 `javascript:alert(1)`、`ftp://example.com/a` 或 `file:///etc/hosts`
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: url 為空字串、null 或非字串
- **WHEN** `url` 為 `""`、`null` 或數字
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: url 長度邊界
- **WHEN** `url` 恰為 2048 位元組（合法格式）
- **THEN** 該 item SHALL 通過驗證
- **WHEN** `url` 為 2049 位元組
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: url 含空白、換行或非 ASCII
- **WHEN** `url` 含空白、結尾換行 `\n` 或非 ASCII 字元
- **THEN** 含該 item 的訊息 SHALL 驗證失敗（尤其結尾換行 MUST 被拒絕，不得因各語言正規表示式對 `$` 的差異而在某一端通過）

#### Scenario: url 為相對路徑
- **WHEN** `url` 為 `/tw/fastshort/4334051_1_2`
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

### Requirement: snapshot 訊息
`snapshot` 訊息 SHALL 含 `items` 陣列，用於第一次成功輪詢（或洪水保護重設基準）時傳送歷史訊息。其 `items` 的順序語意 MUST 為新到舊。`items` 陣列 MUST 至少含一個元素，空 `items[]` 非法【已決定 2026-10-24】。順序為語意約定，JSON Schema 無法表達；契約測試 MUST 以 fixtures 另行檢查順序（見 `contract-fixtures`）。順序違規（`published_at_ms` 由小到大排列的 snapshot）MUST 被拒絕【已決定 2026-10-24】。相鄰兩則 `published_at_ms` 相等視為合法（非嚴格單調）【待確認：使用者未決定同毫秒的處置，本實作採不嚴格，以 fixture `items-equal-timestamps` 標示】。

#### Scenario: 合法 snapshot
- **WHEN** `type` 為 `snapshot` 且 `items` 含多個合法 item，`published_at_ms` 由大到小排列
- **THEN** 該訊息 SHALL 通過驗證

#### Scenario: snapshot 的 items 為空
- **WHEN** `type` 為 `snapshot` 且 `items` 是空陣列
- **THEN** 該訊息 SHALL 驗證失敗

#### Scenario: snapshot 順序違規
- **WHEN** `type` 為 `snapshot` 且 `published_at_ms` 由小到大排列
- **THEN** 該訊息 SHALL 被拒絕（原因類別 `order`）

#### Scenario: snapshot 缺少 items
- **WHEN** `type` 為 `snapshot` 但沒有 `items` 欄位
- **THEN** 該訊息 SHALL 驗證失敗

### Requirement: items 訊息
`items` 訊息 SHALL 含 `items` 陣列，用於傳送之後輪詢所得的新訊息。其順序語意 MUST 為舊到新。`items` 陣列 MUST 至少含一個元素，空 `items[]` 非法【已決定 2026-10-24】。順序違規（`published_at_ms` 由大到小排列）MUST 被拒絕【已決定 2026-10-24】。

#### Scenario: 合法 items
- **WHEN** `type` 為 `items` 且 `items` 含合法 item，`published_at_ms` 由小到大排列
- **THEN** 該訊息 SHALL 通過驗證

#### Scenario: items 順序違規
- **WHEN** `type` 為 `items` 且 `published_at_ms` 由大到小排列
- **THEN** 該訊息 SHALL 被拒絕（原因類別 `order`）

#### Scenario: items 為空
- **WHEN** `type` 為 `items` 且 `items` 是空陣列
- **THEN** 該訊息 SHALL 驗證失敗

#### Scenario: items 含非法 item
- **WHEN** `type` 為 `items` 且陣列中有任一 item 不符合 item 結構
- **THEN** 整則訊息 SHALL 驗證失敗

### Requirement: status 訊息與心跳義務
`status` 訊息 SHALL 含 `source`（非空字串）、`state`（僅能是 `ok` 或 `error`）、`message`（字串）。helper SHALL 至少每 30 秒送出一則 `status`，兼作心跳；此義務不因輪詢成功與否而中止，退避重試期間仍須發送【已決定 2026-10-24】。`message` 在 `state` 為 `ok` 時可為空字串【已決定 2026-10-24】。心跳的實際發送由 `connect-engine-fastbull` 實作並驗收，本 change 只定義義務與可供測試的判定依據。

#### Scenario: 合法 status
- **WHEN** `type` 為 `status`，`state` 為 `ok` 或 `error`，且 `source` 與 `message` 為字串
- **THEN** 該訊息 SHALL 通過驗證

#### Scenario: state 為未定義值
- **WHEN** `state` 為 `warn` 或其他不在 `ok`／`error` 的值
- **THEN** 該訊息 SHALL 驗證失敗

#### Scenario: 心跳間隔判定
- **WHEN** 契約測試取得 helper 一段輸出的 `status` 訊息時間序列
- **THEN** 任兩則相鄰 `status` 的間隔 MUST NOT 超過 30 秒，否則判定違反心跳義務【待確認：是否容許抖動容忍度，使用者未決定，本 change 不訂容忍值】

### Requirement: 單行大小上限
每一行（不含結尾換行）MUST NOT 超過 1MB。發送端 SHALL 不產生超過上限的行；接收端遇到超過上限的行 SHALL 丟棄該行並回報錯誤，且 MUST 繼續處理後續行。「1MB」定義為 1,048,576 位元組（1 MiB），以位元組而非字元計算【已決定 2026-10-24】。

#### Scenario: 剛好等於上限的行
- **WHEN** 一行的位元組長度恰為上限
- **THEN** 該行 SHALL 被視為未超限而照常解析

#### Scenario: 超過上限的行
- **WHEN** 一行的位元組長度為上限加一
- **THEN** 接收端 SHALL 丟棄該行並回報錯誤，且後續的合法行 SHALL 仍被正常處理

### Requirement: 非法訊息的處理期望
本協定有兩個互補義務【已決定 2026-10-24，裁決原規格的矛盾】：(1) 接收端：`items`／`snapshot` 訊息整則所有 item 都合法才接受，只要有一個非法則整則非法、整則拒絕；(2) 發送端（Rust helper）自行負責先過濾：不合格的 item MUST 丟掉，不得混進 `items`／`snapshot`，並另發一則 `status` 警告（`state` 為 `error`，`message` 描述被丟棄的原因）。若過濾後已無任何合法 item，發送端 MUST NOT 發送空的 `items`／`snapshot`（空陣列非法），只發警告 `status`。發送端 SHALL 在輸出前以 schema 驗證每則訊息，不合格者 MUST NOT 輸出。接收端 SHALL 把任何單行的失敗（非 UTF-8、非 JSON、schema 不符、版本不支援、超過上限、順序違規）視為只影響該行：丟棄該行、記錄錯誤、繼續處理下一行，且 MUST NOT 終止串流或結束行程。部分合法的訊息（例如 `items` 中混有非法 item）SHALL 整則丟棄，不得只取其中合法的部分。

#### Scenario: 中間一行是亂碼
- **WHEN** 串流依序為合法行 A、非 JSON 的行 X、合法行 B
- **THEN** 接收端 SHALL 處理 A 與 B，丟棄 X 並記錄錯誤

#### Scenario: items 中混有非法 item
- **WHEN** 一則 `items` 訊息含兩個合法 item 與一個缺少 `id` 的 item
- **THEN** 接收端 SHALL 整則丟棄，不處理其中兩個合法 item

#### Scenario: 發送端遇到不合格的 item
- **WHEN** 發送端組出的訊息含不合格的 item
- **THEN** 發送端 SHALL 丟棄該 item，將其餘合法 item 照常發出（若有），並另輸出一則 `state` 為 `error`、`message` 說明丟棄原因的 `status`；不合格 item MUST NOT 出現在任何 `items`／`snapshot` 中

#### Scenario: 過濾後無合法 item
- **WHEN** 發送端過濾後沒有任何合法 item
- **THEN** 發送端 SHALL 不發送空的 `items`／`snapshot`，只發警告 `status`

