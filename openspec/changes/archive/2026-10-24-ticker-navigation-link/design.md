## Context

來源：使用者第一次目視原型後的回饋（粗體時間、`(n/N)`、`<` `>`、迴紋針連結），加上設計文件第 3、4、5 節與現行主 specs。標【假設】者是本文件替使用者做的設計選擇，尚未確認，規格中原樣標示。標【待確認】者是矛盾或缺漏，不自行補猜。

現況（已讀程式）：
- 協定 `item` 有四個必填欄位且 `additionalProperties: false`（`protocol/schema/item.schema.json`、Rust `Item` 的 `deny_unknown_fields`、Swift `Item` 的 `StrictKeys.check`）。
- FastBull 快照中 `data-href` **不在** `div.news-list` 自身，而在其後代 `div.shear_box[data-href]`；整份文件 70 個（側欄 20＋主內容 50），側欄 20 則逐一等於 `/tw/fastshort/` 加 `data-id`（已用腳本核對，0 個不符）。
- `TickerScheduler` 是值型別、`let config`、`placed` 只在 rebase 時移除、`scrollOffset = baseOffset + speed × tapeTime`；渲染端 `TrackModel.prune` 會移除右緣小於 `offset − 100` 的圖層（單向捲動假設）。
- `TickerView.mouseDown` 整條 `performDrag`；`ShellConfig.panelSize` 620×42、標籤寬 150，帶子可視寬度 470。
- `ticker-connect/tests/no_external_network.rs` 會掃描 `tests/` 原始碼，**不得含正式主機名稱字面值**。

## Goals / Non-Goals

**Goals**
- 時間粗體、`(n/N)`、`<` `>`、迴紋針四項功能，且保持 Core 的不變量與可測性（純函式、假時鐘）。
- 協定修改最小、三端（Rust、Swift、Python 參考驗證器）以同一批 fixtures 驗證。
- 不啟用本 App、不搶鍵盤焦點；自動測試不開真實視窗、不開真實瀏覽器、不連正式網站。

**Non-Goals**
- 樣式可調（`ticker-style-settings`）。「切換 Space 時閃一下」bug 修復。內嵌網頁。通知／搜尋／歷史瀏覽。迴紋針的游標變手形（`cursorRects`，選配，不列入驗收）。

## Decisions

### 1. 協定：`url` 選填，版本維持 `v: 1`【假設】

- Schema（`protocol/schema/item.schema.json`）新增：
  ```
  "url": { "type": "string", "minLength": 1, "maxLength": 2048,
           "pattern": "^https?://[A-Za-z0-9\\[][!-~]*$",
           "not": { "pattern": "[^!-~]" } }
  ```
  `not` 子句不是多餘的：Python `re.search` 的 `$` 會匹配「結尾換行之前」，所以 `"https://a/\n"` 會通過單獨的 `pattern`；Rust `regex` 不會。加上 `not: {pattern: "[^!-~]"}`（任何可見 ASCII 以外字元）後三端一致。fixtures 特別加 `item-url-trailing-newline` 守這個分歧。
- 字元限定為可見 ASCII（`0x21`–`0x7E`）使 JSON Schema 的 `maxLength`（以字元計）等於位元組上限 2048；非 ASCII 位址必須由發送端 percent-encode。
- scheme 只接受小寫 `http`／`https`【假設】；`null` 非法（只有「缺少」代表無連結）【假設】。
- **為什麼不升 `v`**【假設】：helper 與 App 同倉庫、同一個 `.app` 發行、沒有外部消費者；欄位為選填，新 helper 對**新 App** 完全相容、**舊 App**（嚴格）會因 `additionalProperties: false` 以 `schema` 錯誤丟棄含 `url` 的整則。代價：兩端必須一起更新（`make app` 同時帶入 helper，所以實務上成立）。若日後有外部消費者或需要與舊 App 並存，改為 `v: 2`。這是對 `message-protocol` 既有決定「`v` 為整數 1」的有意延續，需使用者確認。
- 變更流程：依 `contract-fixtures` 的「契約變更需 fail-then-pass 證據」——先加 fixtures（參考測試失敗：schema 還在 `additionalProperties: false`），再改 schema 使其通過。

新增 fixtures（皆單行；2048／2049 以實體檔存放約 2KB，不需要 `generate`）：

| 樣本 | 預期 |
|---|---|
| `valid/items-with-url`、`valid/snapshot-with-url`、`valid/items-url-mixed`（有無混合）、`valid/items-url-max-length`（恰 2048 位元組） | accept |
| `invalid/item-url-js-scheme`、`item-url-ftp-scheme`、`item-url-empty`、`item-url-too-long`（2049）、`item-url-null`、`item-url-number`、`item-url-relative`、`item-url-has-space`、`item-url-trailing-newline` | reject（`schema`） |

### 2. FastBull 連接器

- 在每個 `#side_fast_news div.news-list[data-id]` 內以 `[data-href]` 取後代中依文件順序第一個【假設：取第一個】；`url = "https://www.fastbull.com" + data-href`（origin 是連接器常數，**不**從 `fetch` 的目標 URL 推導，否則測試用本機假伺服器位址時會產生本機 URL）。
- 降級而非丟棄：缺 `data-href`、值為空、不以單一 `/` 開頭、串接後不符合 `url` 規則，則輸出無 `url` 的 item 並寫 stderr。理由：引擎層（`connector-engine`「輸出前 schema 驗證與發送端過濾」）會**整個丟棄**含非法欄位的 item，若讓壞 `url` 漏過，使用者會漏掉一則新聞；連結只是附加功能。因此 `convert` 必須自行保證輸出的 `url` 合法。
- 測試的守衛衝突：快照測試要斷言 `https://www.fastbull.com/tw/fastshort/4334051_1_2`，但守衛測試禁止測試原始碼出現正式主機字面值。預期值須以測試輔助函式拼出（沿用守衛測試的 `["fastbull", ".com"].concat()` 手法）。這只是字串比對，不發任何請求。
- 沿用既有待確認：解析範圍取側欄 20 則（非主內容 50 則）。

### 3. Core 資料與 API 修改

`Item` 增加 `url: String?`（memberwise init 預設 `nil`，既有測試不需改）；`ProtocolRules` 增加 `maxURLBytes = 2048` 與單一驗證函式 `isValidURL(_:)`（逐位元組檢查 `0x21`–`0x7E`、prefix、主機首字元、長度），`Item.init(from:)` 以 `decodeIfPresent` 讀取並驗證（`null` 在 `decodeIfPresent` 會回 `nil`，須先檢查 key 是否存在且值為 null 才能拒絕）。

`PlacedItem` 增加 `url: String?`、`seq: Int`、`listID: Int`、`listIndex: Int`、`hasLinkSlot: Bool`。

`SchedulerConfig` 增加：`seekHoldSeconds = 8`【假設】、`readingInset = 24`【假設】、`linkSlotWidth = 0`、`retainPlacedCount = 64`【假設】。

```swift
public struct ReadingPosition: Equatable, Sendable { public var item: PlacedItem; public var index: Int; public var total: Int }
public enum SeekDirection: Sendable { case previous, next }
public enum SeekOutcome: Equatable, Sendable {
    case moved(target: PlacedItem, newlyPlaced: PlacedItem?)
    case atListStart, previousNotRetained, noReadingItem, noMaterial, hidden
}
extension TickerScheduler {
    public var readingItem: PlacedItem? { get }               // 純函數
    public var readingPosition: ReadingPosition? { get }      // 純函數
    public mutating func seek(_ d: SeekDirection) -> SeekOutcome
    public mutating func setPointerInside(_ inside: Bool)
    public private(set) var holdRemaining: Double
    public private(set) var isPointerInside: Bool
}
public func layoutItem(_ item: Item, timeZone: TimeZone, maxWidth: Double, linkSlotWidth: Double = 0, measurer: TextMeasurer) -> ItemLayout   // ItemLayout 增加 hasLinkSlot
```

`TickerScheduler.config` 維持 `let`（本 change 不需要執行期改設定；`ticker-style-settings` 才需要）。

內部實作要點（供 apply 參考，非規格）：
- 抽出 `placeNext(startX:)`，供 `tick()` 與 `seek(.next)` 的強制排入共用，保證強制排入的 `tapeX`（`tailEnd + gap`）與正常補料完全相同。
- `advance()` 改為：`delta` 先給 `holdRemaining` 消耗，剩餘才進 `tapeTime`；`isHidden || isPointerInside` 時整段不推進（也不消耗 hold）。
- 對齊：`baseOffset = target.tapeX − speed × tapeTime`，使 `scrollOffset == target.tapeX`。
- `listTotals: [Int: Int]` 記錄各 `listID` 的總數；進行中的即時批次總數＝已排入數＋`liveQueue.count`；清單隨 `placed` 一起被 rebase 清理。

### 4. 保持的不變量（必須有測試守住）

1. `tapeX`／`width` 排入後不變；seek、hold、pointer 凍結皆只動 `baseOffset` 或計時（rebase 的既有例外不變）。
2. 相鄰訊息間距恆為 `gap`（含強制排入）。
3. 兩次 seek／rebase 之間，位置是 tape 時間的純函數；隱藏與指標停留不推進時間。
4. 隱藏 1 小時後恢復位置不跳動（hold 計時同樣不消耗）。
5. rebase 前後視覺位置相同，且保留最近 `retainPlacedCount` 則。
6. 每則即時訊息只播一次（A2）：`>` 強制排入即時佇列的訊息算「播過」，不會再被供料器重複取出。
7. `readingPosition` 是純函數：同狀態同時間同結果、無副作用。
8. seek 成功後 `readingItem == target`（需要 `readingInset < 任何訊息 width`；時間字串本身已寬於 24pt，測試斷言）。

`SchedulerInvariantTests` 需擴充：以固定種子產生含 seek／指標進出／hide／rebase 的長序列，斷言以上不變量。

### 5. 閱讀位置、清單與 `(n/N)`【假設】

- **閱讀中那一則**：依排入順序第一則「右緣 > `readingInset`（24pt）且左緣 < `viewportWidth`」者。直覺：標籤右側那一則；快要離開（可見不到 24pt）者不算。
- **清單**：重播＝一輪（游標回到起點就是新一輪，`listIndex` 為在最新 N 則中的名次，最新為 1）；即時＝一個批次（舊到新，總數含佇列中尚未排入的，所以 LIVE 追加會讓 N 增加）。每則訊息在排入時就記下 `listID`／`listIndex`（與樣式一樣「跟著訊息」），避免歷史變動後名次漂移；`index = min(listIndex, total)` 作防呆。
- **顯示**：`(n/N)`；無閱讀中那一則時不顯示。LIVE 中帶子上若還有重播訊息在左緣，指示依左緣那一則的清單顯示（例如 `(8/10)`），等即時訊息捲到左緣才變成 `(1/3)`。這是「以閱讀位置為準」的自然結果，已於 spec 明示。
- N 的來源：`SchedulerConfig.replayCount`（預設 10）；`ticker-style-settings` 之後讓它可調，本 change 不需改動 `(n/N)` 邏輯。

### 6. `<` `>` 與邊界【假設】

- `<`＝清單內前一則：必須同 `listID` 且 `seq − 1`；清單第一則按 `<` 無動作（不跨清單、不重設暫停）。
- `>`＝帶子上的下一則；若尚未排入，**強制排入**供料器下一次會取的那一則（即時佇列優先，否則重播游標）。因此重播第 10 則按 `>` 就是「下一輪起點（最新一則）」，即時批次最後一則按 `>` 就是下一則即時或重播最新。這個定義與供料器自身行為一致，不引入第二套順序規則。
- 對齊目標：把目標左緣貼到視窗左緣（視覺 x＝0），暫停 8 秒（`seekHoldSeconds`）；再次 seek 重設為 8 秒，不累加。
- 暫停以注入時鐘計算，不另起 App 計時器；暫停期間 `tick()` 仍補料。

### 7. 回溯需要的支援

- Core：rebase 保留最近 `retainPlacedCount`（64）則（含負座標），否則 rebase 後（約 1.5 小時一次）`<` 會失效。64 遠大於預設清單 10 與上限 30 的重播則數（`ticker-style-settings` 的 `replayCount` 上限 30），也涵蓋即時佇列上限 30。
- 渲染端：`TrackModel.prune`（右緣小於 `offset − 100`）會移除左側圖層，向後 seek 時目標圖層已不存在。解法：`TickerRenderer.add(_ item: PlacedItem)` 對同一 `seq` **冪等**（`TrackModel` 改以 Core 的 `seq` 為鍵，不再自己遞增）；`TickerDriver.seek` 成功後對 Core `placed` 中與新視窗範圍重疊的訊息逐一 `add`（已存在者略過）。bitmap 重新渲染的成本可接受（每次點擊最多數則）。

### 8. 版面：控制列與連結欄位【假設】

- 控制列在面板**右端**（箭頭靠近訊息進入的一側，不遮住使用者正在讀的左側）：`< 24pt | (n/N) 52pt | > 24pt`＝`controlStripWidth` 100pt。面板仍為 620×42，帶子可視寬度由 470 縮為 **370**（`viewportWidth` 由 `ShellConfig` 計算：面板寬 − 標籤寬 − 控制列寬）。這是本 change 唯一會改變預設外觀的結構性取捨；替代方案是加寬面板到 720（保留 470 的帶子寬度），但會動到 app-shell 的「初始約 620×42」與已存的位置偏移夾制。【待確認】請使用者看實物後選。
- 控制列以獨立圖層繪製（底色純色、與訊息 `live`／`replay` 樣式無關），訊息圖層被裁切在控制列之外。
- 連結欄位 `linkSlotWidth` 26pt【假設】，位於每則有 `url` 的訊息最右側（含在 `width` 內，截斷預算相應扣除，所以 `maxItemWidth` 仍是總寬上限）。無 `url` 的訊息不保留欄位寬度（版面與現在完全相同）。
- 時間粗體：`ItemBitmapRenderer` 的 measurer 與繪製都改為「前 8 個字元（`dd:dd:dd` 加空白前綴時）粗體、其餘一般」，measurer 與繪製共用同一個屬性字串建構函式，避免寬度不一致；Core 不知情（只呼叫 `measurer(顯示字串)`）。粗體字型暫定 PingFang TC Semibold【假設，需人工目視】。與 app-shell `ticker-renderer`「每則訊息預渲染為 bitmap」相關（該 requirement 尚未同步到主 specs，故這裡用 ADDED 追加）。

### 9. 命中測試與拖曳

純函式 `HitTesting.target(at:in:)`，輸入面板座標的點、各區域幾何與「目前可見訊息」清單，輸出 `.previousButton / .nextButton / .link(seq) / .drag`。優先序：按鈕 > 迴紋針 > 拖曳。迴紋針命中區為連結欄位外擴 `hitSlop` 4pt、整條帶高，且只在標籤與控制列之間的可見帶子範圍內有效。`TickerView` 的滑鼠處理改為：
- `mouseDown`：算出目標並記錄；`.drag` 才呼叫 `performDrag`；按鈕與迴紋針只記錄。
- `mouseUp`：目標與按下時相同才觸發動作（按鈕→`seek`、迴紋針→`openURL`）。
- 為了可測，把 `mouseDown/mouseUp` 的邏輯放在不依賴 `NSEvent` 的方法（輸入座標與按鍵種類），`NSEvent` 的 override 只做轉接。

mouse-up 觸發的風險：設計文件指出 `performDrag` 之後 mouse-up 可能不送達，那是拖曳；單純點擊在非啟用面板上的 mouse-up 是否可靠沒有查證【待確認，需人工驗收；失敗則改 mouse-down 觸發，這屬我方實作選擇，不是平台限制，不得記為已知限制】。

### 10. 開啟連結

- `URLOpener` 協定（單方法）＋正式實作 `WorkspaceURLOpener`（本 change 唯一出現 `NSWorkspace.shared.open` 的檔案，用 `OpenConfiguration`）。`activates` 預設 true 讓瀏覽器成為前景【假設：使用者要閱讀】；選項：`false` 背景開啟。
- `LinkPolicy.openableURL(from:)` 是協定層規則之後的第二道防線；它回傳的包裝型別 `OpenableURL` 是 opener 唯一接受的參數型別，使「未驗證 URL 被開啟」無法通過編譯。
- 守衛測試掃描 `Tests/` 不得出現 `NSWorkspace.shared.open`；`Sources/` 只能在 `Workspace*Opener.swift`（實作 opener 協定的檔案；`ticker-style-settings` 會再加 `WorkspaceFileOpener.swift`）出現。

### 11. 滑鼠停留暫停【假設】

指標在面板範圍內即 `setPointerInside(true)`，離開即恢復；`NSTrackingArea(.activeAlways, .mouseEnteredAndExited)` 為主，補料計時器每次以 `NSEvent.mouseLocation` 對 `panel.frame` 重新核對（`PointerHover.isInside`）當保險，避免 exit 事件遺失造成永久凍結。`NSEvent.mouseLocation` 不需要任何權限。已知副作用：滑鼠停在帶子上（例如拖曳視窗後忘了移開）帶子就不動。【待確認】是否改成「只有在迴紋針／按鈕命中區上才暫停」或「離開後延遲 N 秒恢復」；前者無法達成「點擊移動中的目標」，故預設整個面板。若面板被其他視窗蓋住，指標位置仍在 frame 內會誤判為在內，可選用 `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` 確認最上層是否為本面板（列為實作時可選強化，不列入驗收）。

## 與 app-shell 的關係（app-shell 尚未 archive，不修改其檔案）

| app-shell 的 requirement（尚未同步到主 specs） | 本 change 的處理 |
|---|---|
| `panel-shell`「拖曳以 performDrag 實作」：「點擊帶子 MUST 等同拖曳（v1 不做開啟詳情）」 | **衝突**。本 change 以 ADDED 在 `ticker-navigation` 定義「命中測試與拖曳區分」（按鈕與迴紋針為動作，其餘為拖曳）。app-shell archive 之後，主 specs 會同時存在兩條互相矛盾的敘述，需追加一個 MODIFIED（見下方待處理）。 |
| `panel-shell`「Accessory App 且永不啟用」 | 沿用，本 change 在兩個 capability 各加一條「不啟用本 App」的驗收。 |
| `ticker-renderer`「每則訊息預渲染為 bitmap」「TickerRenderer 介面」 | 時間粗體、迴紋針繪入 bitmap；`add` 改為對同一 `seq` 冪等（介面行為追加，ADDED 描述於 `ticker-navigation`／`ticker-link`）。 |
| `status-menu`「點穿模式」 | 點穿下不暫停、不可點擊（已寫入 spec 的情境）。 |
| 設計文件第 10 節非目標：「點擊開啟詳情」 | 使用者新回饋覆蓋。【待確認】視為使用者已授權調整；設計文件本身未改（`docs/` 不在本次修改範圍）。 |

**待處理**：app-shell archive 後，需有一個 MODIFIED 修訂 `panel-shell`「拖曳以 performDrag 實作」（改為「除按鈕與迴紋針命中區外，點擊帶子等同拖曳」）。因為 app-shell 的 specs 尚未在主 specs 中，本 change 無法現在就寫這個 MODIFIED（archive 會因目標不存在而失敗）。建議在 app-shell archive 後、本 change archive 前，由協調者以一個小補丁處理，或在本 change apply 前先 archive app-shell 並把此項補成本 change 的 MODIFIED。

## 與 ticker-style-settings 的依賴與 apply 順序

兩個 change 都會碰 `ShellConfig`、`TickerView`、`ItemBitmap`、`StatusMenu`，但**規格層沒有同一條 requirement 被兩邊 MODIFIED**（本 change 的 `ticker-scheduler` MODIFIED 四條，style 只對 `ticker-scheduler` 做 ADDED；`ticker-layout` 本 change 只 ADDED、style 才 MODIFIED `時間字串格式與時區注入`），所以 archive 順序不會互相覆蓋。

**建議先 apply 本 change（ticker-navigation-link），再 apply ticker-style-settings。** 理由：
1. 本 change 動協定、Rust、Core 排程器，是較底層且風險較高的修改（跨語言契約、值型別排程器的不變量）；越早做越早暴露問題，style 的 `showTime`、`replayCount`、`scrollSpeed` 熱重載都建立在「seek／rebase 都靠調整 `baseOffset`」之上，順序反過來則 style 要預留日後 seek 的位置。
2. style 的 `replayCount`（`(n/N)` 的 N）、`showTime`（時間粗體的有無）、`showLabel`（帶子可視寬度公式，已含控制列）都以本 change 的行為為基礎；本 change 先做則 style 直接擴充，不必回頭改。
3. 本 change 的外觀常數（控制列寬、連結欄位寬、顏色）放在 `ShellConfig`；style 把「外觀常數來源」改為 `TickerStyle` 時一併搬移即可。反過來則本 change 要把新增的圖層顏色再接進已建好的 `TickerStyle`。
若順序相反：style 先做沒有技術障礙，但本 change 之後須把控制列與迴紋針的顏色接入 `TickerStyle`（建議新增衍生色而非新欄位），且 `viewportWidth` 公式要再加上控制列寬。

## Risks / Trade-offs

- [帶子可視寬度由 470 縮為 370] → 單則長訊息更常被截斷；控制列位置【待確認】；替代方案為加寬面板。
- [mouse-up 在非啟用面板的可靠度未查證] → 人工驗收；失敗改 mouse-down（我方實作問題，必須修）。
- [hover 暫停造成帶子「卡住」的觀感] → `PointerHover` 保險核對；預設整個面板；待使用者看實物。
- [`data-href` 位置是 FastBull 頁面結構，改版會讓 `url` 全部消失] → 降級為無連結，帶子照常運作；無連結時不顯示迴紋針，使用者看到的是「功能消失」而非錯誤；`status` 不會警告。可考慮日後在連續 N 輪皆無 `url` 時發 `status` 警告【待確認，未列入本 change】。
- [向後 seek 需重建圖層] → `add` 冪等；測試以呼叫序列斷言。
- [fixtures 新增使三端測試同時變紅] → tasks 1.1 先紅（參考測試）再綠；其後 Rust、Swift 各自跟進。
- [連結指向第三方網站、FastBull 服務條款尚未逐條閱讀] → 開啟頁面由使用者主動點擊，不是自動請求；服務條款仍【待使用者確認】，不得宣稱已解決。
- [舊版嚴格接收端不相容] → 同一個 `.app` 發行；`v` 不升。

## 待釐清（彙整）

1. 控制列位置（右端 100pt，帶子縮為 370）還是加寬面板？【待確認】
2. 協定 `v` 維持 1 是否可接受？`url` 規則（可見 ASCII、小寫 scheme、上限 2048）是否可接受？【假設】
3. 無 `url` 的訊息：不顯示迴紋針（本案）還是顯示但停用？【假設】
4. 點擊迴紋針後瀏覽器成為前景（本案）還是背景開啟？【假設】
5. hover 暫停範圍與恢復時機（整個面板、立即恢復）。【假設】
6. 切換後暫停 8 秒、閱讀內縮線 24pt。【假設】
7. 邊界：清單第一則按 `<` 無動作；最後一則按 `>` 跳下一輪起點。【假設】
8. `(n/N)` 的清單定義（重播＝一輪最新 N 則；即時＝當前批次，N 含佇列中尚未排入者）。【假設】
9. mouse-up 觸發在非啟用面板上是否可靠。【待確認，需人工】
10. app-shell archive 後須補一個 MODIFIED 修訂 `panel-shell` 的拖曳 requirement；設計文件第 10 節非目標「點擊開啟詳情」已被使用者回饋覆蓋。【待確認／待處理】
11. 解析範圍取側欄 20 則（沿用 `fastbull-connector` 既有待確認）；FastBull 服務條款仍未逐條閱讀。【待使用者確認】
12. 粗體字型 PingFang TC Semibold、迴紋針圖示（`CGPath` 或 SF Symbol）、控制列配色的實際觀感。【需人工目視】
