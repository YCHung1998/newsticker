# ticker-scheduler Specification

## Purpose
TBD - created by archiving change show-engine-core. Update Purpose after archive.
## Requirements
### Requirement: 輸出介面與渲染方案無關
`TickerScheduler` 的公開輸出 SHALL 僅包含：(a) 每則已排入訊息的 `tapeX`、`width`、樣式類型（`live`／`replay`）、時間字串、（可能被截斷的）文字、訊息識別（`source`、`id`）、選填連結 `url`（原樣取自 `Item.url`）、排入序號 `seq`、所屬清單識別 `listID` 與清單內序號 `listIndex`；(b) 在給定 tape 時間下的位移（`scrollOffset`）；(c) 閱讀位置（`ReadingPosition`）與 seek 結果（`SeekOutcome`）。Core MUST NOT 輸出或引用任何渲染細節（layer、bitmap、displayLink、`CABasicAnimation`、像素密度、幀率）。本介面 MUST 同時能被 displayLink 與線性 `CABasicAnimation` 兩種渲染方案使用，不預設 `panel-feasibility-spikes` S4 的結果。

#### Scenario: 輸出不含渲染型別
- **WHEN** 檢查 Core 的公開 API 與 import
- **THEN** SHALL 不出現渲染框架型別（由 `core-package` 的 import 檢查加上 API 審視確認）

#### Scenario: 輸出帶有連結與清單資訊
- **WHEN** 排入一則含 `url` 的訊息
- **THEN** 對應的 `PlacedItem` SHALL 含相同的 `url`、`seq`、`listID`、`listIndex`，且不含任何渲染型別

### Requirement: 注入的時鐘與設定
排程器 SHALL 接受注入的單調時鐘（回傳秒數）與設定：捲動速度（px/s，固定常數，數值於 apply 時目測調整，本規格不指定）、訊息間距 `gap`、視窗寬度 `viewportWidth`、最大訊息寬度、即時佇列上限（預設 30）、重播則數（預設 10）、切換後捲動保持秒數 `seekHoldSeconds`（預設 1【假設，使用者回饋第二輪：由 8 秒改為 1 秒】）、閱讀位置內縮 `readingInset`（預設 24pt【假設】；自「視窗左緣」即 `viewportWidth` 所涵蓋可視區的左緣起算，App 層把可視區左緣放在控制列右緣，故參考線隨可視區左緣移動，Core 不需改動）、連結欄位寬度 `linkSlotWidth`（預設 0；實際值由 App 層設定）、rebase 後至少保留的已排入訊息數 `retainPlacedCount`（預設 64【假設】）。Core MUST NOT 直接讀取系統時間。時鐘為單調時鐘；回撥（新值小於舊值）SHALL 視為 0 增量而非讓 tape 時間倒退。

#### Scenario: 假時鐘驅動
- **WHEN** 測試以假時鐘將時間前進 5 秒
- **THEN** tape 時間 SHALL 前進 5 秒（可見狀態下），不涉及真實等待

#### Scenario: 時鐘回撥
- **WHEN** 假時鐘回傳比上次小的值
- **THEN** tape 時間 SHALL 不倒退

#### Scenario: 新設定的預設值
- **WHEN** 以預設 `SchedulerConfig` 建立排程器
- **THEN** `seekHoldSeconds` SHALL 為 1、`readingInset` SHALL 為 24、`linkSlotWidth` SHALL 為 0、`retainPlacedCount` SHALL 為 64，且既有測試的行為 SHALL 不變

### Requirement: tape 座標模型
排程器 SHALL 採 tape 座標：每則訊息在被排入帶子的當下取得固定的 `tapeX`（左緣）與 `width`，之後 MUST NOT 改變（唯一例外為下方 rebase，它對所有訊息施加同一個位移；seek 與捲動保持只改變 `baseOffset` 與保持計時，MUST NOT 改變任何 `tapeX`／`width`）。在兩次 seek／rebase 之間，`scrollOffset` 為 tape 時間的純函數（`baseOffset + speed × tapeTime`；seek 與 rebase 是離散事件，各自調整 `baseOffset`），訊息的視覺位置為 `tapeX − scrollOffset`。排程器 MUST NOT 以逐幀累加位置的方式維護狀態。

#### Scenario: 排入後 tapeX 不變
- **WHEN** 一則訊息已排入，之後發生：時間前進、新訊息抵達、模式切換、隱藏後恢復
- **THEN** 該則的 `tapeX` 與 `width` SHALL 與排入時相同

#### Scenario: 位置是 tape 時間的純函數
- **WHEN** 對同一排程器狀態，以任意順序查詢多個 tape 時間的位移
- **THEN** 結果 SHALL 僅取決於該 tape 時間，與查詢順序、查詢次數無關

#### Scenario: seek 後 tapeX 不變
- **WHEN** 已排入若干訊息後執行 `<` 或 `>` 的 seek
- **THEN** 所有已排入訊息的 `tapeX` 與 `width` SHALL 與 seek 前相同，僅 `scrollOffset` 改變

### Requirement: 供料器在尾端有空位時補下一則
當帶子尾端（最後一則的 `tapeX + width + gap`）小於等於視窗右緣（`scrollOffset + viewportWidth`）時，排程器 SHALL 補下一則，其 `tapeX` 為「尾端 + gap」，使連續訊息間距恆為 `gap`，且與補料時機（tick 頻率）無關。帶子上沒有任何尚未完全離開的訊息時，下一則的 `tapeX` SHALL 為視窗右緣。一次 tick 若有多則可補 SHALL 連續補到尾端超出右緣為止。無料可補（見下）時 SHALL 不補且不報錯。

#### Scenario: 間距固定
- **WHEN** 連續排入三則訊息，tick 時機不規則（含較晚的 tick）
- **THEN** 相鄰訊息的 `tapeX` 差 SHALL 恆等於前一則的 `width + gap`

#### Scenario: 空帶子
- **WHEN** 帶子上沒有訊息且有料可補
- **THEN** 第一則的 `tapeX` SHALL 等於當時的視窗右緣

#### Scenario: 尾端無空位
- **WHEN** 尾端 + gap 大於視窗右緣
- **THEN** SHALL 不補料

### Requirement: 歷史與最新 10 則
排程器 SHALL 維護歷史集合：收到 `snapshot` 時以其 `items` 取代歷史；收到 `items` 時把新訊息併入歷史。歷史依 `published_at_ms` 由新到舊，以 `source` 加 `id` 去重（同一鍵以後到者為準；已在歷史中的鍵再度出現於 `items` 時，只更新歷史，MUST NOT 再次進即時佇列）【假設：設計文件的去重在 helper 端，Core 為防禦性去重，使用者 2026-10-24 確認維持暫定，仍標假設】。歷史以 `historyLimit`（預設 200【假設】）為上限，只保留最新者，供重播取用的「最新 10 則」為其前 10 筆。進入即時佇列的訊息 SHALL 同時併入歷史，即使之後因佇列上限被丟棄也不得自歷史移除。啟動後中途收到的新 `snapshot`（例如 helper 洪水保護重設基準）只取代歷史，MUST NOT 清除即時佇列或已排入帶子的訊息，也 MUST NOT 觸發 LIVE【已決定 2026-10-24（使用者決定視為重設基準），細節仍為【假設】：中途 snapshot 不重設重播游標】。

#### Scenario: snapshot 建立歷史
- **WHEN** 收到含 15 則的 `snapshot`
- **THEN** 重播取用的最新 10 則 SHALL 為其中 `published_at_ms` 最大的 10 則，由新到舊

#### Scenario: items 併入歷史並擠掉最舊
- **WHEN** 歷史為 10 則後又收到 2 則更新的 `items`
- **THEN** 最新 10 則 SHALL 含這 2 則新訊息與原本較新的 8 則

### Requirement: REPLAY／LIVE 狀態機
排程器 SHALL 具 REPLAY 與 LIVE 兩個狀態，供料器依狀態取料，樣式跟著每則訊息（即時訊息為 `live`、重播訊息為 `replay`），已在帶子上的訊息 MUST NOT 被改樣式：

1. 啟動後收到的第一個 `snapshot` 為歷史，狀態維持 REPLAY，MUST NOT 產生任何 `live` 訊息。
2. 收到 `items` → 進即時佇列（舊到新依序，【假設 A1】）。REPLAY 中收到新訊息時，帶子上已排入的訊息 MUST NOT 被中斷、移除或改位置；新訊息 SHALL 接在帶子尾端已排入的最後一則之後，供料器切為 LIVE。
3. LIVE 中再收到 `items` → 追加到即時佇列尾端。
4. 即時佇列被取空（供料器補料時發現佇列為空）→ 回 REPLAY，重新取最新 10 則（含剛播過的），從最新一則開始循環；循環至第 10 則後回到最新一則。
5. 每則即時訊息只播一次【假設 A2】；重播為黑底白字樣式類型 `replay`【假設 A3，樣式的視覺呈現屬 `app-shell`】。
6. REPLAY 且歷史為空時，供料器無料可補，帶子保持空白【假設：設計文件未規定，例如 helper 尚未送出 snapshot 之前】。
7. 在收到任何 `snapshot` 之前就收到 `items`，SHALL 忽略該 `items` 並回報錯誤事件（`itemsBeforeSnapshotIgnored`），MUST NOT 進佇列或歷史【已決定 2026-10-24（因 helper 保證先發 snapshot）；事件命名為【假設】】。

「佇列播完」的判定以供料器補料時佇列為空為準（即最後一則即時訊息已排入帶子），而非該訊息已捲出視窗；此為對設計文件措辭「即時佇列播完」的詮釋【假設：使用者 2026-10-24 確認沿用提案暫定值，仍標假設】。

#### Scenario: 啟動 snapshot 不觸發 LIVE
- **WHEN** 排程器初始化後收到一個含 10 則的 `snapshot`，並持續 tick 超過一輪
- **THEN** 所有排入訊息的樣式 SHALL 為 `replay`，狀態 SHALL 為 REPLAY，且無 `live` 訊息

#### Scenario: REPLAY 中新訊息接尾且不打斷
- **WHEN** REPLAY 進行中帶子上已有訊息 R1、R2（尾端為 R2），此時收到一則新訊息 N
- **THEN** R1、R2 的 `tapeX` SHALL 不變、仍在帶子上；N SHALL 為下一則排入，其 `tapeX` 為 R2 尾端加 `gap`，樣式為 `live`；狀態 SHALL 為 LIVE

#### Scenario: LIVE 中追加
- **WHEN** LIVE 中佇列有 N1，又收到 N2、N3
- **THEN** 之後排入順序 SHALL 為 N1、N2、N3，樣式皆 `live`

#### Scenario: LIVE 播完回 REPLAY 且從最新開始
- **WHEN** 即時佇列中的訊息已全部排入，供料器下次補料
- **THEN** 狀態 SHALL 回 REPLAY，下一則為歷史最新 10 則中最新的一則（樣式 `replay`），其後依新到舊循環；歷史 SHALL 已包含剛播過的即時訊息

#### Scenario: 多則即時訊息由舊到新
- **WHEN** 一次 `items` 含 3 則（舊到新 N1、N2、N3）
- **THEN** 排入順序 SHALL 為 N1、N2、N3【假設 A1】

#### Scenario: 已排入訊息不改樣式
- **WHEN** 帶子上有 `replay` 訊息，之後狀態切為 LIVE
- **THEN** 已排入的 `replay` 訊息 SHALL 仍為 `replay`

#### Scenario: 重播循環
- **WHEN** REPLAY 持續補料超過 10 則
- **THEN** 第 11 則 SHALL 回到最新一則，循環不中斷

### Requirement: 即時佇列上限
尚未排入帶子的即時佇列 SHALL 上限為 30 則；超過時 MUST 丟棄最舊的未排入訊息，保留較新者【假設 A7：上限 30、丟最舊】。被丟棄的訊息 SHALL 仍留在歷史中，因此若屬最新 10 則則仍會出現在之後的重播。排程器 SHALL 提供被丟棄數量或等價資訊供記錄。

#### Scenario: 超過 30 則丟最舊
- **WHEN** 隱藏期間累積 35 則 `items`
- **THEN** 即時佇列 SHALL 為最新 30 則，最舊 5 則被丟棄，丟棄數量 SHALL 為 5

#### Scenario: 被丟者仍在最新 10 則
- **WHEN** 上述被丟棄的 5 則之一屬歷史最新 10 則
- **THEN** 它 SHALL 仍出現在之後 REPLAY 的循環中

#### Scenario: 剛好 30 則不丟
- **WHEN** 佇列累積恰 30 則
- **THEN** SHALL 不丟棄任何一則

### Requirement: 隱藏時凍結 tape 時間
排程器 SHALL 提供可見性控制。隱藏期間 tape 時間 MUST 凍結（`scrollOffset` 不變、不補料）；恢復後 SHALL 從凍結的 tape 時間接著走，任何訊息的視覺位置在恢復瞬間 MUST NOT 跳動，隱藏的實際時長不得影響位置。隱藏期間收到的新訊息仍 SHALL 進即時佇列與歷史【假設 A6】，受佇列上限約束；恢復後依一般規則補料。重複隱藏、重複顯示 SHALL 為冪等。

#### Scenario: 凍結恢復不跳動
- **WHEN** 於時間 T 記錄所有訊息視覺位置後隱藏，假時鐘前進 1 小時後恢復，立即查詢位置
- **THEN** 位置 SHALL 與隱藏當下完全相同

#### Scenario: 恢復後接著走
- **WHEN** 恢復後再前進 2 秒
- **THEN** `scrollOffset` SHALL 比凍結值多 `2 × speed`

#### Scenario: 隱藏期間新訊息仍入佇列
- **WHEN** 隱藏期間收到 `items`
- **THEN** 隱藏期間 SHALL 不補料；恢復後 SHALL 依狀態機補出該新訊息

#### Scenario: 重複隱藏
- **WHEN** 連續兩次呼叫隱藏
- **THEN** 凍結的 tape 時間 SHALL 與第一次隱藏時相同

### Requirement: 定期 rebase 的純函數介面
排程器 SHALL 提供 rebase 介面，用以避免座標過大導致渲染端 Float32 精度劣化（背景：60px/s 跑 24 小時約 5M px，Float32 精度約 0.5px，設計文件 5.2）。rebase MUST 對所有已排入訊息的 `tapeX` 與 `baseOffset` 施加同一個位移 `delta`，使每則訊息的視覺位置（`tapeX − scrollOffset`）在 rebase 前後完全相同（浮點誤差在測試容忍度內，Core 內部以 Double 計算）；並 SHALL 回傳 `delta` 供渲染端同步其座標。rebase MAY 移除已完全捲出視窗左緣的訊息，但 MUST 保留尾端訊息以維持間距，並 MUST 保留最近排入的至少 `retainPlacedCount` 則（即使已捲出左緣、座標為負），使 `<` 仍可回溯到同一清單的前一則。rebase MUST NOT 改變訊息的相對間距、排入順序、模式或佇列。何時呼叫由呼叫端決定（Core 只提供介面與「建議 rebase 的閾值判斷」純函數），且 Core MUST NOT 綁定任何渲染 API。

#### Scenario: rebase 後視覺位置不變
- **WHEN** 排程器跑了很長的 tape 時間，記錄所有訊息視覺位置後執行 rebase
- **THEN** 每則的視覺位置 SHALL 不變，`scrollOffset` 與 `tapeX` 的絕對值 SHALL 明顯變小

#### Scenario: rebase 後繼續補料
- **WHEN** rebase 後繼續 tick
- **THEN** 新排入訊息與尾端的間距 SHALL 仍為 `gap`，與未 rebase 的對照排程器輸出的視覺位置 SHALL 一致

#### Scenario: rebase 不影響凍結
- **WHEN** 在隱藏狀態下執行 rebase 後恢復
- **THEN** 位置 SHALL 不跳動

#### Scenario: rebase 後仍可回溯
- **WHEN** 同一重播清單的第 5 則為閱讀中，第 4 則已捲出左緣，執行 rebase 後再按 `<`
- **THEN** 第 4 則 SHALL 仍被保留（`tapeX` 可為負），seek SHALL 成功對齊到它，且對齊後各訊息相對間距 SHALL 不變

### Requirement: 排入序號與清單識別
每則排入的訊息 SHALL 帶有：`seq`（排程器內單調遞增的排入序號，從 1 起，唯一識別一次「排入」；同一則歷史訊息在重播中多次排入會有不同 `seq`）、`listID`（所屬「清單」的識別）、`listIndex`（在該清單內的序號，從 1 起）。「清單」定義【假設】：(a) 重播清單＝一輪重播：從重播游標在最新一則（名次 1）開始排入、到游標繞回為止；每當重播游標回到起點（含供料器由 LIVE 回到 REPLAY）即開始新的一輪並取得新的 `listID`；`listIndex` 為該則在「當時最新 N 則」中的名次（最新者為 1，N 為重播則數與歷史實際則數的較小者）；清單總數＝該輪開始時的 `latestItems.count`。(b) 即時清單＝一個即時批次：每次由 REPLAY 切為 LIVE 起算的連續即時訊息；取得新的 `listID`，`listIndex` 為批次內的排入順序（舊到新，從 1 起）；清單總數＝「已排入該批次的訊息數＋尚在即時佇列中的訊息數」，隨 LIVE 中追加而增加，供料器回到 REPLAY 時批次關閉、總數固定。`PlacedItem` 另 SHALL 傳遞 `url`。`seq`、`listID`、`listIndex`、`url` 與 `tapeX` 一樣，排入後 MUST NOT 改變。

#### Scenario: 重播一輪的序號
- **WHEN** 歷史有 10 則且連續排入 11 則重播訊息
- **THEN** 前 10 則 SHALL 有相同 `listID` 且 `listIndex` 依序為 1 至 10；第 11 則 SHALL 為新的 `listID` 且 `listIndex` 為 1；11 則的 `seq` SHALL 互不相同且遞增

#### Scenario: 即時批次的序號與總數
- **WHEN** 一次 `items` 含 N1、N2、N3 並依序排入
- **THEN** 三則 SHALL 有相同 `listID`，`listIndex` 依序為 1、2、3；排入 N1 後批次總數 SHALL 為 3

#### Scenario: LIVE 追加使批次總數增加
- **WHEN** N1 已排入，之後又收到 N2
- **THEN** N1 所屬批次的總數 SHALL 由 1 變為 2

#### Scenario: 歷史不足 N 則
- **WHEN** 歷史只有 7 則且重播則數為 10
- **THEN** 重播清單總數 SHALL 為 7

### Requirement: 閱讀位置查詢
排程器 SHALL 提供純函數查詢目前「閱讀中那一則」：在目前保留的已排入訊息中（依排入順序），取第一則同時滿足「右緣 `tapeX + width − scrollOffset` 大於 `readingInset`」與「左緣 `tapeX − scrollOffset` 小於 `viewportWidth`」者；不存在則為 `nil`（空帶子、全部尚在視窗右緣之外、或全部已捲出）。`readingPosition` SHALL 回傳 `ReadingPosition(item, index, total)`：`total` 為該則所屬清單的目前總數（定義見「排入序號與清單識別」），`index` 為 `min(item.listIndex, total)`。同一排程器狀態與同一 tape 時間 MUST 得到相同結果，查詢 MUST NOT 改變任何狀態。隱藏期間查詢結果 MUST 與隱藏當下相同。以靠近標籤右側（視窗左緣）的那一則為準，是對使用者「滾動到第幾則」的詮釋【假設】。

#### Scenario: 靠左緣者為閱讀中
- **WHEN** A 的視覺左緣為 −100、寬度 200（右緣 100），B 緊接在後
- **THEN** 閱讀中 SHALL 為 A

#### Scenario: 剛好離開內縮線
- **WHEN** A 的右緣等於 `readingInset`
- **THEN** 閱讀中 SHALL 為 B（右緣須「大於」內縮線）

#### Scenario: 全在右緣之外
- **WHEN** 帶子上唯一一則的左緣大於等於 `viewportWidth`
- **THEN** 閱讀位置 SHALL 為 `nil`

#### Scenario: 重播位置
- **WHEN** 重播清單的第 3 則為閱讀中
- **THEN** `ReadingPosition` 的 `index` SHALL 為 3、`total` SHALL 為 10

#### Scenario: 查詢無副作用
- **WHEN** 連續查詢閱讀位置兩次，中間不呼叫其他操作
- **THEN** 兩次結果 SHALL 相同，且 `placed`、`tapeTime`、`scrollOffset` SHALL 不變

### Requirement: seek 前後切換
排程器 SHALL 提供 `seek(.previous)` 與 `seek(.next)`，將閱讀中那一則的前一則／下一則對齊到閱讀位置。步驟：(1) 隱藏中 MUST 不動作（回傳 `hidden`）；(2) 先以時鐘推進 tape 時間；(3) 取閱讀中 R，`nil` 則不動作（`noReadingItem`）；(4) `.previous`：目標為已保留的、`seq = R.seq − 1` 且 `listID` 與 R 相同者；R 的 `listIndex` 為 1 時不動作（`atListStart`）；清單內前一則已不被保留時不動作（`previousNotRetained`）；(5) `.next`：目標為 `seq = R.seq + 1` 的已排入訊息；若尚未排入，MUST 立即強制排入「供料器下一次補料會取的那一則」（沿用既有狀態機：即時佇列優先，否則重播游標；`tapeX` 為尾端加 `gap`，與正常補料完全相同），因此清單最後一則按 `>` 即跳到「下一輪起點」（重播為最新一則）；無料可排則不動作（`noMaterial`）；(6) 對齊：調整 `baseOffset` 使目標的視覺左緣等於 0（視窗左緣），MUST 只改 `baseOffset`；(7) 將捲動保持計時設為 `seekHoldSeconds`（重設，不累加）；(8) 回傳 `moved(target, newlyPlaced)`。不動作的結果 MUST NOT 改變 `baseOffset` 與保持計時。對齊後閱讀中那一則 MUST 等於目標（`readingInset` 必須小於任何訊息的 `width`，由 `width ≥ 時間字串寬度` 保證，測試以斷言驗證）。

#### Scenario: 切到前一則
- **WHEN** 重播清單的第 5 則為閱讀中，執行 `seek(.previous)`
- **THEN** 第 4 則 SHALL 對齊到視覺左緣 0，閱讀位置 SHALL 為 4/10，保持計時 SHALL 為 `seekHoldSeconds`

#### Scenario: 切到下一則
- **WHEN** 重播清單的第 5 則為閱讀中，第 6 則已排入，執行 `seek(.next)`
- **THEN** 第 6 則 SHALL 對齊到視覺左緣 0，閱讀位置 SHALL 為 6/10

#### Scenario: 第一則按 previous 無動作
- **WHEN** 第 1 則為閱讀中，執行 `seek(.previous)`
- **THEN** 結果 SHALL 為 `atListStart`，`baseOffset` 與保持計時 SHALL 不變

#### Scenario: 最後一則按 next 跳到下一輪起點
- **WHEN** 重播清單第 10 則為閱讀中且為帶子上最後一則，即時佇列為空，執行 `seek(.next)`
- **THEN** SHALL 強制排入最新一則（新的 `listID`、`listIndex` 為 1），其 `tapeX` SHALL 等於第 10 則的 `tapeX + width + gap`，並對齊到視覺左緣 0；閱讀位置 SHALL 為 1/10

#### Scenario: next 取用即時佇列
- **WHEN** 重播清單最後一則為閱讀中且即時佇列有 N1，執行 `seek(.next)`
- **THEN** 被強制排入的 SHALL 為 N1（樣式 `live`），閱讀位置 SHALL 為 1/1

#### Scenario: seek 不改 tapeX
- **WHEN** 任一 seek 之後
- **THEN** 所有既有訊息的 `tapeX`、`width` SHALL 不變，相鄰訊息間距 SHALL 仍為 `gap`

#### Scenario: 隱藏中或空帶子
- **WHEN** 隱藏中或帶子上沒有閱讀中那一則時執行 seek
- **THEN** 結果 SHALL 分別為 `hidden`、`noReadingItem`，狀態 SHALL 不變

#### Scenario: 清單內前一則已不被保留
- **WHEN** 閱讀中那一則的 `listIndex` 大於 1，但其前一則已不在保留的已排入訊息中
- **THEN** `seek(.previous)` SHALL 回傳 `previousNotRetained` 且狀態不變（正常情況下由 `retainPlacedCount` 避免）

### Requirement: 捲動保持與指標停留凍結
排程器 SHALL 提供兩種不改變任何 `tapeX` 的暫停機制，且皆為純函數、由注入時鐘驅動：(1) 捲動保持（hold）：seek 成功後 `holdRemaining = seekHoldSeconds`；時鐘前進時，先消耗 `holdRemaining`，剩餘的時間才推進 tape 時間；保持期間 `scrollOffset` MUST 不變，期滿後 MUST 從對齊位置接著走、無跳動。再次成功 seek MUST 重設為完整 `seekHoldSeconds`。`seekHoldSeconds` 為 0 表示不保持。(2) 指標停留凍結：`setPointerInside(true)` 後，時鐘前進 MUST NOT 推進 tape 時間，也 MUST NOT 消耗 `holdRemaining`；`setPointerInside(false)` 後從凍結位置接著走（若仍有保持剩餘則續算）。隱藏（`hide()`）與指標停留 MUST 各自獨立且任一成立即不推進；重複設定同一值 MUST 冪等。保持與凍結期間 `tick()` MUST 仍照常補料（尾端有空位時），以免帶子出現空白。呼叫 `setPointerInside` 前 MUST 先以時鐘推進 tape 時間，使狀態切換前的時間不被誤算。

#### Scenario: 保持 `seekHoldSeconds` 後恢復
- **WHEN** 以預設 `seekHoldSeconds`（1）建立，seek 成功後假時鐘前進 0.5 秒，再前進 0.5 秒，再前進 2 秒（速度 90 px/s）
- **THEN** 前兩段後 `scrollOffset` SHALL 與 seek 後相同；第三段後 SHALL 增加 `2 × 90` px

#### Scenario: 再次 seek 重設保持
- **WHEN** seek 後 0.6 秒再次 seek 成功
- **THEN** 保持剩餘 SHALL 為 1 秒（而非 0.4 + 1 秒）

#### Scenario: 指標停留凍結且不消耗保持
- **WHEN** seek 後 `setPointerInside(true)`，假時鐘前進 30 秒，再 `setPointerInside(false)`
- **THEN** 凍結期間 `scrollOffset` SHALL 不變，離開後保持剩餘 SHALL 仍為 1 秒（凍結期間不計）

#### Scenario: 隱藏期間不消耗保持
- **WHEN** seek 後隱藏，假時鐘前進 1 小時後恢復
- **THEN** 恢復瞬間位置 SHALL 不變，保持剩餘 SHALL 仍為 1 秒

#### Scenario: 保持期間仍補料
- **WHEN** 保持期間尾端有空位（例如 `>` 強制排入後視窗右側不足）
- **THEN** `tick()` SHALL 補料至尾端超出右緣為止

#### Scenario: 冪等
- **WHEN** 連續兩次 `setPointerInside(true)`
- **THEN** 結果 SHALL 與一次相同，凍結位置 SHALL 為第一次呼叫當下

