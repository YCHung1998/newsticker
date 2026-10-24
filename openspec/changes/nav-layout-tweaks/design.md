## Context

現況（main，已合併 navigation／style）：控制列固定在面板右端 `[520, 620)`，標籤在左 `[0, 150)`，帶子可視區 `[150, 520)`（370）。`TickerView` 以三個 `CATextLayer`（20pt 高、置於控制列垂直中央的 frame）繪 `<`、`(n/N)`、`>`，字型 PingFang TC Semibold，`<`／`>` 16pt、指示 13pt。使用者目視回饋見 proposal。`ShellConfig.swift` 會被使用者手動編輯，本 change 對它只做最小增修（見決定 6）。

**對齊問題的根因（以量測證實）**：`CATextLayer` 把文字貼在 frame 頂端（不垂直置中），frame 高度固定 20pt，而三者字級不同（16／13），字型的 ascent／descent、`<` 的字形在 em box 中的位置也不同，因此「frame 置中」不等於「墨跡置中」。對現況離屏渲染（@2x，控制列高 84 px，中線 42）以墨跡外框量測：`<` 與 `>` 垂直中心 47.5 px（比中線低 5.5 px ≈ 2.75pt）、`(4/10)` 垂直中心 40.5 px（比中線高 1.5 px），`<` 與 `(n/N)` 差 7 px（3.5pt）。原始輸出：`Tests/evidence/nav-layout-align-red.log`。另外，PingFang TC 的 ASCII 括號字距偏寬（圖中 `(` 與數字間有明顯空隙），也影響視覺重心。

## Goals / Non-Goals

**Goals:**
- 停留 1 秒；控制列移到標籤右側；符號垂直對齊且有像素量測標準。
- 版面所有座標由單一偏移 `stripLeft`（標籤右緣）推導，使日後插入齒輪槽只需調整該偏移。

**Non-Goals:**
- 不做齒輪設定介面、不畫齒輪、不新增設定項。
- 不改 Core 的排程邏輯（只改預設值）、不改協定與 helper。
- 不改按鈕的 mouse-up 觸發、優先序、拖曳等行為。

## Decisions

1. **符號對齊以像素墨跡外框為標準**（而非 frame 置中或字型度量）。測試離屏渲染（`CALayer.render`，不開視窗，@2x），取與控制列底色色差 > 64（0–255）的像素的最小外接矩形，垂直中心 = (minRow + maxRow + 1) / 2；要求三者兩兩 ≤ 1 px 且相對控制列中線 ≤ 1 px。選 device px 而非 pt，是因為 pt 會把 2 px 偏差放寬成 1pt，標準更嚴。測試檔 `Tests/FastBullTickerAppTests/StripAlignmentTests.swift`，先對現況紅（見上）。
2. **【假設】`<`、`>` 以路徑自繪 chevron**（`CAShapeLayer`，stroke、圓頭圓角，寬 6pt × 高 12pt、線寬 1.8pt），中心＝按鈕區中心，兩者鏡像因此天生同高；不依賴字型度量。替代方案「改用同一字型同字級」仍受字形在 em box 位置影響、且 `<`／`>` 與括號數字的墨跡高度本來就不同，無法保證；否決。
3. **【假設】`(n/N)` 以位圖繪製並依墨跡外框置中**：`ControlStripGlyphs` 以 CoreText（半形 ASCII、`NSFont.monospacedDigitSystemFont` 13pt semibold，避免 PingFang 括號字距偏寬）把文字畫入控制列高度的位圖，用 `CTLineGetImageBounds` 取墨跡外框後置中並對齊 device pixel 格線。位圖以 `CALayer.contents` 顯示（每次文字變更重畫，成本可忽略：約 52×42pt）；縮放倍率取視窗 backing scale。替代：CATextLayer + 手動補償偏移，會把字型度量魔術數字寫死；否決。
4. **控制列位於標籤右側，座標由 `stripLeft` 推導**：`stripLeft` = 標籤寬（`showLabel=false` 時 0）；控制列 `[stripLeft, stripLeft + 100)`，帶子可視區 `[stripLeft + 100, 面板寬)`，可視寬度 = 面板寬 − stripLeft − 100（`showLabel` 時 370，否則 520）。`ControlStripLayout` 的範圍函式改以 `labelWidth`（即 `stripLeft`）為參數，不再依面板右緣。
5. **帶子座標 0 與 `readingInset`**：Core 的視覺座標 0 = 可視區左緣，`readingInset`（24pt）從那裡起算；App 把可視區左緣放在控制列右緣（面板座標 250），所以「閱讀位置參考線」自然隨可視區左緣移動，Core 不需改。`TickerView` 的 clip 圖層左緣因此為 `stripLeft + 100`，不再需要「標籤斜切突出」的 12pt 補償（因控制列不透明，會蓋住）。迴紋針命中區右緣面板座標 = `labelWidth + stripWidth + visualLeft + width`。
6. **標籤斜切與控制列的縫隙**：標籤右緣為 12pt 斜切，控制列在其右側，若控制列背景從 `stripLeft` 開始會在標籤下半部露出三角形縫隙。控制列背景圖層改從 `stripLeft − 12`（標籤顯示時）開始、畫在標籤圖層之下，由標籤蓋住重疊處。命中測試仍以 `stripLeft` 為界（斜切三角區屬標籤＝`.drag`）。`ShellConfig.swift`：預期只需新增（若需要）極小欄位或不改；若改，僅最小增修，不覆寫使用者的 `itemPadding`／`level` 手動修改。
7. **停留 1 秒**：只改 `SchedulerConfig.seekHoldSeconds` 預設值 8 → 1；`SchedulerInvariantTests` 中用 `seekHoldSeconds = 2` 的測試不受影響。App 層沒有另外的 8 秒常數（已 grep 確認只有 Core 預設值）。
8. **齒輪槽預留方式（本 change 不實作、不繪製）**：所有位置都從單一偏移 `stripLeft = 齒輪槽寬 + 標籤寬` 推導（`ControlStripLayout` 的函式吃 `labelWidth` 參數，語意為「控制列左側已被占用的寬度」）。日後加齒輪只需：(a) `ShellConfig` 新增 `gearSlotWidth`（預設 0），(b) 呼叫端把 `labelWidth` 換成 `gearSlotWidth + labelWidth`，(c) 標籤圖層 x 位移 `gearSlotWidth`。控制列內部三段相對版面、可視寬度公式、命中優先序都不用改（齒輪槽落在 `.drag` 或日後新增的 `.gear` 目標）。面板總寬不變時可視寬度會再縮 G；是否放大面板留給齒輪那個 change 決定。

## Risks / Trade-offs

- [離屏渲染不等於實機合成] → 對齊以像素量測自動驗證，實機觀感列入使用者目視驗收清單（design 中標明【需人工目視】）。
- [字型墨跡外框依賴系統字型版本] → 量測對 chevron（純路徑）與 `monospacedDigitSystemFont`（系統內建）皆不依賴使用者字型；容差 1 px 吸收抗鋸齒。
- [控制列左移後，使用者的肌肉記憶（右端）改變] → 這正是使用者要求；位置僅由 `ControlStripLayout` 決定，日後可再調。
- [`showLabel` 切換時控制列整體位移 150pt] → `StyleApplier` 同步更新 clip、scroll 原點與命中幾何；已排入訊息的 `tapeX` 不變，但可視寬度由 370 變 520，需沿用 style-settings 已有的 `reconfigure` 路徑。

## Migration Plan

純程式與文件變更，無資料遷移。回滾＝還原該分支的 commit。不 archive（由協調者驗證後處理）。

## Open Questions

- 齒輪槽寬度與位置（標籤左側）由下一個 change 決定。
- chevron 的尺寸（6×12、線寬 1.8）與停用淡化 0.3 為【假設】，待使用者目視。
