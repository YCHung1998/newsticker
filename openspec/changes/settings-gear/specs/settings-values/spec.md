## ADDED Requirements

依賴：進行中的 change `ticker-style-settings`（`TickerStyle`、`StyleParser`、`StyleStore`、`StyleMenuModel`、`StyleApplier` 尚未同步到主 specs）；本 capability 在其之上增加兩個欄位，不改其他欄位的語意。

### Requirement: TickerStyle 新增兩個設定欄位
`TickerStyle` SHALL 新增兩個欄位，JSON 鍵為英文 camelCase，並納入 `TickerStyle.keys`（接在既有鍵之後）：

| 鍵 | 型別 | 預設 | 合法值 |
|---|---|---|---|
| `seekHoldSeconds` | 數字（秒） | `1`（現行值） | `0.5`–`10`【假設】 |
| `pollIntervalSeconds` | 整數（秒） | `10`（現行值） | 僅 `10`、`30`、`60`【假設；5 秒未實測，不提供】 |

兩者 MUST 不改變既有 15 個欄位的鍵、預設值與語意；缺鍵時 MUST 取預設，使不改設定時行為與加入本欄位之前完全相同。檔位與範圍 MUST 集中在 `StyleRanges`（`seekHoldSeconds`、`pollIntervalSteps`），供解析、夾制與設定面板共用。`TickerStyle.isValid` MUST 同時檢查這兩個欄位；`clamped()` MUST 夾制它們。`seekHoldSeconds` 的語意見 `ticker-navigation`「切換後暫停自動捲動並恢復」，`pollIntervalSeconds` 的語意見 `poll-interval`。

#### Scenario: 預設值
- **WHEN** 檢視 `TickerStyle.default`
- **THEN** `seekHoldSeconds` SHALL 為 1、`pollIntervalSeconds` SHALL 為 10，且與 Core `SchedulerConfig().seekHoldSeconds`（1）一致

#### Scenario: 欄位齊全與往返
- **WHEN** 編碼再解碼一個 `TickerStyle`
- **THEN** 輸出 SHALL 含 `seekHoldSeconds` 與 `pollIntervalSeconds` 兩鍵，往返後 SHALL 相等

#### Scenario: 舊檔向前相容
- **WHEN** 解析不含這兩個鍵的 `style.json`
- **THEN** 結果 SHALL 取預設值且 SHALL 不產生這兩個鍵的警告

### Requirement: seekHoldSeconds 的解析與夾制
`StyleParser` MUST 將 `seekHoldSeconds` 夾進 0.5–10：超出範圍者夾制並產生 `clamped` 警告（例如 0 → 0.5、-3 → 0.5、99 → 10）；型別不是數字者取預設值 1 並產生 `invalidType` 警告。小數合法（例如 2.5）。`clamped()` MUST 與解析使用相同範圍。0 在 Core 雖合法（表示不保持），但本設定不提供「關閉停留」【假設，見 design.md 決定 5】，故檔案中的 0 被夾制為 0.5。

#### Scenario: 範圍內的值
- **WHEN** `seekHoldSeconds` 為 2.5
- **THEN** 解析結果 SHALL 為 2.5 且 SHALL 無警告

#### Scenario: 越界夾制
- **WHEN** `seekHoldSeconds` 為 0、-3、99
- **THEN** 解析結果 SHALL 依序為 0.5、0.5、10，且各 SHALL 有一則 `clamped` 警告

#### Scenario: 型別錯誤
- **WHEN** `seekHoldSeconds` 為字串 `"2"` 或布林
- **THEN** 解析結果 SHALL 為 1，且 SHALL 有一則 `invalidType` 警告

### Requirement: pollIntervalSeconds 的解析與夾制
`StyleParser` MUST 只接受整數檔位 10、30、60：值為數字但不是檔位者，MUST 夾制到**最近的檔位**（平手取較大者，即較少請求）並產生 `clamped` 警告，例如 5 → 10、20 → 30、45 → 60、1000 → 60、-1 → 10；非整數的數字（例如 30.5）或非數字者取預設 10 並產生 `invalidType` 警告。`clamped()` MUST 以相同規則夾制。

#### Scenario: 合法檔位
- **WHEN** `pollIntervalSeconds` 為 10、30、60
- **THEN** 解析結果 SHALL 原值且無警告

#### Scenario: 非檔位夾制
- **WHEN** `pollIntervalSeconds` 為 5、20、45、1000、-1
- **THEN** 解析結果 SHALL 依序為 10、30、60、60、10，各 SHALL 有一則 `clamped` 警告

#### Scenario: 型別錯誤
- **WHEN** `pollIntervalSeconds` 為 30.5 或字串 `"30"`
- **THEN** 解析結果 SHALL 為 10，且 SHALL 有一則 `invalidType` 警告

### Requirement: 設定動作與資料模型
`StyleMenuAction` SHALL 新增 `setSeekHoldSeconds(Double)` 與 `setPollIntervalSeconds(Int)`，`StyleMenuModel.apply(_:to:)` MUST 設定對應欄位（夾制仍由 `StyleStore.update` 負責，使選單、面板、熱重載經同一條夾制路徑）。選單列「樣式」子選單的項目清單 MUST 不新增這兩項（它們只在設定面板顯示）【假設】，既有項目清單與順序 MUST 不變。

#### Scenario: 動作對樣式的影響
- **WHEN** 對預設樣式依序套用 `setSeekHoldSeconds(3)`、`setPollIntervalSeconds(30)`
- **THEN** 樣式 SHALL 為 `seekHoldSeconds == 3`、`pollIntervalSeconds == 30`，其他欄位 SHALL 不變

#### Scenario: 經 store 夾制
- **WHEN** 經 `StyleStore.update` 套用 `setSeekHoldSeconds(99)` 與 `setPollIntervalSeconds(45)`
- **THEN** 生效樣式 SHALL 為 10 與 60，且寫回的檔案 SHALL 為夾制後的值

#### Scenario: 樣式選單不變
- **WHEN** 以預設樣式產生 `StyleMenuModel.entries`
- **THEN** 項目 id SHALL 與加入本欄位之前完全相同

### Requirement: 設定的生效路徑
`StyleApplier.apply` MUST 把 `seekHoldSeconds` 放進 `SchedulerTunables`（見 `ticker-scheduler`「seekHoldSeconds 可於執行期調整」）；`pollIntervalSeconds` 變更時 MUST 呼叫 `onPollIntervalChange`（見 `poll-interval`）。啟動套用（`source: startup`）MUST NOT 呼叫 `onPollIntervalChange`（啟動時 helper 尚未建立，啟動參數由載入的樣式直接決定）。`StyleApplier.changedKeys` 與日誌摘要 MUST 涵蓋兩個新欄位。選單、面板與熱重載三條路徑 MUST 共用同一個 `StyleApplier.apply`。

#### Scenario: 停留時間生效
- **WHEN** 樣式的 `seekHoldSeconds` 由 1 改為 4 並套用，然後 `seek` 成功
- **THEN** 排程器的 `holdRemaining` SHALL 為 4

#### Scenario: 輪詢間隔變更觸發一次回呼
- **WHEN** `pollIntervalSeconds` 由 10 改為 30 並套用
- **THEN** `onPollIntervalChange` SHALL 恰被呼叫一次且參數為 30；僅改其他欄位時 SHALL 不被呼叫

#### Scenario: 啟動不回呼
- **WHEN** 以 `source: startup` 套用 `pollIntervalSeconds` 為 60 的樣式
- **THEN** `onPollIntervalChange` SHALL 不被呼叫
