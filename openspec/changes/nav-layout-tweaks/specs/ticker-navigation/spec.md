## MODIFIED Requirements

### Requirement: 控制列的位置與版面
App SHALL 在標籤右側、訊息帶子左側顯示固定寬度的控制列，面板由左至右的區域為：〔（預留）齒輪槽〕、紅色標籤（`showLabel` 為 true 時）、控制列、訊息帶子。控制列內由左至右為：`<` 按鈕、位置指示、`>` 按鈕。控制列寬度 `controlStripWidth` 暫定 100pt（按鈕各 24pt、指示 52pt）【假設】，面板整體尺寸維持 620×42。控制列左緣 `stripLeft` 為「標籤右緣」：`showLabel` 為 true 時等於標籤寬度（預設 150pt），為 false 時為 0（控制列貼面板左緣）；訊息帶子可視區為 `[stripLeft + controlStripWidth, 面板右緣)`，因此帶子可視寬度（`SchedulerConfig.viewportWidth`）MUST 由「面板寬度 − 標籤寬度（`showLabel` 為 false 時視為 0）− 控制列寬度」計算（預設 620 − 150 − 100 = 370；標籤隱藏時 520），且帶子內容 MUST 被裁切在可視區之內（訊息不得蓋住控制列或標籤）。帶子座標 0（Core 的視窗左緣，`seek` 的對齊位置與 `readingInset` 的參考線）對應面板座標 `stripLeft + controlStripWidth`，即控制列右緣。控制列背景為純色，且 MUST 延伸到標籤斜切邊的下方（不得在標籤與控制列之間露出帶子底色的三角縫隙）；文字與箭頭顏色與控制列底色形成可讀對比，不隨訊息的 `live`／`replay` 樣式改變【假設】。

`<`、`(n/N)`、`>` 三者 MUST 垂直對齊：離屏渲染（不開視窗）控制列後，以像素「墨跡外框」（與控制列底色的色差超過門檻的像素之最小外接矩形；`(n/N)` 以括號與數字整體計）量測，三者垂直中心兩兩相差 MUST ≤ 1 device px（@2x），且各自相對控制列高度的垂直中心偏差 MUST ≤ 1 device px；此標準對 `showLabel` 為 true／false、任意圓角、及位置指示為 `(1/1)`、`(10/10)`、`(2/30)` 等文字皆成立。實作方式【假設】：`<`、`>` 以路徑自繪 chevron（不經字型度量）、`(n/N)` 以半形 ASCII 的等寬數字字型繪成位圖並依墨跡外框置中，詳見 design.md。字級、箭頭形狀、停用時的淡化等視覺細節仍屬【需人工目視】。與 app-shell 的 `ticker-renderer`（每則訊息預渲染為 bitmap）及面板尺寸設定相關：控制列以獨立圖層繪製，不進入訊息 bitmap。

版面 MUST 不阻擋日後在標籤左側插入固定寬度的齒輪槽：所有控制列與帶子的座標 MUST 由「控制列左緣 `stripLeft`」這個單一偏移推導（`stripLeft = 齒輪槽寬 + 標籤寬`），而不是各自假設 0 或面板右緣；本 change 不實作齒輪槽（其寬度視為 0），也不繪製任何東西。

#### Scenario: 可視寬度計算
- **WHEN** 面板寬 620、標籤寬 150、控制列寬 100
- **THEN** 排程器的 `viewportWidth` SHALL 為 370

#### Scenario: 控制列在標籤右側
- **WHEN** 面板寬 620、標籤寬 150、`showLabel` 為 true
- **THEN** 控制列 SHALL 佔面板 x ∈ [150, 250)，其中 `<` 為 [150, 174)、指示為 [174, 226)、`>` 為 [226, 250)；帶子可視區 SHALL 為 [250, 620)

#### Scenario: 標籤隱藏時控制列貼左
- **WHEN** `showLabel` 為 false
- **THEN** 控制列 SHALL 佔 x ∈ [0, 100)，帶子可視區 SHALL 為 [100, 620)，`viewportWidth` SHALL 為 520，帶子座標 0 SHALL 對應面板 x = 100

#### Scenario: 三個符號垂直對齊
- **WHEN** 離屏渲染控制列（位置指示為 `(4/10)`、兩個按鈕皆啟用），以墨跡外框量測
- **THEN** `<`、`(n/N)`、`>` 的垂直中心兩兩相差 SHALL ≤ 1 device px，且各自與控制列高度中心相差 SHALL ≤ 1 device px

#### Scenario: 預留齒輪槽
- **WHEN** 假設在標籤左側插入寬度 G 的齒輪槽（G 以 `stripLeft` 偏移表示）
- **THEN** 控制列範圍與可視寬度公式 SHALL 只需把 `stripLeft` 加上 G，無須修改控制列內部三個區段的相對版面（以 `ControlStripLayout` 的純函式測試驗證）

#### Scenario: 訊息不蓋住控制列
- **WHEN** 一則訊息捲到控制列所在位置
- **THEN** 該訊息在控制列範圍內 SHALL 不可見（被裁切），控制列文字與按鈕 SHALL 仍清楚可見（需人工目視）

#### Scenario: 控制列不隨樣式變色
- **WHEN** 閱讀中那一則由 `replay` 變為 `live`
- **THEN** 控制列背景 SHALL 不變

### Requirement: 切換後暫停自動捲動並恢復
成功的切換 SHALL 讓自動捲動暫停 `seekHoldSeconds`（預設 1 秒【假設，使用者回饋第二輪】），暫停期間目標訊息固定在視窗左緣；期滿 MUST 從該位置接著捲動、無跳動。暫停期間再次成功切換 MUST 重設為完整的 `seekHoldSeconds`（不累加）。暫停計時使用 Core 的注入時鐘，MUST NOT 另起 App 層計時器。暫停期間補料 MUST 照常進行，帶子右側不得出現空白。

#### Scenario: 1 秒後恢復
- **WHEN** 切換成功後 1 秒內無任何操作（預設 `seekHoldSeconds` = 1）
- **THEN** 這段時間內目標 SHALL 固定在視窗左緣；第 1 秒後帶子 SHALL 恢復向左捲動（以假時鐘驗證）

#### Scenario: 連續點擊
- **WHEN** 切換成功後第 0.6 秒再按一次 `>`
- **THEN** 新的暫停 SHALL 重新計 1 秒（不累加為 1.4 秒）

#### Scenario: 暫停中不空白
- **WHEN** 暫停期間
- **THEN** 視窗右緣 SHALL 持續有訊息（由 Core 補料保證），不出現空白

### Requirement: 命中測試與拖曳區分
命中測試 MUST 為純函式：輸入為面板座標系的點、面板尺寸、標籤寬度、控制列版面（範圍由標籤寬度推導，位於標籤右側）、目前可見訊息的（`seq`、視覺左緣、`width`、`hasLinkSlot`）清單與 `linkSlotWidth`，輸出 `HitTarget`：`.previousButton`、`.nextButton`、`.link(seq)`、`.drag`。判定優先序：控制列的 `<`／`>` 按鈕範圍優先；其次迴紋針命中區（訊息的 `[width − linkSlotWidth, width)`，每側外擴 `hitSlop` 暫定 4pt【假設】，高度為整條帶子高度，且僅在位於可見帶子範圍內〔控制列右緣與面板右緣之間，即 `[標籤寬 + 控制列寬, 面板寬)`〕時有效；訊息視覺左緣為 `visualLeft` 者，其連結欄位右緣的面板座標為「標籤寬 + 控制列寬 + visualLeft + width」）；其餘全部為 `.drag`（含標籤、位置指示、訊息文字、空白處）。按在 `.drag` 上 MUST 呼叫 `performDrag(with:)`（沿用 app-shell 的拖曳實作，與 app-shell 的 `panel-shell`「拖曳以 performDrag 實作」相關：該 requirement 的「點擊帶子 MUST 等同拖曳」自此改為「除按鈕與迴紋針命中區外」）；按在按鈕或迴紋針上 MUST NOT 呼叫 `performDrag`。mouse-down 後超過系統拖曳門檻才移動的行為，在按鈕與迴紋針上 MUST 視為取消（不觸發動作、不移動視窗）【假設】。

#### Scenario: 控制列在標籤右側的命中
- **WHEN** 面板寬 620、標籤寬 150 時點在 x = 160、x = 200、x = 240、x = 600
- **THEN** 結果 SHALL 依序為 `.previousButton`、`.drag`（位置指示）、`.nextButton`、`.drag`（無迴紋針的帶子）；`showLabel` 為 false（標籤寬 0）時 x = 10、50、90 SHALL 依序為 `.previousButton`、`.drag`、`.nextButton`

#### Scenario: 按鈕優先
- **WHEN** 點在 `>` 按鈕範圍內，且該處下方恰有迴紋針
- **THEN** 命中結果 SHALL 為 `.nextButton`

#### Scenario: 迴紋針命中
- **WHEN** 點在某含 `url` 的訊息的連結欄位內（含 `hitSlop` 外擴範圍）
- **THEN** 結果 SHALL 為 `.link(該訊息的 seq)`

#### Scenario: 無連結的訊息
- **WHEN** 點在不含 `url` 的訊息最右側
- **THEN** 結果 SHALL 為 `.drag`

#### Scenario: 被控制列或標籤遮住的迴紋針
- **WHEN** 含 `url` 的訊息的連結欄位位置落在標籤區或控制列區內
- **THEN** 結果 SHALL 不是 `.link`（而是 `.drag` 或按鈕）；標籤寬 150、控制列寬 100 時，面板 x < 250 的任何點 SHALL 不是 `.link`

#### Scenario: 其餘為拖曳
- **WHEN** 點在標籤、位置指示、訊息文字或空白處
- **THEN** 結果 SHALL 為 `.drag`，視圖 SHALL 呼叫 `performDrag(with:)`
