## ADDED Requirements

### Requirement: 齒輪槽的位置與面板寬度推導
面板由左至右的區域 SHALL 為：齒輪槽（固定寬度 `gearSlotWidth`，暫定 28pt【假設】）、紅色標籤（`showLabel` 為 true 時，150pt）、控制列（100pt）、訊息帶子。齒輪槽 MUST 永遠存在於面板最左側，不受 `showLabel` 影響。面板寬度 MUST 由各段寬度推導，而非寫死：`panelWidth = gearSlotWidth + labelWidth + controlStripWidth + tapeViewport`，其中 `tapeViewport` 的設計值為使用者已確認的 370pt，故預設面板尺寸為 648×42（28 + 150 + 100 + 370）。所有控制列與帶子的座標 MUST 由單一偏移 `leftInset = gearSlotWidth + (showLabel ? labelWidth : 0)` 推導；控制列內部三個區段的相對版面與 `ControlStripLayout` 的範圍函式 MUST 不因加入齒輪槽而改變。`showLabel` 為 false 時，齒輪槽仍在最左，控制列緊接其後（`leftInset = gearSlotWidth`），帶子可視寬度為 `panelWidth − gearSlotWidth − controlStripWidth`（預設 520）。標籤圖層 MUST 向右位移 `gearSlotWidth`；齒輪槽有自己的純色底，與控制列同色，標籤斜切邊下方的控制列底延伸規則不變。排程器的 `viewportWidth` MUST 以同一公式計算（預設 370，標籤隱藏 520）。

#### Scenario: 預設版面
- **WHEN** 使用預設 `ShellConfig` 與預設樣式
- **THEN** 面板寬 SHALL 為 648；齒輪槽 SHALL 為 x ∈ [0, 28)，標籤 [28, 178)，控制列 [178, 278)（`<` [178, 202)、指示 [202, 254)、`>` [254, 278)），帶子可視區 [278, 648)，排程器 `viewportWidth` SHALL 為 370

#### Scenario: 標籤隱藏
- **WHEN** `showLabel` 為 false
- **THEN** 齒輪槽 SHALL 仍為 [0, 28)，控制列 SHALL 佔 [28, 128)，帶子可視區 SHALL 為 [128, 648)，`viewportWidth` SHALL 為 520，帶子座標 0 SHALL 對應面板 x = 128

#### Scenario: 面板寬度由推導得出
- **WHEN** 改變 `gearSlotWidth` 為 G'（其餘不變）並重新推導面板寬
- **THEN** 面板寬 SHALL 為 `G' + 150 + 100 + 370`，且帶子可視寬度 SHALL 仍為 370

#### Scenario: 單一偏移
- **WHEN** 對任一 `leftInset`，呼叫 `ControlStripLayout` 的範圍函式
- **THEN** 各範圍 SHALL 只是 `leftInset` 的平移，寬度不變（沿用 `gearSlotCanBeInsertedByShiftingTheSingleOffset` 的性質）

### Requirement: 齒輪圖示與 hover
齒輪 MUST 以路徑自繪（`CAShapeLayer`，`fillRule = evenOdd`）【假設：不使用 SF Symbol，見 design.md 決定 3】：8 齒、外徑 16pt、齒根徑 12.4pt、中心孔徑 5.6pt【假設】，其墨跡外框的中心 MUST 落在齒輪槽的幾何中心（水平 ± 1 device px、垂直 ± 1 device px，@2x 離屏渲染以像素量測）。顏色為白色；閒置不透明度 0.75、指標在齒輪槽內（hover）時 1.0【假設】。hover 狀態 MUST 由純函式依指標座標與幾何判定（與命中測試同源），指標離開面板時 MUST 復原。圓角 `cornerRadius` 為合法範圍內任意值（上限 21pt）時，齒輪 MUST 完整可見（齒輪外半徑 8pt 加上中心偏離圓角圓心的 7pt 小於 21pt，故不被圓角裁切；以離屏渲染比較圓角 0 與 21 的墨跡像素數相等來驗證）。齒輪外觀（尺寸、齒形、hover 手感）為【需人工目視】。

#### Scenario: 齒輪置中於槽
- **WHEN** 離屏渲染（不開視窗）預設版面
- **THEN** 齒輪墨跡外框的水平與垂直中心 SHALL 與槽中心 (14, 21) 相差 ≤ 1 device px（@2x）

#### Scenario: 與標籤和控制列的垂直對齊
- **WHEN** 離屏渲染預設版面，量測齒輪、`<`、`>` 的墨跡外框
- **THEN** 三者垂直中心兩兩相差 SHALL ≤ 1 device px

#### Scenario: hover 高亮
- **WHEN** 指標移到齒輪槽內，再移到訊息帶子上
- **THEN** 齒輪不透明度 SHALL 先為 1.0 再回到 0.75；指標離開面板 SHALL 回到 0.75

#### Scenario: 最大圓角不裁切齒輪
- **WHEN** `cornerRadius` 為 21 離屏渲染
- **THEN** 齒輪墨跡像素數 SHALL 與圓角 0 時相同

#### Scenario: 標籤隱藏仍在最左
- **WHEN** `showLabel` 為 false 離屏渲染
- **THEN** 齒輪墨跡外框 SHALL 位於 x < 28，且控制列 `<` 墨跡位於 x ≥ 28

### Requirement: 齒輪命中與觸發
命中測試 MUST 新增目標 `.gear`：點在齒輪槽範圍 `[0, gearSlotWidth)`（半開區間，高度為整條）內時結果為 `.gear`。判定優先序為：齒輪／控制列按鈕／迴紋針 > 拖曳（`.gear` 與按鈕範圍互不重疊；被齒輪槽、標籤或控制列遮住的迴紋針命中區 MUST 不是 `.link`）。`NavigationInputRouter` MUST 提供 `onGear` 回呼：mouse-up 時才觸發（沿用導覽按鈕規則）、放開位置須仍在齒輪範圍內、只回應左鍵、點穿模式（`isEnabled == false`）忽略；按下在齒輪上 MUST NOT 呼叫 `performDrag`。右鍵在齒輪上 SHALL 照舊彈出選單列的選單。觸發後做什麼（開啟設定面板）由 `settings-panel` 規範；本 requirement 只規範命中與回呼。

#### Scenario: 齒輪槽內命中
- **WHEN** 預設版面下點在 x = 0、14、27.9
- **THEN** 結果 SHALL 為 `.gear`；x = 28 SHALL 為 `.drag`（標籤）

#### Scenario: mouse-up 才觸發
- **WHEN** 在齒輪上按下左鍵
- **THEN** `onGear` SHALL 尚未被呼叫、`performDrag` SHALL 未被呼叫；放開後 `onGear` SHALL 恰被呼叫一次

#### Scenario: 移出後放開不觸發
- **WHEN** 在齒輪上按下、移到標籤上放開
- **THEN** `onGear` SHALL 不被呼叫

#### Scenario: 右鍵與點穿
- **WHEN** 在齒輪上按右鍵，或點穿模式下點齒輪
- **THEN** `onGear` SHALL 不被呼叫

#### Scenario: 標籤隱藏時的命中
- **WHEN** `showLabel` 為 false，點在 x = 10、40、100
- **THEN** 結果 SHALL 依序為 `.gear`、`.previousButton`、`.drag`（位置指示 [52, 104) 中 x=100 屬指示）

### Requirement: 齒輪操作不啟用 App、不搶鍵盤焦點
點擊齒輪與 hover MUST NOT 使本 App 成為前景或取得鍵盤焦點：程式 MUST NOT 呼叫 `NSApp.activate` 或 `NSApplication.activate(ignoringOtherApps:)`；追蹤區 MUST 使用 `.activeAlways`。此限制沿用 `ticker-navigation` 的「切換操作不啟用 App、不搶鍵盤焦點」。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/` 執行 `grep -rn "activate(" Sources/`
- **THEN** SHALL 無新增的 `NSApp`／`NSApplication` 啟用呼叫（唯一例外維持 `SingleInstanceGuard.swift` 的重複實例對話框）

#### Scenario: 操作期間 frontmost 不變
- **WHEN** 使用者在另一 App 持續打字，同時 hover、點擊齒輪
- **THEN** `frontmostApplication` SHALL 不變、鍵盤輸入 SHALL 不中斷（需人工驗收）
