# line-buffer Specification

## Purpose
TBD - created by archiving change show-engine-core. Update Purpose after archive.
## Requirements
### Requirement: 以 0x0A 切行並保留半行
`LineBuffer` SHALL 接受任意切分的位元組區塊（chunk），以位元組 0x0A 切行，輸出完整行（不含 0x0A）。尚未遇到 0x0A 的尾端資料 SHALL 保留於內部，待後續 chunk 補齊後才輸出。切行 MUST 在位元組層進行，不得先轉成字串（多位元組 UTF-8 字元可能被切在 chunk 邊界）。

#### Scenario: 一個 chunk 含多行
- **WHEN** 餵入 `a\nb\nc\n`
- **THEN** SHALL 依序輸出 `a`、`b`、`c`

#### Scenario: 半行跨 chunk
- **WHEN** 先餵入 `{"v":1,` 再餵入 `"type":"status"}\n`
- **THEN** 第一次 SHALL 不輸出任何行；第二次 SHALL 輸出一行完整內容

#### Scenario: UTF-8 字元被切在邊界
- **WHEN** 一個 3 位元組的 CJK 字元被切成兩個 chunk，後接 0x0A
- **THEN** 輸出的行 SHALL 與未切分時位元組完全相同

#### Scenario: 逐位元組餵入
- **WHEN** 將一段含多行的資料一次一個位元組餵入
- **THEN** 輸出的行序列 SHALL 與一次整段餵入相同

### Requirement: 單行上限與超長行處理
單行長度（不含 0x0A，以位元組計）超過上限時，`LineBuffer` SHALL 丟棄該行並輸出一個超長錯誤事件（含已丟棄位元組數或等價資訊），並 MUST 繼續處理後續行，不得終止串流。超長行 MUST NOT 被完整累積在記憶體中（超過上限後只計數、丟棄位元組，直到下一個 0x0A）。上限數值取自 message-contract 的單行上限 1,048,576 位元組【已決定 2026-10-24，見 `protocol/fixtures/manifest.json` 的 `max_line_bytes`；上限為單一常數 `ProtocolRules.maxLineBytes`】。超長錯誤事件於該行的 0x0A 到達時輸出一次，並帶整行位元組數【假設：事件輸出時機與內容由 apply 決定，規格原只要求「已丟棄位元組數或等價資訊」】。恰等於上限的行 SHALL 照常輸出。

#### Scenario: 恰為上限
- **WHEN** 餵入長度恰為上限的一行加 0x0A
- **THEN** SHALL 輸出該行，無錯誤事件

#### Scenario: 上限加一
- **WHEN** 餵入長度為上限加一的一行加 0x0A，其後接一個合法短行
- **THEN** SHALL 輸出一個超長錯誤事件、不輸出該超長行，且 SHALL 隨後輸出該合法短行

#### Scenario: 超長行跨多個 chunk
- **WHEN** 超長行被拆成多個 chunk 餵入，其後接合法短行
- **THEN** 結果 SHALL 與一次餵入相同，且內部緩衝大小 MUST NOT 隨超長行長度成長（以測試檢查緩衝上界）

#### Scenario: 超長行尚未結束時又收到 chunk
- **WHEN** 超長行的 0x0A 尚未到達
- **THEN** SHALL 持續丟棄，直到 0x0A 才恢復正常切行；錯誤事件 SHALL 只輸出一次

### Requirement: 壞行不影響後續行
`LineBuffer` 只負責切行，不負責解析。對於輸出的每一行，呼叫端解碼失敗 MUST NOT 影響 `LineBuffer` 的狀態或後續行。整合測試 SHALL 驗證「合法行 A、亂碼行、合法行 B」串流經 `LineBuffer` 加解碼器後，A 與 B 皆被處理、亂碼行回報錯誤。

#### Scenario: 中間一行是亂碼
- **WHEN** 串流依序為合法行 A、非 JSON 行 X、合法行 B
- **THEN** SHALL 得到 A 的訊息、X 的 `not_json` 錯誤、B 的訊息，順序不變

### Requirement: 空行與串流結尾的處置
空行（連續兩個 0x0A）與串流結束時未以 0x0A 結尾的尾端半行，其處置 SHALL 為：`LineBuffer` 照實輸出空行（長度 0）；結束時未完成的半行 MUST NOT 被當成完整行輸出。空行交解碼器判為 `not_json`（與 manifest 樣本 `not-json-empty-line` 一致）；EOF 殘留不輸出【假設：沿用提案暫定值，使用者 2026-10-24 確認維持暫定，仍標假設】

#### Scenario: 空行
- **WHEN** 餵入 `a\n\nb\n`
- **THEN** SHALL 輸出 `a`、空行、`b` 三項

#### Scenario: 結尾無換行
- **WHEN** 餵入 `a\nb` 後串流結束
- **THEN** SHALL 只輸出 `a`；`b` 視為未完成半行而不輸出

