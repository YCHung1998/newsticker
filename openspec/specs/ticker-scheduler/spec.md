# ticker-scheduler Specification

## Purpose
TBD - created by archiving change show-engine-core. Update Purpose after archive.
## Requirements
### Requirement: 輸出介面與渲染方案無關
`TickerScheduler` 的公開輸出 SHALL 僅包含：(a) 每則已排入訊息的 `tapeX`、`width`、樣式類型（`live`／`replay`）、時間字串、（可能被截斷的）文字、訊息識別（`source`、`id`）；(b) 在給定 tape 時間下的位移（`scrollOffset`）。Core MUST NOT 輸出或引用任何渲染細節（layer、bitmap、displayLink、`CABasicAnimation`、像素密度、幀率）。本介面 MUST 同時能被 displayLink 與線性 `CABasicAnimation` 兩種渲染方案使用，不預設 `panel-feasibility-spikes` S4 的結果。

#### Scenario: 輸出不含渲染型別
- **WHEN** 檢查 Core 的公開 API 與 import
- **THEN** SHALL 不出現渲染框架型別（由 `core-package` 的 import 檢查加上 API 審視確認）

### Requirement: 注入的時鐘與設定
排程器 SHALL 接受注入的單調時鐘（回傳秒數）與設定：捲動速度（px/s，固定常數，數值於 apply 時目測調整，本規格不指定）、訊息間距 `gap`、視窗寬度 `viewportWidth`、最大訊息寬度、即時佇列上限（預設 30）、重播則數（預設 10）。Core MUST NOT 直接讀取系統時間。時鐘為單調時鐘；回撥（新值小於舊值）SHALL 視為 0 增量而非讓 tape 時間倒退。

#### Scenario: 假時鐘驅動
- **WHEN** 測試以假時鐘將時間前進 5 秒
- **THEN** tape 時間 SHALL 前進 5 秒（可見狀態下），不涉及真實等待

#### Scenario: 時鐘回撥
- **WHEN** 假時鐘回傳比上次小的值
- **THEN** tape 時間 SHALL 不倒退

### Requirement: tape 座標模型
排程器 SHALL 採 tape 座標：每則訊息在被排入帶子的當下取得固定的 `tapeX`（左緣）與 `width`，之後 MUST NOT 改變（唯一例外為下方 rebase，它對所有訊息施加同一個位移）。`scrollOffset` 為 tape 時間的純函數（`baseOffset + speed × tapeTime`），訊息的視覺位置為 `tapeX − scrollOffset`。排程器 MUST NOT 以逐幀累加位置的方式維護狀態。

#### Scenario: 排入後 tapeX 不變
- **WHEN** 一則訊息已排入，之後發生：時間前進、新訊息抵達、模式切換、隱藏後恢復
- **THEN** 該則的 `tapeX` 與 `width` SHALL 與排入時相同

#### Scenario: 位置是 tape 時間的純函數
- **WHEN** 對同一排程器狀態，以任意順序查詢多個 tape 時間的位移
- **THEN** 結果 SHALL 僅取決於該 tape 時間，與查詢順序、查詢次數無關

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
排程器 SHALL 提供 rebase 介面，用以避免座標過大導致渲染端 Float32 精度劣化（背景：60px/s 跑 24 小時約 5M px，Float32 精度約 0.5px，設計文件 5.2）。rebase MUST 對所有已排入訊息的 `tapeX` 與 `baseOffset` 施加同一個位移 `delta`，使每則訊息的視覺位置（`tapeX − scrollOffset`）在 rebase 前後完全相同（浮點誤差在測試容忍度內，Core 內部以 Double 計算）；並 SHALL 回傳 `delta` 供渲染端同步其座標。rebase MAY 移除已完全捲出視窗左緣的訊息，但 MUST 保留尾端訊息以維持間距。rebase MUST NOT 改變訊息的相對間距、排入順序、模式或佇列。何時呼叫由呼叫端決定（Core 只提供介面與「建議 rebase 的閾值判斷」純函數），且 Core MUST NOT 綁定任何渲染 API。

#### Scenario: rebase 後視覺位置不變
- **WHEN** 排程器跑了很長的 tape 時間，記錄所有訊息視覺位置後執行 rebase
- **THEN** 每則的視覺位置 SHALL 不變，`scrollOffset` 與 `tapeX` 的絕對值 SHALL 明顯變小

#### Scenario: rebase 後繼續補料
- **WHEN** rebase 後繼續 tick
- **THEN** 新排入訊息與尾端的間距 SHALL 仍為 `gap`，與未 rebase 的對照排程器輸出的視覺位置 SHALL 一致

#### Scenario: rebase 不影響凍結
- **WHEN** 在隱藏狀態下執行 rebase 後恢復
- **THEN** 位置 SHALL 不跳動

