## Why

使用者第一次目視原型後回饋：畫面可以，但希望（1）能從快訊回到網頁看完整訊息（迴紋針圖示）；（2）時間以粗體呈現；（3）知道目前滾動到第幾則 `(n/N)`；（4）能用 `<` `>` 切到前一則或下一則來看。這四項都需要新資料（每則快訊的完整頁面連結 `url`）與新的互動（點擊、暫停捲動），而原設計把「點擊開啟詳情」列為 v1 非目標（設計文件第 10 節）、把「點擊帶子」定義為拖曳（app-shell 的 `panel-shell`）。本 change 依使用者的新回饋調整這些決定，並把協定、連接器、Core 排程器與 App 殼層需要配合的修改一次規格化。樣式可調整（圓角、顏色、字級、速度、訊息量）另由 change `ticker-style-settings` 處理，不在本 change。

## What Changes

- **協定**（`message-protocol`、`protocol-decoding`、`contract-fixtures`）：`item` 新增**選填**欄位 `url`（絕對 http(s) URL，可見 ASCII，上限 2048 位元組【假設】）；缺少即「無連結」。`additionalProperties: false` 維持不變，`url` 明列於 `properties`。協定版本維持 `v: 1`【假設，理由與代價見 design.md】。新增合法與非法 fixtures（含 2048／2049 位元組邊界、結尾換行、非 http(s)、空字串、null、相對路徑等）；Rust、Swift、Python 參考驗證器三端同步。
- **連接器**（`fastbull-connector`、`connector-engine`）：FastBull 連接器由各 `div.news-list` 後代的 `data-href`（快訊頁實測為 `div.shear_box[data-href]`）組出 `https://www.fastbull.com` 加 `data-href` 為 `url`；缺 `data-href` 或值不合法時降級為無連結，不視為錯誤。快照測試驗證第一則 `url` 為 `https://www.fastbull.com/tw/fastshort/4334051_1_2`。`connector-engine` 僅修正「本 change SHALL NOT 新增協定欄位」的措辭使其不與新欄位矛盾。
- **Core**（`ticker-scheduler`、`ticker-layout`）：`PlacedItem` 增加 `url`、`seq`、`listID`、`listIndex`；新增純函數的閱讀位置查詢 `readingPosition`、`seek(.previous/.next)`、捲動保持（hold，預設 8 秒【假設】）與指標停留凍結；版面新增連結欄位寬度 `linkSlotWidth` 與時間粗體量測的契約；rebase 保留最近 `retainPlacedCount` 則以支援回溯。保持「`tapeX` 排入後不變」不變量（seek 只改 `baseOffset`）。
- **顯示**（新 capability `ticker-navigation`、`ticker-link`）：粗體時間、`(n/N)` 位置指示、右端控制列的 `<` `>` 按鈕、迴紋針圖示與以預設瀏覽器開啟連結（`NSWorkspace`，只允許 http(s)，不啟用本 App）、滑鼠停在面板上時暫停捲動【假設】、命中測試與拖曳的區分。
- 不在範圍：樣式／顏色／字級／速度／訊息量設定（`ticker-style-settings`）；「切換 Space 時帶子閃一下」是另案 bug 修復；FastBull 之外的來源；Windows／iOS；真正的內嵌網頁（維持不使用 WebView）。
- 本階段只產規格，不實作、不寫程式。

## Capabilities

### New Capabilities
- `ticker-navigation`: `(n/N)` 位置指示、右端控制列版面、`<` `>` 切換與邊界行為、切換後暫停與恢復、滑鼠停留暫停、命中測試與拖曳區分、不啟用 App、測試策略。
- `ticker-link`: 迴紋針圖示顯示規則、點擊以預設瀏覽器開啟、只允許 http(s)（`LinkPolicy`）、不啟用 App、自動測試不得開啟真實瀏覽器。

### Modified Capabilities
- `message-protocol`: `item 結構` 新增選填 `url` 及其規則。
- `protocol-decoding`: Swift 型別新增 `url`；嚴格性規則新增 `url` 驗證。
- `contract-fixtures`: fixtures 涵蓋清單新增 `url` 的合法與非法樣本。
- `fastbull-connector`: `HTML 解析規則` 與 `對快照 fixture 的解析測試` 新增 `url`。
- `connector-engine`: `遵守 message-contract 協定` 的措辭與 `url` 原樣輸出。
- `ticker-scheduler`: 輸出介面、設定、tape 座標模型、rebase 的修改；新增排入序號與清單識別、閱讀位置查詢、seek、捲動保持與指標停留凍結。
- `ticker-layout`: 新增連結欄位寬度與時間粗體量測一致。

## Impact

- 與 app-shell 的關係：app-shell（第 A、B 段已實作，5.x 人工驗收未做）的 specs 尚未同步到主 specs，故本 change 對其行為只能用 ADDED 追加並在 design.md 註明衝突，不修改其任何檔案。已知衝突：`panel-shell`「拖曳以 performDrag 實作」的「點擊帶子 MUST 等同拖曳（v1 不做開啟詳情）」與設計文件第 10 節非目標「點擊開啟詳情」，須在 app-shell archive 後以 MODIFIED 修訂（見 design.md「待處理」）。
- 與 `ticker-style-settings` 的關係：兩者都會改 `TickerView`、`ShellConfig`、`StatusMenu`；規格層無重疊的 MODIFIED，建議先 apply 本 change（見 design.md）。
- 會修改的程式（apply 階段）：`protocol/schema/item.schema.json`、`protocol/fixtures/*`、`protocol/refcheck.py`；`ticker-connect/src/{model,fastbull}.rs` 與其測試；`Sources/FastBullTickerCore/{ProtocolTypes,TickerScheduler,Layout}.swift`；`Sources/FastBullTickerApp/{ShellConfig,TickerView,TickerDriver,ItemBitmap,AppDelegate}.swift` 與新增的命中測試、`LinkPolicy`／`URLOpener` 檔案；對應測試。
- 相容性：舊版嚴格接收端會拒絕含 `url` 的訊息，helper 與 App 必須一起更新（同一個 `.app` 發行）。
- 前置：`message-contract`、`connect-engine-fastbull`、`show-engine-core` 已 archive（主 specs 已同步）；app-shell 第 A、B 段已實作。
