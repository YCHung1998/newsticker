## Why

使用者對 navigation／style 成果做了第二輪目視驗收：連結、滑鼠停留暫停、左右切換暫停都很好，但有三點要調：(1) 左右切換後的停留 8 秒太久，改為 1 秒；(2) 控制列 `< (n/N) >` 的三個符號垂直沒對齊（離屏圖 `Tests/evidence/n3-panel-offscreen.png` 中 `<`、`>` 偏低、`(n/N)` 偏高）；(3) 控制列要移到標籤旁邊（面板前段），而不是面板右端。這些是使用者親自提出的明確要求，視為已確認，直接 propose 後 apply。

## What Changes

- `seekHoldSeconds` 預設值由 8 秒改為 **1 秒**（`SchedulerConfig`；行為語意不變：重設不累加、凍結與隱藏期間不消耗）。
- 面板版面改為：〔（預留）齒輪槽〕→ 紅色標籤「即時財經快訊」→ 控制列 `< (n/N) >` → 訊息帶子。控制列緊貼標籤右側；面板仍 620 寬，帶子可視寬度仍為 620 − 150 − 100 = 370；`showLabel=false` 時控制列貼面板左緣、可視寬度 520。帶子座標 0（`seek` 對齊位置與 `readingInset` 參考線）隨之移到控制列右緣。
- `ControlStripLayout` 的範圍函式、命中測試的座標與迴紋針命中區、`TickerView` 圖層版面、`StyleApplier`（`showLabel` 切換）同步更新。
- 控制列三個符號垂直對齊：以離屏位圖的像素「墨跡外框」量測，三者垂直中心兩兩 ≤ 1 device px，且相對控制列高度置中 ≤ 1 device px。`<`、`>` 改為路徑自繪 chevron，`(n/N)` 改為依墨跡外框置中的位圖。
- 控制列背景延伸到標籤斜切邊下方，避免標籤與控制列間露出三角縫隙。
- README 預覽圖 `docs/preview/ticker-modes.svg` 與第 5／7／8 節文字同步（控制列位置、停留 1 秒）。
- **不做**：齒輪設定介面（使用者說最後做）；僅在版面規格中確保日後可在標籤左側插入固定寬度的齒輪槽（design.md 說明預留方式）。

## Capabilities

### New Capabilities
（無）

### Modified Capabilities
- `ticker-navigation`：「控制列的位置與版面」（位置改到標籤右側、可視寬度與座標公式、符號垂直對齊標準、齒輪槽預留）、「切換後暫停自動捲動並恢復」（8 秒 → 1 秒）、「命中測試與拖曳區分」（座標隨控制列位置）。
- `ticker-scheduler`：「注入的時鐘與設定」（`seekHoldSeconds` 預設 1、`readingInset` 參考線說明）、「捲動保持與指標停留凍結」（場景數字 8 秒 → 1 秒）。

## Impact

- 程式：`Sources/FastBullTickerCore/TickerScheduler.swift`（預設值）；`Sources/FastBullTickerApp/` 的 `ControlStripLayout.swift`、`HitTesting.swift`、`TickerView.swift`、`ShellConfig.swift`（僅在需要時最小增修）、新檔 `ControlStripGlyphs.swift`。
- 測試：既有硬編「控制列在右端」「8 秒」的斷言改成新規格（不刪除斷言）；新增對齊量測與 mutation。
- 文件：README、`docs/preview/ticker-modes.svg`、`Tests/README.md`。
- 不影響：協定、helper、Connect engine、主 specs 以外的其他 change。
