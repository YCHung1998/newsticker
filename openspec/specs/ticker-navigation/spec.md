# ticker-navigation Specification

## Purpose
TBD - created by archiving change ticker-navigation-link. Update Purpose after archive.
## Requirements
### Requirement: 位置指示 (n/N) 的內容
帶子 SHALL 顯示位置指示，格式固定為半形括號、半形斜線、十進位整數且無前導零與空白：`(n/N)`，例如 `(3/10)`。`n` 與 `N` 取自 Core 的 `ReadingPosition`（見 `ticker-scheduler` 的「閱讀位置查詢」）：`n` 為目前「閱讀中那一則」在其清單內的序號，`N` 為該清單的目前總數。重播時清單為最新 N 則（N 為重播則數，預設 10；歷史不足時為實際則數；重播則數之後由 change `ticker-style-settings` 決定），即時時清單為當前即時批次（總數隨 LIVE 追加而增加）。閱讀位置為 `nil`（空帶子等）時 MUST 不顯示指示文字（不顯示 `(0/0)`）。「閱讀中那一則」以靠近標籤右側（視窗左緣內縮 `readingInset`）的那一則為準【假設，見 design.md】。格式化為純函式，MUST 有單元測試。

#### Scenario: 重播時顯示
- **WHEN** 重播清單的第 3 則為閱讀中，重播則數為 10
- **THEN** 指示文字 SHALL 為 `(3/10)`

#### Scenario: 即時批次顯示
- **WHEN** 即時批次共 3 則，第 2 則為閱讀中
- **THEN** 指示文字 SHALL 為 `(2/3)`

#### Scenario: 即時批次增長
- **WHEN** 第 2 則為閱讀中時又收到一則 `items` 進入同一批次
- **THEN** 指示文字 SHALL 變為 `(2/4)`

#### Scenario: 無閱讀中那一則
- **WHEN** 帶子為空或閱讀位置為 `nil`
- **THEN** 指示文字 SHALL 為空（不顯示）

#### Scenario: 兩位數與邊界格式
- **WHEN** `n` 為 10、`N` 為 10；或 `n` 為 1、`N` 為 1
- **THEN** 指示文字 SHALL 分別為 `(10/10)` 與 `(1/1)`

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

### Requirement: 前後切換按鈕
點擊 `<` SHALL 呼叫 Core 的 `seek(.previous)`，點擊 `>` SHALL 呼叫 `seek(.next)`；成功時 App MUST 對新的 `scrollOffset` 做渲染同步，並為對齊後落在視窗範圍內、但圖層已被裁剪（prune）的已排入訊息重新建立圖層（`TickerRenderer.add` 對同一 `seq` MUST 冪等）。按鈕動作 MUST 在滑鼠放開（mouse-up）時觸發，且放開位置仍須在同一按鈕範圍內；按住後移出範圍再放開 MUST 不觸發【假設：以 mouse-up 觸發；若在非啟用面板上 mouse-up 實測不可靠，改為 mouse-down，見 design.md 待確認】。只回應滑鼠左鍵。`<` 在無法前移時（`atListStart`、`previousNotRetained`、`noReadingItem`、`hidden`）SHALL 以淡化外觀表示停用，點擊 MUST 無任何狀態變化；`>` 僅在 `noReadingItem`／`noMaterial`／`hidden` 時停用。

#### Scenario: 點 > 前進
- **WHEN** 重播清單第 5 則為閱讀中，在 `>` 範圍內按下並放開左鍵
- **THEN** 排程器 SHALL 收到一次 `seek(.next)`，指示 SHALL 變為 `(6/10)`，且第 6 則 SHALL 位於視窗左緣

#### Scenario: 點 < 後退到已被裁剪圖層的訊息
- **WHEN** 第 4 則的圖層因捲出左緣已被移除，閱讀中為第 5 則，點擊 `<`
- **THEN** 渲染端 SHALL 重新建立第 4 則的圖層並顯示於視窗左緣

#### Scenario: 第一則的 < 為停用
- **WHEN** 閱讀中為清單第 1 則，點擊 `<`
- **THEN** 排程器 SHALL 回傳 `atListStart`，位置、保持計時 SHALL 不變，按鈕 SHALL 為淡化外觀

#### Scenario: 移出後放開不觸發
- **WHEN** 在 `>` 上按下左鍵、移到按鈕範圍外再放開
- **THEN** SHALL 不呼叫 `seek`

#### Scenario: 右鍵不觸發
- **WHEN** 在 `>` 上按右鍵
- **THEN** SHALL 不呼叫 `seek`，而是彈出與選單列相同的選單（沿用 app-shell 的右鍵後備入口）

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

### Requirement: 邊界行為
下列邊界 MUST 明確且可測：(1) 清單第一則（重播最新一則，或即時批次第一則）按 `<`：無動作（不跳到上一個清單，也不重設暫停）【假設】；(2) 清單最後一則按 `>`：跳到「下一輪起點」——重播清單最後一則按 `>` 對齊到下一輪的最新一則；即時批次最後一則按 `>`：若即時佇列仍有訊息則為其下一則，否則為重播最新一則；此行為由 Core 的「強制排入下一則」實現【假設】；(3) 帶子上沒有閱讀中那一則（空帶子、尚未收到 snapshot）：兩個按鈕皆無動作；(4) 隱藏中：兩個按鈕皆無動作（面板不可見，僅防禦）；(5) 歷史為空且無即時訊息時按 `>`：無動作（`noMaterial`）。

#### Scenario: 第一則按 <
- **WHEN** 重播清單第 1 則為閱讀中，按 `<`
- **THEN** 無任何位置變化，指示 SHALL 仍為 `(1/10)`

#### Scenario: 最後一則按 >
- **WHEN** 重播清單第 10 則為閱讀中，按 `>`
- **THEN** 指示 SHALL 變為 `(1/10)` 且閱讀中為下一輪的最新一則

#### Scenario: 空帶子
- **WHEN** 尚未收到 snapshot 時按 `<` 或 `>`
- **THEN** SHALL 無動作且不當機

### Requirement: 滑鼠停在帶子上時暫停捲動
滑鼠指標位於面板範圍內時，自動捲動 MUST 暫停（Core 的 `setPointerInside(true)`），移出後從原位置接著捲動，使使用者能點擊移動中的迴紋針與按鈕【假設：整個面板範圍皆暫停，立即恢復，無延遲；永久停在帶子上會使帶子不動，見 design.md 待確認】。進出偵測以 `NSTrackingArea`（`.activeAlways`、`.mouseEnteredAndExited`，不需要 App 啟用）為主；為避免 mouse-exited 事件遺失（拖曳視窗、切換 Space、隱藏／顯示）造成永久凍結，補料計時器每次觸發 MUST 以 `NSEvent.mouseLocation` 與面板 frame 重新核對（純函式 `PointerHover.isInside`），不一致時以核對結果為準。隱藏面板時 MUST 視為指標在外。點穿模式（`ignoresMouseEvents = true`）下不暫停。核對僅使用 `NSEvent.mouseLocation`，不需要輔助使用或螢幕錄製權限。

#### Scenario: 進入暫停離開恢復
- **WHEN** 指標進入面板後 10 秒再離開（假時鐘）
- **THEN** 進入期間 `scrollOffset` SHALL 不變；離開後 SHALL 從原位置接著走、無跳動

#### Scenario: 離開事件遺失
- **WHEN** 指標已實際位於面板外，但 mouse-exited 事件未送達
- **THEN** 下一次補料計時器觸發時 SHALL 以 `PointerHover.isInside` 的結果解除凍結

#### Scenario: 隱藏時視為在外
- **WHEN** 指標在面板上時使用者隱藏面板
- **THEN** 指標停留凍結 SHALL 解除（隱藏本身仍凍結 tape 時間）

#### Scenario: 點穿模式
- **WHEN** 點穿模式開啟
- **THEN** 指標進入 SHALL 不造成暫停，按鈕與迴紋針 SHALL 不可點擊

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

### Requirement: 切換操作不啟用 App、不搶鍵盤焦點
點擊 `<`／`>`、拖曳、滑鼠進出面板 MUST NOT 使本 App 成為前景或取得鍵盤焦點：程式 MUST NOT 呼叫 `NSApp.activate` 或 `NSApplication.activate(ignoringOtherApps:)`，面板維持 `canBecomeKey = false`／`canBecomeMain = false` 與 `.nonactivatingPanel`。tracking area MUST 使用 `.activeAlways`，不得依賴 App 啟用。此限制沿用 app-shell 的 `panel-shell`「Accessory App 且永不啟用」。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/` 執行 `grep -rn "activate(" Sources/`
- **THEN** SHALL 無對 `NSApp`／`NSApplication` 的啟用呼叫

#### Scenario: 操作期間 frontmost 不變
- **WHEN** 使用者在另一 App 持續打字，同時點擊 `<`／`>`、滑鼠進出面板
- **THEN** `frontmostApplication` SHALL 不變、鍵盤輸入 SHALL 不中斷、本 App 的啟用通知 SHALL 為零（需人工驗收）

### Requirement: 測試策略與禁止項目
命中測試、`(n/N)` 格式化、`PointerHover.isInside`、控制列版面計算 MUST 為純函式並以單元測試驗證；seek／保持／凍結以 Core 的假時鐘測試。自動測試 MUST NOT 開啟真實視窗、MUST NOT 呼叫 `orderFront` 或 `makeKeyAndOrderFront`、MUST NOT 連到正式網站、MUST NOT 啟動真實瀏覽器。視圖的滑鼠處理 MUST 拆為可直接呼叫的方法（輸入座標與事件種類，輸出動作）供測試使用，不得要求合成真實 `NSEvent` 才能測。箭頭與位置指示的外觀、點擊手感為【需人工目視】，tasks 必須逐項標明。

#### Scenario: 無真實視窗
- **WHEN** 執行本 change 新增的所有 App 層測試
- **THEN** 測試過程 SHALL 不顯示任何視窗，也 SHALL 不改變 frontmost 應用程式

