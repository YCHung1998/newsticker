前置：`message-contract`、`connect-engine-fastbull`、`show-engine-core` 已 archive；app-shell 第 A、B 段已實作（程式在 `Sources/FastBullTickerApp/`）；建議先 apply `ticker-navigation-link`（見 design.md）。使用者尚未確認本 change 的 proposal 前 **不得 apply**（見倉庫 `CLAUDE.md`）；apply 前先跑 `openspec validate ticker-style-settings --strict`。

通則：每個改邏輯的 task 先寫測試並記錄「失敗」輸出，再實作並記錄「通過」輸出（fail-then-pass），回報附實際指令與測試檔路徑。每項標【自動】或【需人工】。**自動測試不得開啟真實視窗、不得觸及使用者真實的 `style.json`、不得真的呼叫 `NSWorkspace.shared.open`**。apply 順序 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9。總計 9 項（≤ 12）。

## 1. 樣式模型與驗證（純函式）

- [x] 1.1 【自動】`Sources/FastBullTickerApp/TickerStyle.swift`（僅 import Foundation）：`TickerStyle`（15 個欄位、`default`）、`RGBColor` 與 `#RRGGBB` 解析／正規化、`ContrastRatio`（WCAG）、`StyleParser.parse(Data)`（整份失敗 vs 欄位層級夾制／預設／警告、未知鍵、`version`、64KB 上限、對比度警告）。測試 `Tests/FastBullTickerAppTests/TickerStyleTests.swift`、`StyleParserTests.swift`：欄位齊全與往返、預設值逐項斷言、**預設值與原型常數一致**（`ShellConfig.provisional` 的 `panelSize`／`labelWidth`／`itemPadding`／`defaultAlpha`／`alphaRange` 與原型的空隙底色／標籤紅，色彩容忍 1/255）、越界夾制、型別錯誤、非法色碼（`red`／`#FFF`／`#FFE45C80`／`FFE45C`／`#GGGGGG`）、缺鍵／未知鍵、`labelText` 規則、三組配色預設對比度 ≥ 4.5 且低對比度只警告、固定種子隨機輸入永遠得到合法樣式。驗證方式：`swift test --filter TickerStyleTests`、`swift test --filter StyleParserTests`；fail-then-pass；mutation：改動一個預設值（例如 `fontSize` 17）或放寬一個範圍時測試須變紅。依賴：無。（S1 段實作註記：Core 另有同名列舉 `TickerStyle`〔`.live`／`.replay`〕，App 內本檔宣告優先；需要 Core 列舉時寫 `FastBullTickerCore.TickerStyle`，既有 `TickerRendererTests` 一處已改為限定名稱。`StyleParser.parse` 回傳 `Result<StyleParseResult, StyleLoadError>`，`StyleParseResult` 含 `style`、`warnings`、`unknownKeys`。）

## 2. Core：執行期重新設定

- [x] 2.1 【自動】`TickerScheduler`：`config` 改 `private(set) var`、`SchedulerTunables`、`reconfigure(_:measurer:)`（改速度保持視覺連續、已排入不變、`viewportWidth`／`maxItemWidth`／`showTime`／`timeZone`／measurer 只影響之後排入的訊息、`replayCount` 縮放不越界、隱藏中合法）、`SchedulerConfig.showTime`（預設 true）、`layoutItem` 的 `showTime` 參數（false 時顯示字串只有 `text`，`timeString` 為空）。測試 `Tests/FastBullTickerCoreTests/ReconfigureTests.swift`、擴充 `TickerLayoutTests`，並在 `SchedulerInvariantTests` 加入含 `reconfigure` 的長序列（若 `ticker-navigation-link` 已 apply，同序列加入 seek／hold／指標進出）。驗證方式：`swift test --filter ReconfigureTests`、`--filter TickerLayoutTests`、`--filter SchedulerInvariantTests`、`--filter FreezeResumeTests`；fail-then-pass；mutation：不調整 `baseOffset`（速度改變時視覺位置跳動）時測試須變紅；`swift test` 既有 Core 測試全過，`PackageSkeletonTests` 仍通過（Core 無 AppKit import）。依賴：無（與 1.1 可獨立）。

## 3. StyleStore：載入、熱重載、寫回

- [x] 3.1 【自動】`StyleStore.swift`、`StyleFileWatching.swift`（協定＋`DispatchSource` 實作＋測試用假監看器）：啟動載入（無檔案／損壞／越界）、目錄監看＋debounce 熱重載（位元組相同不重套、樣式相等不重套、連續觸發合併、刪檔保留）、整份失敗保留舊值並設「設定檔有誤」、原子寫入（暫存檔＋取代）、正規化輸出、`.bak` 備份（損壞或含未知鍵時）、自寫入雜湊辨識、寫入失敗不崩潰、`FASTBULL_TICKER_STYLE` 路徑覆寫、日誌以 `style:` 開頭走 `AppLog`。測試 `Tests/FastBullTickerAppTests/StyleStoreTests.swift`：全部用暫存目錄、假監看器與 `FakeClock`（見 `Support.swift`），測試前後不得觸及真實 `style.json`。驗證方式：`swift test --filter StyleStoreTests`；fail-then-pass；mutation：移除自寫入辨識（寫回後又被重套）、讓載入時改寫檔案、讓失敗載入覆蓋舊值，測試須變紅。依賴：1.1。

## 4. 外觀套用

- [x] 4.1 【自動＋需人工目視】`ShellConfig.swift` 移除 `fontSize`／`labelText`／`scrollSpeed`（保留其餘，`provisional` 的 level／collectionBehavior／renderer／feedTimer 不動）；`ItemBitmap.swift` 的顏色、字級、顯示字串改由 `TickerStyle`；`TickerView.swift`：標籤顯示／文字／顏色、空隙底色、`cornerRadius`（內容視圖圖層裁切）、`showLabel` 改變時重新佈局與 `viewportWidth`（若 `ticker-navigation-link` 已 apply，公式含控制列寬）、顏色變更時就地重繪已排入訊息（保存 `PlacedItem` 與樣式類型）、`fontSize`／`showTime` 只影響之後排入的訊息；`TickerDriver`／`AppDelegate` 以 `reconfigure` 套用速度、`replayCount`、`showTime`、新 measurer。若 `ticker-navigation-link` 已 apply，同步處理 `showTime = false` 時粗體偵測改用明確的 `timeBold`（見 design.md 決定 5）。測試擴充 `TickerRendererTests`、`PanelShellTests`：預設樣式渲染與原型像素一致、改色後位置與寬度不變且 bitmap 重繪、改字級只影響新訊息、圓角夾制到 21、`showLabel` 為 false 時 `viewportWidth` 增加標籤寬、`grep -rn "fontSize\|labelText\|scrollSpeed" Sources/` 只剩 `TickerStyle` 相關。驗證方式：`swift test --filter TickerRenderer`、`--filter PanelShell`、`--filter AppSmoke`；fail-then-pass 與 mutation（預設值被改、顏色改變時位置跳動，測試須變紅）。**需人工目視**（併入 8.1）：圓角觀感、配色、字級切換。依賴：1.1、2.1、3.1。 （S2 段實作註記：新增 `StyleApplier.swift`〔唯一套用路徑：`TickerView.apply(style:)`＋Core `reconfigure`〕；`TickerView` 以「字級世代」保存舊字級，使字級改變後的重繪／向後 seek 重建仍用原字級；`ItemBitmapRenderer` 時間粗體：繪製端用 `timeString` 長度（明確資訊），量測端因 `TextMeasurer` 只收字串而以 `showTime` 旗標決定是否偵測；**色碼以 Generic RGB 解讀**（原型的建構方式；改 sRGB 時預設紅的綠通道差 23，見 `Tests/README.md`），此為偏離 spec「不透明 sRGB」字面的決定，待使用者確認；標籤隱藏時畫面上已有訊息會整體左移 150pt；過渡性測試改寫見 `Tests/README.md` S2 段。重繪次數與耗時寫在日誌 `style: applied … redrew=N redrawMs=…`，**實機成本未量測**，圓角／配色／字級觀感併入 8.1。）

## 5. 選單

- [x] 5.1 【自動】`StyleMenuModel.swift`（純資料模型）、`WorkspaceFileOpener.swift`（唯一新增 `NSWorkspace.shared.open` 處）、`StatusMenu.swift` 新增「樣式」子選單與 `NSMenuDelegate.menuNeedsUpdate` 同步：字級檔位（13／16／20／24）、速度滑桿、訊息量（5／10／20）、圓角滑桿、即時配色三組、顯示時間／顯示標籤、開啟樣式設定檔…（檔案不存在先建立、注入 `FileOpener`）、重設為預設（`.bak`）、設定檔有誤提示行。更新 `StatusMenuTests` 的項目斷言（四項→五項），新增 `StyleMenuTests.swift`：項目清單與順序、各檔位勾選與自訂值不勾選、動作對樣式的影響、檔位皆在合法範圍、重設備份、開啟檔案只呼叫假 opener、守衛（`Tests/` 不得出現 `NSWorkspace.shared.open`，`Sources/` 只能在 `Workspace*Opener.swift`）、不建立 `NSWindow`／`NSAlert`。驗證方式：`swift test --filter StyleMenu`、`swift test --filter StatusMenu`；fail-then-pass；`grep -rn "activate(" Sources/` 無對 `NSApp`／`NSApplication` 的啟用呼叫。依賴：3.1、4.1。 （S2 段實作註記：`StyleMenuController.swift`〔`NSMenu` 呈現與 `StyleActionRunner`〕、`StyleMenuModel.swift`、`WorkspaceFileOpener.swift`〔`FileOpener` 協定與唯一新增的真實 `open` 呼叫〕；顯示時間／顯示標籤勾選依 spec 放在子選單內；守衛測試 `StyleMenuGuardTests` 確認 `Sources/` 恰有兩個 opener 檔出現真實 `open`；`grep -rn "activate(" Sources/` 無結果。）

## 6. 組裝與煙霧測試

- [x] 6.1 【自動】`AppDelegate.swift`：建立 `StyleStore`（正式監看器與 `WorkspaceFileOpener`）、套用啟動樣式、熱重載回呼（主執行緒）→ `TickerView` 與 `reconfigure`、選單操作寫回；headless 煙霧測試（假 helper 餵 snapshot／items，暫存目錄樣式檔，假監看器觸發）：改檔→生效樣式改變且畫面端收到一次套用、損壞檔案→生效樣式不變、選單改字級→檔案內容更新且不重套。驗證方式：擴充 `Tests/FastBullTickerAppTests/AppSmokeTests.swift`，`swift test --filter AppSmoke`、`make test`；`swift build` 無警告。依賴：5.1。 （S2 段實作註記：`StyleWiring.connect` 為 `AppDelegate` 與煙霧測試共用的接線；`AppDelegate` 以預設樣式建構視圖後經 `StyleApplier.apply(source: startup)` 套用啟動樣式，與熱重載／選單同一路徑；結束時 `flushWrite`。`AppDelegate` 本身（正式監看器、正式 opener、選單列圖示）沒有被自動測試執行，**真機啟動驗證未做**——開工時已有使用者的實例在跑。）

## 7. 文件

- [x] 7.1 【自動】`README.md` 與 `Tests/README.md`：`style.json` 欄位表、範例、環境變數、選單操作、熱重載與備份行為、測試清單與證據路徑；`Tests/evidence/` 放 fail-then-pass 輸出。驗證方式：`grep -n "style.json" README.md` 有結果；文件中的欄位表與 `TickerStyleTests` 的欄位清單一致（測試讀取 README 表格的鍵名並比對，缺漏則失敗）。依賴：1.1。 （S2 段實作註記：`README.md` 新增第 5.5 節與狀態／驗證表；`TickerStyleTests.readmeFieldTableListsExactlyTheStyleKeys` 讀 README 欄位表與 `TickerStyle.keys` 比對。）

## 8. 人工驗收

- [ ] 8.1 【需人工】使用者在機器前操作並回報（每項 PASS／FAIL／未執行〔含原因〕與截圖）：(a) 圓角滑桿 0→21 的觀感，與標籤、訊息裁切是否正確，圓角外是否可拖曳可接受；(b) 三組即時配色與手動編輯重播配色的實際觀感；(c) 字級四檔切換（舊新樣式短暫混合是否可接受）、`showTime`／`showLabel` 切換；(d) 速度滑桿手感、`replayCount` 改為 5／20 後循環；(e) 熱重載：以 TextEdit 與 `vim`（或 VS Code）各儲存一次，確認即時套用；存成非法 JSON 時畫面不變、日誌有錯誤、選單出現提示行；(f) 選單展開並拖動滑桿 60 秒，帶子無空白；(g) 「開啟樣式設定檔…」開啟的編輯器是否合理（`.json` 預設應用程式），本 App 啟用通知為零；(h) 「重設為預設」後 `.bak` 內容正確。結果寫入 `ACCEPTANCE.md`（路徑沿用 app-shell 5.x 的約定，待確認）。依賴：6.1。

## 9. 收尾

- [x] 9.1 【自動】整體驗證：`make helper app sign` 成功；`swift test`（或 `make test`）、`cd ticker-connect && cargo test`、`python3 -m unittest discover -s protocol/tests` 全綠；`openspec validate ticker-style-settings --strict` 與 `openspec validate --all --strict` 通過；核對 specs 中仍標【假設】／【待確認】的項目並在回報中列出（含 design.md 待釐清 1–10）。驗證方式：以上指令的實際輸出貼入回報並附測試檔路徑清單；未完成或未驗證之處照實說。依賴：1–8。 （S2 段結果：`swift build` 0 warning；`make helper app sign` 成功；`swift test` 471 個，470 通過、**1 個失敗**〔`defaultsAgreeWithShellConfigPrototypeConstants`：工作樹有不屬於本 change 的未提交修改 `ShellConfig.itemPadding` 10，原型為 14，待使用者決定〕；其餘指令見回報。仍標【假設】的項目＝design.md 待釐清 1–7；8 已處理（`timeBold`／`timeString` 長度＋量測端旗標）；9 待確認；10 需人工〔併入 8.1〕。9.1 的「全綠」因該 1 個失敗**不成立**，勾選代表驗證已執行並如實記錄，不代表全綠。）
