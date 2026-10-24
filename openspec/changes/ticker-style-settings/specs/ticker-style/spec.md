## ADDED Requirements

### Requirement: TickerStyle 結構與欄位
App SHALL 以單一 `Codable`、`Equatable`、`Sendable` 的 `TickerStyle` 結構集中所有可調樣式與行為，位於 `FastBullTickerApp` 目標（僅依賴 Foundation，不依賴 AppKit，使其可純函式測試）。欄位（JSON 鍵為英文 camelCase）：

| 鍵 | 型別 | 預設 | 合法範圍 |
|---|---|---|---|
| `version` | 整數 | `1` | 僅 `1` |
| `cornerRadius` | 數字（pt） | `0` | `0`–`21`（面板高 42 的一半） |
| `fontSize` | 數字（pt） | `16` | `10`–`26` |
| `scrollSpeed` | 數字（px/s） | `90` | `20`–`300` |
| `replayCount` | 整數 | `10` | `3`–`30` |
| `showTime` | 布林 | `true` | — |
| `showLabel` | 布林 | `true` | — |
| `labelText` | 字串 | `即時財經快訊` | 1–16 個 Character |
| `labelBackground` | 色彩 | `#D91A21` | `#RRGGBB` |
| `labelColor` | 色彩 | `#FFFFFF` | `#RRGGBB` |
| `tapeBackground` | 色彩 | `#17171A` | `#RRGGBB` |
| `liveBackground` | 色彩 | `#FFFFFF` | `#RRGGBB` |
| `liveText` | 色彩 | `#000000` | `#RRGGBB` |
| `replayBackground` | 色彩 | `#000000` | `#RRGGBB` |
| `replayText` | 色彩 | `#FFFFFF` | `#RRGGBB` |

`cornerRadius` 預設 0（直角）是為了「不改設定時畫面不變」而選的值，使用者若想要預設就有圓角，需另行決定【假設】。範圍數值（`cornerRadius` 0–21、`fontSize` 10–26、`scrollSpeed` 20–300、`replayCount` 3–30、`labelText` 1–16 字）皆為【假設】，其中 `fontSize` 上限 26 是因面板高度固定 42pt、CJK 行高約為字級 1.45 倍而留邊界；`replayCount` 3–30 來自使用者指定的範圍。`tapeBackground`（訊息之間空隙的底色）、`labelBackground`、`labelColor` 是為了讓預設值能與原型一致而增加的欄位，使用者要求的欄位（圓角、即時／重播的背景色與文字色、字級、速度、`replayCount`、`showTime`、`showLabel`、標籤文字）皆已涵蓋。透明度與位置仍由既有 `Persistence`（UserDefaults）與選單的透明度滑桿管理，不納入 `TickerStyle`。

#### Scenario: 欄位齊全
- **WHEN** 檢查 `TickerStyle` 的編碼輸出
- **THEN** SHALL 含上表所有鍵，且鍵名逐字相同

#### Scenario: 往返
- **WHEN** 將一個 `TickerStyle` 編碼再解碼
- **THEN** SHALL 得到相等的值

#### Scenario: 不依賴 AppKit
- **WHEN** 檢查 `TickerStyle` 所在檔案的 import
- **THEN** SHALL 只有 `Foundation`

### Requirement: 預設值與目前原型一致
`TickerStyle.default` MUST 使不改設定時的畫面與目前原型相同。目前原型的值（取自 `ShellConfig.provisional` 與 `TickerView`／`ItemBitmapRenderer`）：面板 620×42、標籤寬 150pt、標籤文字「即時財經快訊」、字型 PingFang TC 16pt（標籤 15pt Semibold 維持固定，不在本 change 範圍）、捲動速度 90 px/s、重播則數 10、透明度預設 0.9 且下限 0.3、單則左右留白 14pt、即時為白底黑字（`#FFFFFF`／`#000000`）、重播為黑底白字（`#000000`／`#FFFFFF`）、空隙底色 RGB(0.09, 0.09, 0.10)、標籤紅色 RGB(0.85, 0.10, 0.13)。其中面板尺寸、標籤寬度、留白、透明度範圍與預設不屬於 `TickerStyle`，MUST 維持在 `ShellConfig` 且值不變；屬於 `TickerStyle` 的預設值 MUST 逐項等於上述原型值。十六進位色碼與原型 RGB 浮點值的量化誤差 MUST 不超過 1/255【假設：`#17171A` 對應 (0.09, 0.09, 0.10)、`#D91A21` 對應 (0.85, 0.10, 0.13)，浮點值無法以 8 位元精確表示】。tasks 以斷言測試保證：修改任一原型常數或預設值而未同步另一端時測試 MUST 失敗。

#### Scenario: 預設值逐項斷言
- **WHEN** 讀取 `TickerStyle.default`
- **THEN** `fontSize` SHALL 為 16、`scrollSpeed` SHALL 為 90、`replayCount` SHALL 為 10、`showTime` 與 `showLabel` SHALL 為 true、`labelText` SHALL 為「即時財經快訊」、`cornerRadius` SHALL 為 0、四個即時／重播色碼 SHALL 為 `#FFFFFF`、`#000000`、`#000000`、`#FFFFFF`

#### Scenario: 與原型常數一致
- **WHEN** 比較 `TickerStyle.default` 與 `ShellConfig.provisional` 中仍保留的對應原型值（`panelSize`、`labelWidth`、`itemPadding`、`defaultAlpha`、`alphaRange`）及原型的空隙底色與標籤紅色
- **THEN** 差異 SHALL 為 0（色彩 SHALL 不超過 1/255），且 `ShellConfig` 的這些值 SHALL 維持 620×42、150、14、0.9、0.3…1.0

#### Scenario: 預設渲染不變
- **WHEN** 以 `TickerStyle.default` 預渲染一則 `live` 與一則 `replay` 訊息
- **THEN** 背景像素 SHALL 分別為白與黑、文字區含黑與白的前景像素，且寬度 SHALL 與本 change 之前相同

### Requirement: 欄位驗證與夾制
所有欄位 MUST 經過驗證，驗證為純函式，輸入原始值、輸出合法值與警告清單：(1) 數值欄位越界 MUST 夾制到最近的邊界並記錄警告（含鍵名、原值、夾制後的值）；(2) 型別錯誤（例如 `fontSize` 為字串 `"16"`、`showTime` 為數字、`replayCount` 為小數）MUST 視為非法，該欄位使用預設值並記錄警告，不做隱式型別轉換【假設】；(3) `replayCount` 為整數，JSON 中的 `10.0` 視為整數 10，`10.5` 為非法；(4) `labelText` 前後空白修剪後為空則使用預設並警告，超過 16 個 Character（grapheme cluster）則截為前 16 個並警告；(5) 缺少的鍵使用預設值（不警告）；(6) 未知的鍵 MUST 忽略並記錄警告（前向相容）；(7) `version` 缺少視為 1，非整數或大於 1 視為整份檔案無法解讀（見 `style-persistence`）。驗證結果 MUST 永遠是合法的 `TickerStyle`（任何欄位都在合法範圍內）。

#### Scenario: 越界夾制
- **WHEN** `fontSize` 為 5、`scrollSpeed` 為 999、`cornerRadius` 為 −3、`replayCount` 為 100
- **THEN** 結果 SHALL 為 10、300、0、30，且各有一則警告

#### Scenario: 型別錯誤
- **WHEN** `fontSize` 為 `"16"`、`showTime` 為 `1`
- **THEN** 這兩個欄位 SHALL 取預設值（16、true）並各有一則警告，其餘欄位不受影響

#### Scenario: 缺鍵與未知鍵
- **WHEN** JSON 只含 `{"fontSize": 20, "colour": "#FF0000"}`
- **THEN** `fontSize` SHALL 為 20，其餘為預設，`colour` SHALL 被忽略並有警告

#### Scenario: 標籤文字
- **WHEN** `labelText` 為 20 個 Character，或為只含空白
- **THEN** 前者 SHALL 被截為 16 個 Character，後者 SHALL 取預設值，各有警告

#### Scenario: 結果永遠合法
- **WHEN** 以隨機（固定種子）的鍵與值組合餵給驗證函式
- **THEN** 輸出的 `TickerStyle` SHALL 每個欄位都在合法範圍內

### Requirement: 色彩格式與非法色碼
色彩 MUST 以字串 `#RRGGBB`（`#` 加恰 6 個十六進位字元，大小寫皆可）表示，為不透明 sRGB。MUST NOT 接受 3 位數縮寫、8 位數（含 alpha）、顏色名稱、`rgb()` 或不含 `#` 的字串【假設：背景為純色，整條透明度由 window `alphaValue` 控制，故不需要色彩 alpha】。非法色碼 MUST 使該欄位取預設值並記錄警告（含鍵名與原字串）。內部以 0–1 的 sRGB 分量表示，寫回檔案時 MUST 正規化為大寫 `#RRGGBB`。

#### Scenario: 合法色碼
- **WHEN** 輸入 `#ffe45c`
- **THEN** SHALL 解析為 R=255、G=228、B=92，寫回時 SHALL 為 `#FFE45C`

#### Scenario: 非法色碼
- **WHEN** 輸入 `red`、`#FFF`、`#FFE45C80`、`FFE45C` 或 `#GGGGGG`
- **THEN** SHALL 皆視為非法，該欄位取預設值並有警告

### Requirement: 可讀性警告不阻擋
驗證 MUST 計算 `liveText`／`liveBackground`、`replayText`／`replayBackground`、`labelColor`／`labelBackground` 三組的 WCAG 對比度（相對亮度 `L = 0.2126R + 0.7152G + 0.0722B`，R、G、B 為線性化後的 sRGB 分量；對比度 `(L1 + 0.05) / (L2 + 0.05)`，`L1` 為較亮者）。對比度低於 4.5 時 MUST 記錄警告（含組別與數值），但 MUST 照常套用，不夾制、不拒絕【假設：門檻取 WCAG 一般文字 AA 的 4.5；警告只寫日誌，不彈出 UI】。對比度計算為純函式。

#### Scenario: 預設與預設配色不警告
- **WHEN** 驗證預設樣式與選單的三組即時配色預設
- **THEN** SHALL 沒有對比度警告（白底黑字約 21:1、黃底黑字約 16.5:1、綠底白字約 5.3:1）

#### Scenario: 低對比度警告但照用
- **WHEN** `liveBackground` 為 `#FFFF00`、`liveText` 為 `#FFFFFF`（約 1.07:1）
- **THEN** 結果樣式 SHALL 保留這兩個值，並有一則含數值的對比度警告

### Requirement: 外觀常數來源改為 TickerStyle
app-shell（尚未同步到主 specs，與 app-shell 的 `panel-shell`、`ticker-renderer`、`status-menu` 相關）已實作的外觀常數來源 MUST 由 `ShellConfig` 改為 `TickerStyle`：`TickerView`、`ItemBitmapRenderer`、標籤文字、`SchedulerConfig.speed`／`replayCount`／`showTime` 的值一律來自目前生效的 `TickerStyle`。`ShellConfig` 保留與樣式無關的值（level、collectionBehavior、渲染方案旗標、補料計時器種類、紋理上限、幀率上限、面板尺寸、標籤寬度、留白、透明度範圍與預設、位置存檔 debounce、補料間隔、螢幕邊距），其中 `ShellConfig.provisional` 的視窗層級、旗標與渲染方案仍是暫定值，不在本 change 範圍，MUST 不被修改。`ShellConfig` 中已移入 `TickerStyle` 的欄位（`fontSize`、`labelText`、`scrollSpeed`）MUST 從 `ShellConfig` 移除，避免兩處來源。與 `ticker-navigation-link` 相關：若該 change 已 apply，帶子可視寬度公式為「面板寬 − （`showLabel` 為 true 時的標籤寬）− 控制列寬」；若尚未 apply，則為「面板寬 − （`showLabel` 為 true 時的標籤寬）」。

#### Scenario: 單一來源
- **WHEN** 搜尋 `Sources/` 中對 `fontSize`、`labelText`、`scrollSpeed` 的讀取
- **THEN** SHALL 只出現在 `TickerStyle` 及由它取值的地方，`ShellConfig` SHALL 不再定義這三個欄位

#### Scenario: 暫定值不被修改
- **WHEN** 比較本 change 前後的 `ShellConfig.provisional` 的 level、collectionBehavior、renderer、feedTimer
- **THEN** SHALL 逐項相同

#### Scenario: 隱藏標籤時的可視寬度
- **WHEN** `showLabel` 為 false
- **THEN** 排程器的 `viewportWidth` SHALL 增加標籤寬度（150），帶子 SHALL 從面板左緣起顯示

### Requirement: 樣式變更的套用語意
樣式變更（來自設定檔熱重載或選單）MUST 依下列規則套用，且不得重建面板、不得造成訊息位置跳動：(1) 立即生效且影響畫面上已有的訊息：背景色與文字色（已排入訊息的 bitmap 就地重繪，寬度與位置不變）、`tapeBackground`、標籤的顯示與顏色與文字、`cornerRadius`、`scrollSpeed`（經排程器 `reconfigure`，視覺位置連續）；(2) 只影響變更之後才排入的訊息：`fontSize`、`showTime`（會改變訊息寬度，已排入的訊息維持舊樣式直到捲出）【假設】；(3) 影響之後的重播取料：`replayCount`。`showLabel` 改變時帶子可視寬度改變，已排入訊息位置不動，之後補料依新寬度。圓角以內容視圖的圖層 `cornerRadius` 搭配 `masksToBounds` 裁切（含標籤與訊息），`cornerRadius` MUST 夾制在 `[0, 面板高 ÷ 2]`；窗口背景維持透明、無陰影、無毛玻璃。圓角不改變面板的點擊與拖曳範圍。

#### Scenario: 改顏色不跳動
- **WHEN** 帶子上有 5 則訊息時，將 `liveBackground` 改為 `#FFE45C`
- **THEN** 5 則訊息的位置與寬度 SHALL 不變，其中 `live` 樣式者的 bitmap 背景 SHALL 重繪為新色

#### Scenario: 改字級只影響新訊息
- **WHEN** 將 `fontSize` 由 16 改為 20
- **THEN** 已排入訊息的寬度 SHALL 不變；之後排入的訊息 SHALL 以 20pt 量測與繪製，且與前一則的間距 SHALL 仍為 `gap`

#### Scenario: 改速度連續
- **WHEN** 將 `scrollSpeed` 由 90 改為 150
- **THEN** 所有訊息的視覺位置 SHALL 在變更瞬間不變，之後以 150 px/s 前進

#### Scenario: 圓角夾制
- **WHEN** `cornerRadius` 為 100
- **THEN** 生效值 SHALL 為 21

### Requirement: 測試策略與禁止項目
驗證、夾制、色碼解析、對比度計算、預設值斷言 MUST 為純函式並以單元測試驗證，使用固定輸入與固定種子。自動測試 MUST NOT 開啟真實視窗（不呼叫 `orderFront`、`makeKeyAndOrderFront`），MUST NOT 啟用 App，MUST NOT 讀寫使用者真實的 `~/Library/Application Support/FastBullTicker/style.json`（一律使用暫存目錄）。圓角、配色與字級的實際觀感為【需人工目視】，tasks 必須逐項標明。

#### Scenario: 測試不碰真實設定
- **WHEN** 執行本 change 新增的所有測試
- **THEN** 測試 SHALL 只讀寫暫存目錄，SHALL 不顯示視窗，且測試前後使用者的 `style.json`（若存在）SHALL 不變
