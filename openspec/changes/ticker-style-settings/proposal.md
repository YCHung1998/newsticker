## Why

使用者第一次目視原型後的回饋：畫面可以，但**樣式未來要可以調整**——周圍圓角、即時快訊的顏色、文字內容、文字大小、滾動速度、呈現訊息量的多寡。目前這些值都是 app-shell 內寫死的常數（`ShellConfig`、`TickerView`、`ItemBitmapRenderer` 中的顏色與字級），修改需要重新編譯。本 change 把它們集中成一個可持久化、可熱重載的 `TickerStyle`，並在選單列提供不開新視窗的快速調整入口。與 change `ticker-navigation-link`（粗體時間、`(n/N)`、`<` `>`、迴紋針）互補，兩者範圍不重疊。

## What Changes

- **新增 `TickerStyle`**（`Codable`）：圓角、字級、捲動速度、重播訊息量、是否顯示時間、是否顯示標籤、標籤文字、即時與重播各自的背景色／文字色，加上為使預設值與原型逐項一致而必要的空隙底色與標籤顏色。每個欄位有合法範圍與夾制／驗證規則（越界夾制並記日誌；型別錯誤與非法色碼取欄位預設值）。**預設值與目前原型的外觀一致**，不改設定時畫面不變。
- **持久化與熱重載**：`~/Library/Application Support/FastBullTicker/style.json`；檔案變動（目錄事件、debounce）即套用；整份檔案格式錯誤時保留舊值並記錄日誌；選單操作寫回（原子寫入、必要時備份為 `style.json.bak`、自寫入不重套）。
- **選單列新增「樣式」子選單**（`NSMenu`，不開新視窗、不啟用 App）：字級檔位、捲動速度滑桿、訊息量檔位（5／10／20）、圓角滑桿、即時配色預設（白底黑字、黃底黑字、綠底白字）、顯示時間／顯示標籤、開啟樣式設定檔、重設為預設。
- **Core 小幅擴充**：`TickerScheduler.reconfigure(_:measurer:)`（執行期改變速度［視覺位置連續］、可視寬度、最大寬度、重播則數、`showTime`、時區與 measurer；已排入訊息不變）、`SchedulerConfig.showTime`、版面支援不含時間的顯示字串。
- **外觀常數來源**：由 `ShellConfig` 改為從 `TickerStyle` 讀取（`fontSize`、`labelText`、`scrollSpeed` 移出 `ShellConfig`），預設值不變；`ShellConfig.provisional` 的視窗層級／旗標／渲染方案仍是暫定值，不在本 change 範圍。
- 不在範圍：`ticker-navigation-link` 的功能；視窗尺寸／位置／透明度（沿用既有 Persistence 與滑桿）；圖形化設定視窗（設計文件非目標，維持選單＋檔案）；主題包／匯入匯出；字型家族可選；重播配色的選單入口（只能改檔案）。
- 本階段只產規格，不實作、不寫程式。

## Capabilities

### New Capabilities
- `ticker-style`: `TickerStyle` 欄位與預設、與原型一致的斷言、驗證與夾制、色彩格式、可讀性警告、外觀常數來源、套用語意、測試策略。
- `style-persistence`: 樣式檔位置與格式、啟動載入、熱重載、格式錯誤保留舊值、寫回與備份、測試策略。
- `style-menu`: 「樣式」子選單的項目與各控制（字級、速度、訊息量、圓角、即時配色、時間／標籤切換、開啟設定檔、重設）、選單同步、測試策略。

### Modified Capabilities
- `ticker-layout`: `時間字串格式與時區注入` 新增 `showTime` 為 false 時的顯示字串。
- `ticker-scheduler`: 新增「執行期重新設定」與「SchedulerConfig 增加 showTime」兩條 requirement（皆為 ADDED，未修改既有 requirement）。

## Impact

- 與 app-shell 的關係：app-shell（第 A、B 段已實作，5.x 人工驗收未做）的 specs 尚未同步到主 specs，本 change 不修改其任何檔案；對其行為只能用 ADDED 追加（`ticker-style` 的「外觀常數來源改為 TickerStyle」「樣式變更的套用語意」，`style-menu` 的子選單）。既有 `StatusMenuTests` 對「恰為四項」的斷言須更新。
- 與 `ticker-navigation-link` 的關係：兩者都會改 `TickerView`、`ShellConfig`、`ItemBitmap`、`StatusMenu`；規格層沒有同一條 requirement 被兩邊 MODIFIED。**建議先 apply `ticker-navigation-link`，再 apply 本 change**（理由見 design.md）。
- 會修改的程式（apply 階段）：新增 `Sources/FastBullTickerApp/{TickerStyle,StyleParser,StyleStore,StyleFileWatching,StyleMenuModel,WorkspaceFileOpener}.swift`；修改 `ShellConfig.swift`、`TickerView.swift`、`ItemBitmap.swift`、`StatusMenu.swift`、`AppDelegate.swift`；`Sources/FastBullTickerCore/{TickerScheduler,Layout}.swift`；對應測試。
- 風險：圓角裁切與 bitmap 就地重繪的視覺細節；熱重載對各種編輯器儲存方式的相容性；設計文件第 10 節把「設定頁」「可調捲動速度」列為 v1 非目標，使用者新回饋已覆蓋（見 design.md 待確認）。
- 前置：`message-contract`、`connect-engine-fastbull`、`show-engine-core` 已 archive；app-shell 第 A、B 段已實作。
