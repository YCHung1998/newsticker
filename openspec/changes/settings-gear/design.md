## Context

現況（`main`，已含 `nav-layout-tweaks`）：面板 620×42，由左至右 標籤 `[0,150)`、控制列 `[150,250)`、帶子可視區 `[250,620)`（370）。`ControlStripLayout` 的所有範圍函式吃一個 `leftInset`（控制列左側已被占用的寬度），`HitGeometry.labelWidth` 即此值；`gearSlotCanBeInsertedByShiftingTheSingleOffset` 測試已證明「只要把 `leftInset` 加上槽寬」即可。`TickerStyle`、`StyleStore`、`StyleMenuModel`、Core `reconfigure` 存在於程式，但其 specs 還在進行中的 change `ticker-style-settings`（尚未同步到主 specs）。helper 已支援 `--interval-ms N`（`ticker-connect/src/main.rs`）。Core 對「中途 snapshot」的現行行為（`TickerScheduler.receive(.snapshot)`）：只取代歷史、設 `hasBaseline`，不碰即時佇列、帶子、模式。

使用者已授權「剩下要做的一併做完」，並指定排列〔齒輪〕→ 紅色標籤 → 控制列 → 訊息帶子，設定項目採協調者先前建議全部保留。以下凡替使用者做的選擇皆標【假設】。

## Goals / Non-Goals

**Goals**
- 齒輪槽落在最左，面板寬度由各段寬度推導，帶子可視寬度維持 370。
- 三個新設定可用：切換停留時間、輪詢間隔（重啟 helper）、開機自動啟動（如實顯示平台狀態）。
- 設定面板與選單列「樣式」子選單共用同一份資料模型與動作。

**Non-Goals**
- 不改協議、不改 Rust helper、不提供 5 秒輪詢（未實測，`fastbull-connector` 已規定在實測前不得宣稱）。
- 不改 `ticker-style-settings`、`app-shell`、`single-instance-guard` 的 artifacts。
- 不做自動更新、不做設定匯入匯出。
- 本 change 的 A 段不實作設定面板視窗（B 段）。

## Decisions

1. **齒輪槽寬 28pt【假設】，面板寬度推導為 648pt**。`panelWidth = gearSlotWidth + labelWidth + controlStripWidth + tapeViewport`，`tapeViewport` 的設計值 370 是使用者已確認的可視寬度。`ShellConfig.provisional` 以靜態函式 `ShellConfig.panelWidth(gearSlotWidth:labelWidth:strip:tapeViewport:)` 計算 `panelSize.width`，不再寫死 620。`panelSize` 仍是 `ShellConfig` 的欄位（使用者可手動編輯其值）；若使用者手動改成別的值，`tapeViewport` 由「面板寬 − 槽 − 標籤 − 控制列」推導，行為與先前一致。替代方案「面板維持 620、帶子縮為 342」被否決：使用者在 `nav-layout-tweaks` 已確認 370。28pt 是為讓 16pt 的齒輪圖示左右各留 6pt、點擊目標寬 28 與按鈕高 42 相稱；也可用 24（與按鈕同寬），選 28 是多留一點給觸控式的準星誤差【假設，待使用者目視】。
2. **單一偏移不變**：`leftInset = gearSlotWidth + (showLabel ? labelWidth : 0)`，`ControlStripLayout` 範圍函式不改一行；`HitGeometry` 新增 `gearSlotWidth`（預設 0，使既有直接建構 `HitGeometry` 的測試不受影響），內部 `inset = gearSlotWidth + labelWidth`。`TickerView` 標籤圖層 x 位移 `gearSlotWidth`；控制列底延伸到標籤斜切下方的規則不變（起點為 `leftInset − slant`）。齒輪槽有自己的純色底（與控制列同色 `gray 0.15`【假設】），`showLabel=false` 時與控制列相連成一整塊。
3. **齒輪圖示：自繪 `CAShapeLayer` 路徑，不用 SF Symbol `gearshape`【假設】**。理由：(a) 與 `<`／`>` 一致，可用像素墨跡外框量測置中，不依賴字型／符號的內部留白；(b) 不依賴系統符號版本與渲染模式（離屏渲染 `CALayer.render` 對 `NSImage` symbol 的 tint 行為不穩）；(c) hover 高亮只改 `opacity`。外形：8 齒、外徑 16pt、齒根徑 12.4pt、中心孔徑 5.6pt，`fillRule = .evenOdd`；閒置不透明度 0.75、hover 1.0【假設】。hover 偵測用 `NSTrackingArea` 的 `.mouseMoved`（`.activeAlways`、`.inVisibleRect`），判斷為純函式 `HitTesting.target(at:)` 是否為 `.gear`。
4. **命中 `.gear`**：優先序 齒輪／按鈕／迴紋針 > 拖曳；齒輪範圍 `[0, gearSlotWidth)`（半開），高度為整條。`NavigationInputRouter` 新增 `onGear`，mouse-up 觸發規則與按鈕相同（按下與放開都在齒輪範圍、只回應左鍵、點穿模式忽略）。不開視窗的行為（開面板）屬 B 段。
5. **`TickerStyle` 新欄位**（寫進 `style.json`，缺鍵取預設，使不改設定時行為不變）：
   - `seekHoldSeconds`：Double，預設 1.0（現行值），範圍 0.5–10【假設】。下限 0.5 避免與「幾乎沒停」無差別；0 在 Core 仍合法（表示不保持），但設定面板不提供，故檔案中的 0 會被夾制到 0.5（使用者若真要 0 須改程式；此為取捨，因為「0＝關閉停留」不屬使用者要求）。上限 10 約為舊預設 8 秒再多一點。
   - `pollIntervalSeconds`：Int，檔位 `[10, 30, 60]`，預設 10【假設】。不在檔位的值**夾制到最近檔位**（平手取較大者＝較少請求），例如 5→10、20→30、45→60、1000→60，並產生 `clamped` 警告；非整數或非數字視為型別錯誤取預設。5 秒未實測，不提供。
   - 兩者的檔位／範圍集中在 `StyleRanges`，面板控制項與解析共用同一份。
6. **停留時間經 Core `reconfigure` 生效（最小擴充）**：`SchedulerTunables` 增第七欄位 `seekHoldSeconds`，`init(config:)` 帶入現值，主初始化器新增必填參數（唯一呼叫端是 `StyleApplier`）；`reconfigure` 只更新 `config.seekHoldSeconds`，**不動 `holdRemaining`**（進行中的停留依舊期滿，下一次 seek 才用新值），其餘不變量不動。`reconfigure` 前置條件新增 `seekHoldSeconds >= 0`。既有測試 `tunablesExposeExactlySixFields` 的斷言清單增一項（改名為 `...SevenFields`，不刪斷言）。
7. **輪詢間隔變更＝計畫性重啟 helper**：`FeedClient` 新增 `reconfigure(arguments:)`。
   - `running`：記下新參數與「待重啟」旗標，走與 `shutdown` 相同的優雅結束（關 stdin → `terminateTimeout` 後 SIGTERM → 再逾時 SIGKILL）；該 generation 結束時**不進退避、不重置也不累計退避狀態**，立即以新參數 `launch()`；對外發 `.exited(generation, status, restartIn: 0)` 後接 `.started`（不新增事件型別，`AppCoordinator` 日誌顯示 `restartIn=0.0`）。重啟進行中再次呼叫只更新參數（合併）。
   - `backingOff`／`idle`／`failed`／`stopped`：只更新參數，下一次 `launch` 用新參數；`stopping` 時忽略。參數相同為 no-op。
   - 參數產生：`FeedClientConfig.helperArguments(pollIntervalSeconds:)`——10 秒（預設）回傳 `[]`（與現況命令列完全一致），其他回傳 `["--interval-ms", "<秒×1000>"]`。
   - 套用路徑：`StyleApplier` 偵測 `pollIntervalSeconds` 變更時呼叫 `onPollIntervalChange(秒)`（啟動時不呼叫，啟動參數由 `AppDelegate.startFeed` 依載入的樣式計算）。選單／面板／熱重載三條路徑都經 `StyleApplier`，所以行為一致。
   - **重啟期間顯示不中斷**：重啟只影響 helper 行程；Core／TickerDriver／TickerView 完全不被觸碰，帶子持續捲動、已排入與即時佇列中的訊息不受影響。
8. **helper 重啟後重發 `snapshot` 的安全性（有證據）**：新 helper 的「第一次成功輪詢」必發 `snapshot`（`connector-engine`「第一次成功輪詢發 snapshot」），所以每次重啟 Core 都會再收到一次。Core 現行語意：`receive(.snapshot)` 只取代 `history` 並設 `hasBaseline=true`，**不改 `mode`、不碰 `liveQueue`、不碰 `placed`**，因此：(a) 不會觸發 LIVE（只有 `.items` 內「不在歷史中」的訊息才會進佇列並設 `mode=.live`）；(b) 即時佇列與帶子上的訊息保留。副作用（誠實標示）：
   - 歷史被換成新 snapshot 的內容，重播清單（`latestItems`）可能與重啟前略有不同（新訊息已在 snapshot 內、舊訊息若已不在來源頁面就消失）；`(n/N)` 的 N 為「清單固定時」的總數，進行中的一輪重播沿用既有 `closedTotals`，下一輪才用新清單。
   - 重啟前後之間（舊 helper 最後一次輪詢到新 helper 首次輪詢）出現的新訊息，會直接進 snapshot 歷史，**不會**以 LIVE 播報。重啟間隙約為 stdin 關閉到新 helper 首次成功（數秒），使用者操作的頻率很低，接受此取捨【假設】。
   - 新 snapshot 之後的 `items` 以 snapshot 為基準去重：snapshot 內已有的 id 視為重複（`duplicatesSkipped`），不進即時佇列。
   以 Core 測試固定上述行為（含 REPLAY 與 LIVE 兩種模式下的重發），以 App 層測試（假 helper 腳本＋真實 `FeedClient` 重啟＋`AppCoordinator`）證明整條路徑的 `modesSeen` 不含 `live`、`placed` 不被清空。
9. **開機自動啟動：`SMAppService.mainApp`，包成 `LaunchAtLoginService`**。協定：`status: LaunchAtLoginStatus`、`enable() throws`、`disable() throws`、`openSystemSettings()`；`LaunchAtLoginStatus` ＝ `enabled`／`notRegistered`／`requiresApproval`／`notFound`。`SystemLaunchAtLoginService` 是唯一 import `ServiceManagement` 的檔案，`SMAppService.Status` → 自己的列舉用純函式 `map` 轉換（可測）。純邏輯 `LaunchAtLoginController`（可注入服務）把 `enable()/disable()` 的結果與錯誤轉成 UI 顯示用的 `LaunchAtLoginViewState`（開關位置、說明文字、是否提供「開啟系統設定」）。**平台行為【假設】**：本 App 為 ad-hoc 簽名、無 team ID、非 notarize、通常不在 `/Applications`；`register()` 可能 (a) 成功並直接 `enabled`，(b) 成功但 `requiresApproval`（使用者須到「系統設定 → 一般 → 登入項目」核准），(c) 丟錯。我們不預測也不隱藏——UI 一律顯示 `status` 與錯誤訊息，且勾選狀態以「呼叫後重新讀到的 `status`」為準（不是使用者按了什麼）。App 被移動（例如從 `build/` 搬走）後登入項目指向舊路徑，這是平台行為，列入人工驗收。自動測試用假服務，**不得真的註冊**，並以靜態掃描守衛 `Tests/` 不出現 `SMAppService`、`Sources/` 只在 `SystemLaunchAtLoginService.swift` 出現。
10. **設定面板（B 段）**：非啟用 `NSPanel`（`[.borderless, .nonactivatingPanel]`，`canBecomeKey/Main = false`、`hidesOnDeactivate = false`，level 高於跑馬燈一級，`collectionBehavior` 同跑馬燈），位置貼在跑馬燈下方（間距 6pt），下方空間不足時改放上方，水平靠跑馬燈左緣並夾進該螢幕 `visibleFrame`【假設】。關閉：再點齒輪、面板外按下滑鼠（含按在本 App 跑馬燈的非齒輪處，由 `TickerView.onTickerPointerDown` 回報；B 段實作時補充）、面板內關閉鈕。面板外偵測用 `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`——**只監看滑鼠按下，不需要輔助使用權限**（鍵盤事件才需要）；全域監看器看不到本 App 自己視窗內的事件，所以面板內與齒輪的點擊由本地 hit-test 處理。操作立即生效並寫回 `style.json`（經既有 `StyleStore.update`）。選單列「樣式」子選單**保留**，兩處共用 `StyleMenuModel` 與 `StyleActionRunner`【假設】。**平台風險**：非啟用面板內的 `NSSlider`／`NSSegmentedControl`／`NSSwitch` 是否能不啟用 App 就正常互動（第一次點擊就生效、可拖動滑桿）屬平台行為，無法在自動測試中證明，列為人工驗收項；若實測 slider 無法拖動，退路是改用步進按鈕（−／＋）或讓面板可成為 key 但不啟用 App（`becomesKeyOnlyIfNeeded`），由 B 段實測後決定並回報。
11. **`StyleMenuModel` 共用**：A 段只在純資料層增 `StyleMenuAction.setSeekHoldSeconds(Double)`／`.setPollIntervalSeconds(Int)` 與 `apply`（夾制仍由 `StyleStore.update` 負責）；選單列「樣式」子選單的 `entries` **不新增**這兩項（它們只在齒輪面板顯示），以免選單變長且未被要求【假設】。面板的控制項清單由 B 段在同一個模型上擴充（例如 `SettingsPanelModel`），不另寫第二套動作邏輯。

## Dependencies on in-progress changes

下列 requirement 尚未在主 specs（僅存在於進行中的 `ticker-style-settings`），故本 change 用 ADDED 而非 MODIFIED，並在 archive 順序上依賴它：`TickerStyle 結構與欄位`、`執行期重新設定`、`樣式子選單的項目清單`。建議 archive 順序：`ticker-style-settings` → `settings-gear`。若 `settings-gear` 先 archive，新 capability 仍可獨立成立，但其文字引用的 `TickerStyle` 要在 `ticker-style-settings` archive 後才有完整規格。`app-shell` 的設計文件寫「初始 620×42」，本 change 的 648 寬度覆寫它（app-shell 的 specs 不含 620 的 requirement，只有 design 敘述）；`single-instance-guard` 的 `ticker-navigation`「切換操作不啟用 App」delta 與本 change 的 `settings-gear` 不衝突（本 change 不修改該 requirement，另以新 requirement 規範齒輪）。

## Risks / Trade-offs

- [28pt 槽寬與齒輪觀感未目視] → 離屏 PNG 自動檢查置中與對齊，觀感列人工驗收。
- [`SMAppService` 在 ad-hoc 簽名 App 行為不確定] → 如實顯示狀態、不宣稱成功、人工驗收三種結果皆算「行為如設計」。
- [重啟 helper 的間隙漏播 LIVE] → 決定 8 說明並標【假設】。
- [非啟用面板內控制項互動] → 人工驗收與退路（決定 10）。
- [面板寬度 648 使既有寫死座標的測試平移] → 逐項記錄於 `Tests/README.md`，斷言數量不減。

## Migration Plan

純程式與文件變更。`style.json` 缺新鍵時取預設，舊檔向前相容；新版寫回的檔案多兩個鍵，舊版 App 讀到會視為未知鍵（警告＋忽略，並依既有規則在寫回前備份）。已儲存的視窗位置：寬度由 620 變 648，`PlacementMath` 以新尺寸夾制，不需遷移。回滾＝還原該分支 commit。不 archive（由協調者驗證後處理）。

## Open Questions

- 齒輪槽寬 28、齒輪尺寸與 hover 不透明度待使用者目視。
- 輪詢間隔是否要提供 5 秒：待另行實測「連續請求會拿到新資料」後再議。
- 面板內控制項在非啟用面板上的互動（決定 10）待實機驗證。
- 透明度滑桿仍在選單列，是否也搬進面板由使用者決定（本 change 不搬，因使用者列的項目不含透明度）【假設】。
