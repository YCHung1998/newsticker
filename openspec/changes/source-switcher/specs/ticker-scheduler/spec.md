## ADDED Requirements

### Requirement: 為切換來源重設
排程器 SHALL 提供 `reset()`：清除歷史、即時佇列、已排入的訊息與閱讀位置、`hasBaseline`，並回到 REPLAY 模式；tape 座標與 `seq`／清單識別碼 MUST 繼續單調（不得歸零後與舊序號衝突）；設定（速度、寬度、時區等）與量測函式 MUST 不變。重設後在第一個 `snapshot` 之前收到的 `items` MUST 依既有規則被忽略。

#### Scenario: 重設清空狀態
- **WHEN** 排程器有歷史、即時佇列與已排入訊息，呼叫 `reset()`
- **THEN** 歷史為空、佇列為空、沒有閱讀位置、模式為 REPLAY

#### Scenario: 重設後 items 先到
- **WHEN** 重設後、尚未收到 `snapshot` 就收到 `items`
- **THEN** 該 `items` 被忽略並回報 `itemsBeforeSnapshotIgnored`

#### Scenario: 序號不歸零
- **WHEN** 重設前最後排入的 `seq` 為 N，重設後排入新訊息
- **THEN** 新訊息的 `seq` 大於 N
