## ADDED Requirements

本 capability 為 B 段（由後續工程師實作）；A 段只提供它所依賴的型別與純邏輯（`HitTarget.gear`／`onGear`、`StyleMenuAction` 新動作、`StyleApplier`、`FeedClient.reconfigure`、`LaunchAtLoginService`／`LaunchAtLoginController`）。

### Requirement: 點齒輪彈出設定面板
點擊齒輪（`onGear`）SHALL 彈出一個設定面板（`SettingsPanel`，`NSPanel` 子類），再點齒輪 SHALL 關閉（切換）。面板 MUST 為非啟用面板：styleMask `[.borderless, .nonactivatingPanel]`、`canBecomeKey`／`canBecomeMain` 為 false、`hidesOnDeactivate` 為 false、不呼叫任何 App 啟用 API，level 高於跑馬燈一級、`collectionBehavior` 同跑馬燈（不得進入 `.fullScreenPrimary`）。開啟與關閉 MUST NOT 使本 App 成為前景、MUST NOT 取得鍵盤焦點、MUST NOT 改變跑馬燈面板的 frame／alpha／捲動。面板的位置 MUST 由純函式 `SettingsPanelPlacement.frame(panelSize:tickerFrame:screenVisibleFrame:gap:)` 決定：預設貼在跑馬燈下方（間距 6pt【假設】），水平與跑馬燈左緣對齊；下方空間不足時改放上方；水平方向 MUST 夾進螢幕 `visibleFrame` 內；上下皆放不下時 MUST 取空間較大者並夾制。

#### Scenario: 預設在下方
- **WHEN** 跑馬燈下方有足夠空間
- **THEN** 面板 SHALL 位於跑馬燈正下方、間距 6pt、左緣對齊跑馬燈左緣

#### Scenario: 下方不足改放上方
- **WHEN** 跑馬燈靠近螢幕下緣，下方空間小於面板高度加間距
- **THEN** 面板 SHALL 位於跑馬燈正上方

#### Scenario: 水平夾制
- **WHEN** 跑馬燈靠近螢幕右緣，面板右緣會超出 `visibleFrame`
- **THEN** 面板 SHALL 被水平移回 `visibleFrame` 內

#### Scenario: 不啟用 App
- **WHEN** 開啟與關閉面板
- **THEN** `canBecomeKey`／`canBecomeMain` SHALL 為 false、styleMask SHALL 含 `.nonactivatingPanel`，且 `Sources/` 中 SHALL 無新增的 `NSApp`／`NSApplication` 啟用呼叫

### Requirement: 面板內容與控制項
面板 SHALL 以下列順序顯示控制項【假設：分組與順序為設計選擇】，且 MUST 與選單列「樣式」子選單共用同一份 `StyleMenuModel` 的檔位、範圍與動作（`StyleRanges`、`StyleMenuModel.fontSizeSteps`／`replayCountSteps`／`LiveColorPreset.all`），不得另寫一套：(1) 字級（四檔分段控制）；(2) 捲動速度（滑桿 20–300）；(3) 圓角（滑桿 0–21）；(4) 重播訊息量（三檔 5／10／20）；(5) 即時配色（三組）；(6) 顯示時間（開關）；(7) 顯示標籤（開關）；(8) 切換後停留時間（滑桿 0.5–10 秒，步進 0.5）；(9) 輪詢間隔（三檔 10／30／60 秒）；(10) 開機自動啟動（開關＋狀態文字；需核准時提供「開啟系統設定」按鈕）；(11)「開啟樣式設定檔…」按鈕；(12)「重設為預設」按鈕；(13) 關閉鈕。選單列「樣式」子選單 MUST 保留且行為不變【假設】。面板內 MUST NOT 使用 `NSAlert` 或新對話框。每個控制項的目前值 MUST 反映生效樣式（面板開啟時，以及樣式因熱重載或選單操作改變時重新整理）。

#### Scenario: 控制項與樣式同步
- **WHEN** 樣式為預設，開啟面板
- **THEN** 各控制項 SHALL 顯示預設值（字級標準、速度 90、圓角 0、訊息量 10、白底黑字、顯示時間開、顯示標籤開、停留 1 秒、輪詢 10 秒）

#### Scenario: 熱重載後重新整理
- **WHEN** 面板開啟時 `style.json` 被改成 `fontSize: 20`
- **THEN** 字級控制項 SHALL 顯示「大」

#### Scenario: 共用同一份檔位
- **WHEN** 檢查面板的字級、訊息量、配色、停留、輪詢控制項的選項
- **THEN** SHALL 與 `StyleMenuModel`／`StyleRanges` 的值逐項相同

### Requirement: 操作立即生效並寫回
面板中的任何樣式控制項操作 MUST 立即生效並寫回 `style.json`：經 `StyleActionRunner.run` → `StyleStore.update`（夾制）→ `StyleApplier.apply`（與選單、熱重載同一條路徑）。滑桿連續拖動 MUST 即時套用並由 `StyleStore` 既有 debounce 寫回。「開啟樣式設定檔…」與「重設為預設」MUST 沿用 `StyleActionRunner` 的既有語意（開啟只呼叫注入的 `FileOpener`、重設前備份為 `.bak`）。開機自動啟動 MUST 經 `LaunchAtLoginController`，不經 `StyleStore`。

#### Scenario: 改字級
- **WHEN** 在面板選字級「大」
- **THEN** `fontSize` SHALL 為 20 並套用、寫回

#### Scenario: 改輪詢間隔
- **WHEN** 在面板選輪詢 30 秒
- **THEN** `pollIntervalSeconds` SHALL 為 30、`style.json` SHALL 更新，且 helper SHALL 以 `--interval-ms 30000` 重啟一次

#### Scenario: 改停留時間
- **WHEN** 將停留滑桿拖到 3
- **THEN** `seekHoldSeconds` SHALL 為 3，下一次成功切換 SHALL 停留 3 秒

#### Scenario: 開機自動啟動不寫樣式檔
- **WHEN** 切換開機自動啟動開關
- **THEN** `style.json` SHALL 不變，狀態文字 SHALL 反映 `LaunchAtLoginService.status`

### Requirement: 關閉規則與全域滑鼠監看
面板 MUST 在下列任一情況關閉：再次點擊齒輪、在面板與跑馬燈**以外**按下滑鼠（左鍵或右鍵）、點擊面板內關閉鈕。面板外偵測 MUST 使用 `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`，**只監看滑鼠按下事件，MUST NOT 需要輔助使用（Accessibility）權限、MUST NOT 監看鍵盤事件**；全域監看器 MUST 在面板開啟時安裝、關閉時移除（不得洩漏）。因全域監看器不會收到本 App 自己視窗內的事件，本 App 視窗內的點擊 MUST 由本地處理：面板內的點擊不得關閉面板；跑馬燈上按在齒輪者由 `onGear` 切換（不得被判為「面板外」而先關閉再重開）；跑馬燈上**齒輪以外**的按下（左鍵含導覽按鈕、迴紋針、拖曳；右鍵）【假設：B 段實作時依協調者指示補充，使面板不會在跑馬燈被拖走後留在原處】視為面板外而關閉，由 `TickerView.onTickerPointerDown` 回報，MUST NOT 阻擋既有導覽、連結與拖曳行為。判斷「是否在面板外」MUST 為純函式（輸入螢幕座標點、面板 frame、跑馬燈 frame；點落在跑馬燈矩形內者不算面板外，供全域事件落在跑馬燈矩形時使用，例如點穿模式）。

#### Scenario: 點面板外關閉
- **WHEN** 面板開啟時在其他 App 的視窗上按下滑鼠
- **THEN** 面板 SHALL 關閉並移除全域監看器

#### Scenario: 點面板內不關閉
- **WHEN** 在面板內任一控制項上按下滑鼠
- **THEN** 面板 SHALL 維持開啟

#### Scenario: 點齒輪切換
- **WHEN** 面板開啟時點齒輪
- **THEN** 面板 SHALL 關閉（不得先被「面板外」邏輯關閉再被齒輪重新開啟）

#### Scenario: 點跑馬燈非齒輪處關閉
- **WHEN** 面板開啟時在跑馬燈的 `>` 按鈕、訊息或標籤上按下左鍵（或按右鍵）
- **THEN** 面板 SHALL 關閉並移除全域監看器，且該次點擊原本的行為（導覽、拖曳、選單）SHALL 照常進行

#### Scenario: 不需要輔助使用權限
- **WHEN** 檢查監看器遮罩
- **THEN** SHALL 僅含 `.leftMouseDown`、`.rightMouseDown`，`Sources/` 中 SHALL 無 `AXIsProcessTrusted`、`CGEventTap` 或鍵盤事件遮罩的全域監看

### Requirement: 非啟用面板上的互動風險與驗收
`NSSlider`、`NSSegmentedControl`、`NSSwitch` 等控制項在非啟用 `NSPanel`（`canBecomeKey = false`）上能否「第一次點擊就生效、滑桿可拖動、不啟用本 App」屬平台行為【假設】，無法由自動測試證明。B 段 MUST 在實機驗收並如實回報：(1) 每種控制項第一次點擊即生效；(2) 滑桿可連續拖動且跑馬燈即時反應；(3) 操作期間 `frontmostApplication` 不變；(4) 在另一 App 持續打字時操作面板，打字不中斷。若 (1)–(3) 任一不成立，退路為：先改用步進按鈕（−／＋）取代滑桿；仍不行再讓面板可成為 key 但不啟用 App（`becomesKeyOnlyIfNeeded`），並更新本 requirement 與 design.md 的決定 10。自動測試 MUST NOT 開真實視窗（不呼叫 `orderFront`／`makeKeyAndOrderFront`）、MUST NOT 寫使用者真實的 `style.json`、MUST NOT 真的註冊登入項目。

#### Scenario: 人工驗收清單
- **WHEN** 在實機操作每一種控制項
- **THEN** 驗收紀錄 SHALL 逐項寫明結果（生效／不生效），不得以「應該可以」代替（需人工驗收）

#### Scenario: 自動測試無視窗
- **WHEN** 執行 B 段新增的全部測試
- **THEN** 過程 SHALL 不顯示任何視窗、不改變 frontmost 應用程式
