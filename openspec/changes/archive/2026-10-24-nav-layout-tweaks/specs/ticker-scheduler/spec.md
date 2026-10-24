## MODIFIED Requirements

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
