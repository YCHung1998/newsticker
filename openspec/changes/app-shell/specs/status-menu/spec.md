## ADDED Requirements

### Requirement: 選單列項目與選單內容
`StatusMenu` MUST 以 `NSStatusItem`＋`NSMenu` 實作，選單 SHALL 含：透明度滑桿（`NSMenuItem.view`）、隱藏／顯示切換、點穿開關、結束。不做設定頁與全域快捷鍵。

#### Scenario: 選單項目齊全
- **WHEN** 建立選單
- **THEN** 單元測試 SHALL 驗證四類項目都存在且標題與狀態正確（隱藏時顯示「顯示」）

### Requirement: 面板右鍵後備入口
在面板上按右鍵 MUST 彈出與選單列相同的選單（同一份 `NSMenu` 實例或同一建構函式），作為選單列項目被隱藏或擠掉時的後備入口。

#### Scenario: 右鍵選單
- **WHEN** 在面板上按右鍵
- **THEN** SHALL 出現與選單列相同的項目，且操作結果一致

### Requirement: 點穿模式不跨重啟保存
點穿開啟時面板 MUST 忽略滑鼠事件（`ignoresMouseEvents = true`）；此狀態 MUST NOT 寫入任何持久化儲存，每次啟動 MUST 重置為關。點穿開啟時，選單列選單 MUST 仍可用以關閉它。

#### Scenario: 重啟重置
- **WHEN** 開啟點穿後結束並重新啟動 App
- **THEN** 點穿 SHALL 為關，面板 SHALL 可被點擊拖曳

#### Scenario: 持久化檢查
- **WHEN** 開啟點穿後檢查 UserDefaults 與存檔檔案
- **THEN** SHALL 不含點穿欄位

### Requirement: 隱藏與顯示
隱藏 MUST 讓面板不可見並通知 `TickerRenderer`／`TickerScheduler` 凍結 tape 時間；顯示 MUST 接著原位置續走。隱藏期間新訊息仍進佇列【假設 A6，佇列上限 30 為假設 A7】。

#### Scenario: 隱藏後恢復
- **WHEN** 隱藏 10 秒後顯示
- **THEN** 帶子 SHALL 從隱藏前的 tape 位置續走，無可見跳動（目視驗收）

### Requirement: 選單展開期間計時器不斷料
選單展開（`NSEventTrackingRunLoopMode`）期間，補料計時器 MUST 持續觸發。計時器種類（`.common` mode 的 `Timer` 或 `DispatchSourceTimer`）MUST 依 spike S3 決定章節實作【依 spike-decisions，被 S3 結果阻塞】，MUST NOT 使用預設 mode 的 `Timer`。

#### Scenario: 展開 60 秒
- **WHEN** 選單展開 60 秒以上並拖動滑桿
- **THEN** 帶子 SHALL 無空白、滑桿 SHALL 即時生效、補料誤差 SHALL < 100ms（需人工，於正式 bundle 補驗）

### Requirement: 結束
選擇「結束」MUST 觸發 `FeedClient` 的正常結束流程（見 `feed-client`）後再終止 App。

#### Scenario: 結束時 helper 收尾
- **WHEN** 按下結束
- **THEN** helper SHALL 在逾時內結束，不留孤兒行程
