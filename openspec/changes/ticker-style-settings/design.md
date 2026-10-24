## Context

來源：使用者第一次目視原型後的回饋（樣式未來要可調：圓角、即時快訊顏色、文字內容、字級、速度、訊息量）、設計文件第 5 節、現行主 specs，以及 app-shell 已實作的程式（`ShellConfig.swift`、`TickerView.swift`、`ItemBitmap.swift`、`StatusMenu.swift`、`AppDelegate.swift`）。標【假設】者是本文件替使用者做的設計選擇，尚未確認；標【待確認】者是矛盾或缺漏，不自行補猜。

現況（已讀程式）：
- 外觀常數散在三處：`ShellConfig`（`fontSize` 16、`labelText`、`scrollSpeed` 90、`itemPadding` 14、`labelWidth` 150、`panelSize` 620×42、`defaultAlpha` 0.9、`alphaRange` 0.3…1.0）、`TickerView`（空隙底色 RGB(0.09, 0.09, 0.10)、標籤紅 RGB(0.85, 0.10, 0.13)、標籤白字 15pt Semibold）、`ItemBitmapRenderer.render`（`live` 白底黑字、`replay` 黑底白字，寫死為 0/1 灰階）。
- `TickerScheduler.config` 是 `let`；measurer 在建構時注入（`ItemBitmapRenderer.measurer` 內含字級與留白），所以字級改變時**必須**能換 measurer。
- `StatusMenuController.items` 恰為四項，`StatusMenuTests` 斷言 `kinds == [.opacity, .toggleVisibility, .clickThrough, .quit]`。
- 位置存檔已有 `PlacementSaver`（debounce 0.5 秒）、`FeedClock` 測試替身、`AppLog`、`~/Library/Application Support/FastBullTicker/` 目錄；環境變數覆寫的命名慣例為 `FASTBULL_TICKER_*`。

## Goals / Non-Goals

**Goals**
- 以單一 `TickerStyle` 集中所有可調外觀與行為，預設值與原型一致。
- 檔案（可手動編輯、熱重載）＋選單（快速入口）兩條路徑，且兩者修改同一份資料。
- 全部可純函式測試；自動測試不開真實視窗、不碰使用者真實設定檔、不開真實編輯器。

**Non-Goals**
- 圖形化設定視窗（會啟用 App，且設計文件第 10 節列為非目標）。字型家族、視窗尺寸、位置、透明度（既有機制）。主題包／匯入匯出。重播配色的選單入口。`ticker-navigation-link` 的功能。

## Decisions

### 1. `TickerStyle` 欄位、範圍與預設值【假設】

| 鍵 | 預設 | 範圍 | 備註 |
|---|---|---|---|
| `cornerRadius` | 0 | 0–21 | 預設 0＝直角，與原型一致；若使用者希望預設就有圓角，是外觀變更，需另行決定 |
| `fontSize` | 16 | 10–26 | 面板高 42，CJK 行高約 1.45 倍字級，26 為安全上限 |
| `scrollSpeed` | 90 | 20–300 | 原型 90 px/s（註解：60 時 8 秒一則的示範會一直堆積在 LIVE） |
| `replayCount` | 10 | 3–30 | 使用者指定 3–30；`historyLimit` 預設 200 ≥ 30 |
| `showTime` | true | — | |
| `showLabel` | true | — | |
| `labelText` | 即時財經快訊 | 1–16 Character | 標籤寬 150pt、15pt Semibold，約可容納 8–9 個 CJK 字；超寬以尾端「…」截斷（`CATextLayer.truncationMode = .end`，人工目視） |
| `labelBackground` / `labelColor` | `#D91A21` / `#FFFFFF` | `#RRGGBB` | 為使預設一致而增加 |
| `tapeBackground` | `#17171A` | `#RRGGBB` | 訊息間空隙底色；為使預設一致而增加 |
| `liveBackground` / `liveText` | `#FFFFFF` / `#000000` | `#RRGGBB` | 使用者指定「即時預設白底黑字」 |
| `replayBackground` / `replayText` | `#000000` / `#FFFFFF` | `#RRGGBB` | 使用者指定「重播預設黑底白字」 |
| `version` | 1 | 僅 1 | 日後格式升級用 |

- **為什麼用扁平結構而不是 `{live: {background, text}}`**：手動編輯與選單操作都更簡單，驗證與警告訊息的鍵名也直接對應檔案。代價是鍵較多，可接受（15 個）。
- **色碼量化**：原型的 RGB 浮點值（0.09、0.10、0.85、0.13）無法以 8 位元精確表示；`#17171A`、`#D91A21` 與原值差距 ≤ 1/255（不可見）。預設值測試以 ≤ 1/255 容忍度斷言，並直接與原型常數比較，防止日後兩邊漂移。若使用者要求逐位元相同，可改為預設值直接使用原浮點常數、檔案存在時才用色碼（本案不採用，複雜度不值得）。
- 透明度（alpha）**不**納入：它已有選單滑桿與 UserDefaults，且語意是視窗層級。

### 2. 驗證為純函式，不依賴先前狀態

`StyleParser.parse(_ data: Data) -> Result<(TickerStyle, [Warning]), StyleLoadError>`：
- 整份失敗（`StyleLoadError`）：非 UTF-8／非 JSON、頂層非物件、`version` 非整數 1、檔案過大。→ 呼叫端保留舊值。
- 欄位層級：越界夾制＋警告；型別錯誤與非法色碼→欄位預設值＋警告；未知鍵→忽略＋警告；缺鍵→預設值。
- 對比度（WCAG，一般文字 AA 4.5）低於門檻→警告但照用。
- 為什麼欄位層級取「預設值」而不是「保留舊值」：使用者描述的是「格式錯誤時保留舊值」（整份）；欄位層級若保留舊值，驗證就依賴狀態，無法純函式測試，且「檔案內容」與「生效值」之間會出現看不見的不一致（檔案寫 `blue`、畫面卻是上次的紅）。取預設值使「檔案＋預設」決定生效值，可重現。【假設】

### 3. 熱重載與寫回（`StyleStore`）

- 目錄監看（`DispatchSource` `O_EVTONLY`，注入 `StyleFileWatching` 協定）＋ 0.3 秒 debounce → 讀檔 → 與上次位元組比較 → `StyleParser` → 與生效樣式比較 → 通知套用端（主執行緒）。
- 監看目錄的理由：TextEdit、多數編輯器以原子取代儲存，對檔案本身的監看會在第一次儲存後失效。正式實作行為需人工驗證（TextEdit、`vim`／VS Code 各儲存一次）。若 `DispatchSource` 實測漏事件，退路是 1 秒輪詢 `mtime`（仍不需任何權限）。
- 寫回：選單修改→立即套用→0.5 秒 debounce→原子寫入（同目錄暫存檔＋`replaceItemAt`）。正規化輸出（鍵排序、縮排、大寫色碼）。寫入內容雜湊記起來，之後的目錄事件若讀到相同雜湊即為自寫入，不重套。
- 備份：磁碟上現有檔案「無法解讀」或「含未知鍵」時先複製為 `style.json.bak`。理由：使用者可能正在手寫 JSON（暫時不合法），此時若同時按了選單，直接覆蓋會毀掉使用者的內容。已知限制：正規化輸出會丟掉未知鍵與（JSON 本來就沒有的）註解。
- 檔案被刪除→保留生效樣式（因為原子取代的瞬間可能暫時看不到檔案；debounce 之後仍不存在才記錄日誌）。使用者要回到預設請用「重設為預設」。
- 啟動時**不**自動建立檔案（避免在使用者不知情下寫檔）；「開啟樣式設定檔…」才會建立。

### 4. 套用語意（最關鍵的取捨）

Core 的「`tapeX`／`width` 排入後不變」不變量使「改字級時重排畫面上的訊息」不可行（寬度改變會與相鄰訊息重疊）。因此分兩類【假設】：
- **即時、影響已排入訊息**：顏色（就地重繪 bitmap，寬度不變）、空隙底色、標籤、圓角、速度（`reconfigure` 保持視覺連續）。實作上 `TickerView` 需保存每個圖層對應的 `PlacedItem` 與樣式類型，以便重繪；僅顏色改變時每則訊息重新渲染一次（最多數十則，成本可接受）。
- **只影響之後才排入的訊息**：`fontSize`、`showTime`（改變寬度）。已排入訊息維持舊樣式直到捲出視窗（約 370–470pt／90px/s ≈ 數秒到十數秒）。替代方案是「清空帶子重排」（立即但會閃一下，且與另案 bug「切換 Space 閃一下」的感受類似），不採用。
- `showLabel` 改變帶子可視寬度（`viewportWidth` 增減標籤寬度）：已排入訊息位置不動，右緣改變只影響之後的補料；`TickerView` 的裁切圖層需重新佈局。

### 5. Core 修改（小）

```swift
public struct SchedulerTunables: Sendable { var speed: Double; var viewportWidth: Double; var maxItemWidth: Double
                                           var replayCount: Int; var showTime: Bool; var timeZone: TimeZone }
extension TickerScheduler { public mutating func reconfigure(_ t: SchedulerTunables, measurer: @escaping TextMeasurer) }
public struct SchedulerConfig { ... public var showTime: Bool = true }
public func layoutItem(_ item: Item, timeZone: TimeZone, maxWidth: Double, showTime: Bool = true, measurer: TextMeasurer) -> ItemLayout
```
- `config` 由 `let` 改 `private(set) var`。
- 改速度：`baseOffset += (oldSpeed − newSpeed) × tapeTime`，`scrollOffset` 不變。
- 只開放六個欄位（`gap`、`liveQueueLimit`、`historyLimit`、`rebaseThreshold` 不可變），縮小風險面。
- 與 `ticker-navigation-link` 的互動：`seek` 與 `rebase` 也只調整 `baseOffset`，三者可交錯；測試要涵蓋「seek 後改速度」「hold 期間改速度」（hold 不受影響，因為 hold 是時間而非位移）。
- 顯示字串在 `showTime = false` 時只有 `text`；`ItemBitmapRenderer.render` 需改用 `PlacedItem` 的顯示字串（目前寫死 `timeString + " " + text`）。`ticker-navigation-link` 的「時間粗體」以前 8 字元 `dd:dd:dd` 前綴偵測，`showTime = false` 時若訊息本文剛好以該格式開頭會被誤判為時間。**建議**：measurer 與繪製函式接收明確的 `timeBold: Bool`（由 `showTime` 決定）而不是只靠格式偵測；這需要 `ticker-navigation-link` 先 apply 後在本 change 修正（列入 tasks 4.1 的驗證項）。

### 6. 選單（`StyleMenuModel` + `StatusMenuController`）

資料模型產生項目描述（標題、勾選、停用、動作），`NSMenu` 只負責呈現，因此「選單項目清單」可純函式測試。子選單：字級（小 13／標準 16／大 20／特大 24）、捲動速度滑桿、訊息量（5／10／20）、圓角滑桿（0–21）、即時配色（白底黑字／黃底黑字 `#FFE45C`+黑／綠底白字 `#1E7B3C`+白）、顯示時間、顯示標籤、開啟樣式設定檔…、重設為預設；設定檔有誤時最上方多一行停用提示。

- 全部在 `NSMenu` 內，**不開視窗、不用 `NSAlert`**（會啟用 App，違反 app-shell「永不啟用」）。因此「重設為預設」沒有確認，改以 `style.json.bak` 作為復原手段。
- 滑桿沿用既有 `NSMenuItem.view` 作法；選單展開期間補料計時器 `.common` mode 不得更動。
- 色碼取捨：綠底白字 `#1E7B3C` 對比度 ≈ 5.3，黃底黑字 `#FFE45C` ≈ 16.5；色碼是設計選擇，需使用者看實物決定【假設】。

### 7. 測試策略

- 純函式：`StyleParser`（驗證、夾制、色碼、對比度、隨機輸入永遠得到合法樣式）、`StyleMenuModel`、預設值斷言（與原型常數逐項比較）。
- `StyleStore`：暫存目錄＋`FakeWatcher`＋`FakeClock`；驗證熱重載、debounce、自寫入、備份、原子寫入、刪除檔案、損壞檔案保留舊值。
- Core：`reconfigure` 的視覺連續、已排入不變、`replayCount` 縮小不越界；`swift test --filter` 為主，fail-then-pass 與 mutation（例如故意不調整 `baseOffset`，測試須變紅）。
- 渲染：預設樣式的 bitmap 像素與原型一致；改色後就地重繪、位置不變。
- 守衛：`Tests/` 不得出現 `NSWorkspace.shared.open`；測試不得觸及真實 `style.json`。
- 人工目視：圓角觀感、配色、字級切換、滑桿手感、熱重載（TextEdit／vim 儲存）、選單展開 60 秒不斷料。

## 與 app-shell 的關係（app-shell 尚未 archive，不修改其檔案）

| app-shell 的 requirement（尚未同步到主 specs） | 本 change 的處理 |
|---|---|
| `panel-shell`（透明度由 window `alphaValue`、純色背景、無毛玻璃、`.clear` 背景） | 沿用；圓角以內容視圖圖層裁切，不改窗口屬性，不新增毛玻璃。 |
| `status-menu`「選單列項目與選單內容」：四類項目 | 新增第五項「樣式」；既有 `StatusMenuTests` 更新。與其 requirement 的字面（「SHALL 含…四類」）不衝突，因為它是「含」而非「僅含」。 |
| `status-menu`「選單展開期間計時器不斷料」 | 不變；滑桿操作須在此條件下仍不斷料（人工驗證）。 |
| `ticker-renderer`「每則訊息預渲染為 bitmap」 | bitmap 的顏色與字級改由 `TickerStyle` 提供；顏色變更時就地重繪。 |
| `window-persistence` | 不變；樣式檔獨立於位置與透明度，不混存。 |
| 設計文件第 10 節非目標：「設定頁」「可調捲動速度」 | 使用者新回饋已覆蓋速度可調；本案以檔案＋選單而非「設定頁（視窗）」滿足，未違反「不開視窗」。【待確認】使用者是否同意以新回饋為準。 |

## 與 ticker-navigation-link 的依賴與 apply 順序

**建議先 apply `ticker-navigation-link`，再 apply 本 change。** 理由：
1. 該 change 動協定、Rust、Core 排程器與命中測試，風險較高、跨語言；越早做越早暴露問題。本 change 主要在 App 層，另有一個小而獨立的 Core 擴充。
2. 本 change 的 `replayCount`（`(n/N)` 的 N）、`showTime`（時間粗體）、`showLabel`（可視寬度公式含控制列）都以該 change 的結果為基礎；先做則本 change 直接擴充，不必預留或回頭修改。
3. 該 change 的控制列與迴紋針顏色放在 `ShellConfig`；本 change 將外觀來源改為 `TickerStyle` 時可一併決定這些衍生色（建議：迴紋針與控制列文字色沿用目前樣式類型的文字色，不新增欄位），不會做白工。
4. `StatusMenuTests` 與 `AppSmokeTests`、`TickerRendererTests` 兩邊都要改；後做的人承擔合併成本，而本 change 的改動較機械。
若順序相反：技術上可行，但該 change 之後須把控制列、迴紋針顏色接入 `TickerStyle`，`viewportWidth` 公式再加控制列寬，且 `timeBold` 修正在該 change 一開始就要納入。

規格層衝突：兩邊**沒有**同一條 requirement 被 MODIFIED（本 change 只 MODIFIED `ticker-layout` 的 `時間字串格式與時區注入`；該 change 對 `ticker-layout` 只有 ADDED；`ticker-scheduler` 這邊只 ADDED、該 change 做 MODIFIED），所以 archive 順序不影響規格合併。程式層衝突：`ShellConfig.swift`、`TickerView.swift`、`ItemBitmap.swift`、`StatusMenu.swift`、`AppDelegate.swift`、`TickerDriver.swift` 兩邊都改，需在第二個 change 的 apply 前確認第一個已合併。

## Risks / Trade-offs

- [就地重繪顏色需要保存每個圖層的 `PlacedItem`] → 與 `TickerView` 內部資料結構相關，若成本過高，退路為「顏色也只影響新訊息」（使用者調色時要等數秒才看到，體驗較差）。
- [熱重載的 DispatchSource 在目錄事件上的實際行為] → 人工驗證；退路輪詢 `mtime`。
- [`fontSize` 與 `showTime` 只影響新訊息，畫面上會短暫混合新舊樣式] → 已在 spec 明示為【假設】；替代方案「清空重排」會閃一下。
- [圓角裁切後，窗口四角透明處仍屬窗口範圍，會攔截點擊] → 視覺上圓角外可點擊拖曳；可接受，列入人工目視備註。
- [使用者手寫 JSON 時被選單覆蓋] → `.bak` 備份；但「正規化輸出丟掉未知鍵」仍是已知取捨。
- [預設 `cornerRadius = 0` 讓「圓角」功能一開始看不出來] → 這是為了「不改設定時畫面不變」的明確要求；使用者可從選單滑桿立即看到效果。
- [對比度警告只寫日誌，使用者看不到] → 選單不顯示警告（避免過度設計）；若使用者需要，可再加「樣式有警告」提示行【待確認】。

## 待釐清（彙整）

1. 預設 `cornerRadius` 0（與原型一致）還是給一個較好看的預設？【假設】
2. 各欄位範圍（`fontSize` 10–26、`scrollSpeed` 20–300、`labelText` 16 字等）與檔位（字級 13／16／20／24、訊息量 5／10／20）。【假設】
3. 三組即時配色色碼（`#FFE45C`、`#1E7B3C`）與是否要提供重播配色預設。【假設】
4. 欄位層級非法值取預設值（而非保留舊值）；未知鍵忽略＋警告；對比度門檻 4.5。【假設】
5. `fontSize`／`showTime` 只影響之後排入的訊息，顏色／速度／圓角／標籤即時生效。【假設】
6. 「重設為預設」無確認、以 `.bak` 備份代替；檔案被刪除時保留生效樣式。【假設】
7. 環境變數 `FASTBULL_TICKER_STYLE` 覆寫路徑（本 change 自訂名稱）。【假設】
8. `showTime = false` 時的粗體偵測（與 `ticker-navigation-link` 的互動，見決定 5）。【待確認／待實作時處理】
9. 設計文件第 10 節非目標（設定頁、可調速度）已被使用者回饋覆蓋，設計文件本身未改（`docs/` 不在範圍）。【待確認】
10. 圓角、配色、字級的實際觀感；熱重載對 TextEdit／vim 儲存方式的相容性；選單展開期間拖動滑桿不斷料。【需人工】
