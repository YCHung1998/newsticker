## MODIFIED Requirements

### Requirement: item 結構
`item` SHALL 含四個必填欄位與三個選填欄位（`url`、`title`、`important`）。必填欄位：`source`（非空字串，來源識別）、`id`（非空字串，於同一 `source` 內唯一）、`published_at_ms`（整數，UTC epoch 毫秒）、`text`（字串，訊息本文，MUST NOT 為空字串【已決定 2026-10-24】；長度上限未定【待確認：不得自行發明上限，驗收不依賴它】）。選填欄位 `url`（【新增，change `ticker-navigation-link`】完整頁面連結）：缺少該欄位即「無連結」，MUST 合法；存在時 MUST 為字串，且 MUST 同時滿足：(i) 非空；(ii) 長度不超過 2048 位元組【假設：2048 為暫定上限，使用者未確認】；(iii) 以小寫 `http://` 或 `https://` 開頭，其後緊接的字元 MUST 為英數字或 `[`（即主機部分不得為空，不接受相對路徑、`javascript:`、`ftp:`、`file:` 等）【假設：scheme 僅接受小寫】；(iv) 全部字元 MUST 落在可見 ASCII 範圍 `0x21`–`0x7E`（因此不得含空白、控制字元、換行、非 ASCII；非 ASCII 位址 MUST 由發送端先做 percent-encoding），使「字元數」與「位元組數」相等，JSON Schema 的 `maxLength` 即可精確表達位元組上限。`url` 為 `null`、數字或其他非字串型別 MUST 非法（缺少才表示無連結）【假設】。協定版本 `v` 維持 `1`：理由為 helper 與 App 同倉庫同時建置並隨同一個 `.app` 發行、尚無外部消費者，且 `url` 為選填；代價是「舊版嚴格接收端」會因 `additionalProperties: false` 拒絕含 `url` 的 item，故兩端 MUST 同步更新【假設，需使用者確認；若日後出現外部消費者，改為 `v: 2`】。選填欄位 `title`（【新增，change `jin10-source`】訊息標題，顯示時粗體）：缺少即「無標題」，MUST 合法；存在時 MUST 為非空字串（不得為空字串或 `null`），不含 HTML；`title` 是 `text` 之外的獨立文字，發送端 MUST NOT 把同一段標題文字重複放進 `text`。選填欄位 `important`（【新增，change `jin10-source`】來源標示為重要訊息，推翻 2026-10-24 「v1 不含重要旗標」的決定，需使用者確認）：缺少即「非重要」，MUST 合法；存在時 MUST 為布林值（`true` 或 `false`；`null`、數字、字串皆非法）。`title` 與 `important` 同為選填、`v` 維持 `1`，同 `url` 的理由與代價：舊版嚴格接收端會拒絕含這兩個欄位的 item，兩端 MUST 同步更新。`item` MUST NOT 含未定義的額外欄位（schema 以 `additionalProperties: false` 表達，`url` 已明列於 `properties`，此限制維持不變）【已決定 2026-10-24】。`status` 與 `snapshot`／`items` 頂層同樣不允許額外欄位。

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
- **WHEN** item 含未定義欄位（例如 `priority`）
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

#### Scenario: 含 title 的 item
- **WHEN** item 含非空字串 `title`
- **THEN** 該 item SHALL 通過驗證

#### Scenario: title 為空字串或 null
- **WHEN** `title` 是 `""` 或 `null`
- **THEN** 含該 item 的訊息 SHALL 驗證失敗

#### Scenario: important 為布林
- **WHEN** item 含 `"important": true` 或 `"important": false`
- **THEN** 該 item SHALL 通過驗證

#### Scenario: important 型別錯誤
- **WHEN** `important` 是 `null`、`1` 或 `"true"`
- **THEN** 含該 item 的訊息 SHALL 驗證失敗
