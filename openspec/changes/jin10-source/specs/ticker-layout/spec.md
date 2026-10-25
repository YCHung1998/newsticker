## ADDED Requirements

### Requirement: 標題粗體與重要訊息配色
當 `item` 含 `title` 時，顯示字串 SHALL 為 `HH:mm:ss`、空白、`title`、空白、`text`；`title` 區段 SHALL 為粗體字重（與時間相同字重）。`important` 為 `true` 時，`title` 區段 SHALL 以強調色（紅色，色值為【假設】，對照使用者截圖，需人工目視）繪製；`text` 維持原配色。沒有 `title` 的 item（包含所有 fastbull item）的顯示字串與繪製 MUST 與本 change 之前完全相同。量測與繪製 MUST 使用相同字型與字重，被「…」截斷時 SHALL 不使粗體區段與本文錯位。

#### Scenario: 有標題
- **WHEN** item 含 `title` 為 `標題`
- **THEN** 顯示字串為 `HH:mm:ss 標題 本文`，時間與 `標題` 區段為粗體，其餘為一般字重（以屬性區段斷言）

#### Scenario: 重要訊息標題變紅
- **WHEN** item 的 `important` 為 `true`
- **THEN** `title` 區段前景色為強調色，時間與本文不變

#### Scenario: 無標題不變
- **WHEN** item 沒有 `title`
- **THEN** 顯示字串與屬性與本 change 之前逐字相同

#### Scenario: 截斷
- **WHEN** 可視寬度不足而需截斷
- **THEN** 截斷後字串仍以「…」結尾，且粗體區段範圍不超過字串長度
