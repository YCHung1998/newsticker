## ADDED Requirements

### Requirement: 只有有連接器的來源才可選
App SHALL 以 helper 的 `--list-sources` 輸出為「可用來源」的唯一依據（啟動時執行一次，逾時 5 秒，失敗時只視 `fastbull` 為可用並寫日誌）。清單中 `id` 不在可用來源內的項目，選單 MUST 顯示為停用並附註「尚無連接器」，MUST NOT 能被選到，且 MUST NOT 被傳給 helper 的 `--source`。

#### Scenario: 清單中有未登錄來源
- **WHEN** `sources.json` 含 `id` 為 `bloomberg` 的項目但 helper 沒有該連接器
- **THEN** 選單中該項停用並標示「尚無連接器」，點擊無效果

#### Scenario: list-sources 失敗
- **WHEN** 執行 `--list-sources` 逾時或失敗
- **THEN** 只有 `fastbull` 可選，日誌有一行錯誤，App 不崩潰

### Requirement: 選單列的來源子選單
選單列選單 SHALL 含「來源」子選單：依清單順序列出各來源的 `name`，目前使用的打勾；之後有分隔線與「開啟來源設定檔…」（以系統預設應用程式開啟 `sources.json`，檔案不存在就先建立；本 App 不被啟用）。每次選單即將開啟時 SHALL 重新讀取檔案，使手動編輯不需重啟即可看到。在帶子上按右鍵的選單與選單列選單 SHALL 相同。

#### Scenario: 顯示與打勾
- **WHEN** 目前來源為 `jin10`
- **THEN** 「來源」子選單中「金十數據」打勾，「FastBull 快訊」不打勾

#### Scenario: 手動編輯後
- **WHEN** 使用者在編輯器新增一筆合法來源並存檔，再開啟選單
- **THEN** 新來源出現在子選單中（不需重啟 App）

### Requirement: 即時切換
點選另一個可用來源時，App SHALL：(1) 寫回 `selected`；(2) 以計畫性重啟（沿用輪詢間隔變更的機制）用新的 `--source` 重啟 helper，保留目前輪詢間隔；(3) 重設排程器與畫面，清掉舊來源的歷史、即時佇列與帶子上的訊息；(4) 套用新來源的標籤（見下一條）。從舊 helper 送來、在切換之後才處理的訊息 MUST 被丟棄。點選已選的來源 MUST 無動作。切換期間 App MUST NOT 崩潰或殘留兩個 helper。

#### Scenario: 從 FastBull 切到金十
- **WHEN** 使用者點「金十數據」
- **THEN** 一個新的 `--source jin10` helper 啟動、舊 helper 結束，畫面只含金十的訊息

#### Scenario: 舊訊息不會殘留
- **WHEN** 切換前帶子上有 FastBull 訊息
- **THEN** 切換完成後帶子與重播清單中沒有任何 `source` 為 `fastbull` 的訊息

#### Scenario: 重複點選
- **WHEN** 點選目前已打勾的來源
- **THEN** 不重啟 helper

#### Scenario: 切換後晚到的舊訊息
- **WHEN** 切換之後才收到舊 helper 的 `snapshot`
- **THEN** 該訊息被丟棄，不進入排程器

### Requirement: 標籤文字隨來源
目前來源有 `label` 時，左側標籤 SHALL 顯示該 `label`，且 MUST NOT 修改 `style.json`；沒有 `label` 的來源使用 `style.json` 的 `labelText`。`style.json` 的 `showLabel`、顏色等其他設定不受影響。

#### Scenario: 來源有標籤
- **WHEN** 目前來源 `label` 為「金十數據」，`style.json` 的 `labelText` 為預設
- **THEN** 標籤顯示「金十數據」，`style.json` 內容不變

#### Scenario: 來源沒有標籤
- **WHEN** 目前來源沒有 `label`
- **THEN** 標籤顯示 `style.json` 的 `labelText`

### Requirement: 環境變數優先且不寫檔
設定了 `NEWSTICKER_SOURCE` 時，啟動 SHALL 使用該來源（即使它不在清單中，只要 helper 認得），MUST NOT 寫入 `sources.json` 的 `selected`；之後從選單切換仍可進行並寫檔。未設定時行為由 `sources.json` 決定。

#### Scenario: 環境變數指定
- **WHEN** 以 `NEWSTICKER_SOURCE=jin10` 啟動且檔案 `selected` 為 `fastbull`
- **THEN** 本次使用 jin10，檔案 `selected` 仍為 `fastbull`
