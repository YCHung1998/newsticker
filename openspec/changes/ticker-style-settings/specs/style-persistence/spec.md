## ADDED Requirements

### Requirement: 樣式檔位置與格式
樣式 MUST 持久化於 `~/Library/Application Support/FastBullTicker/style.json`（與 app-shell 的 `helper.pid`、`app.log` 同目錄）。檔案 MUST 為 UTF-8 的 JSON 物件，鍵與值如 `ticker-style` 所定義；範例：

```json
{
  "version": 1,
  "cornerRadius": 0,
  "fontSize": 16,
  "scrollSpeed": 90,
  "replayCount": 10,
  "showTime": true,
  "showLabel": true,
  "labelText": "即時財經快訊",
  "labelBackground": "#D91A21",
  "labelColor": "#FFFFFF",
  "tapeBackground": "#17171A",
  "liveBackground": "#FFFFFF",
  "liveText": "#000000",
  "replayBackground": "#000000",
  "replayText": "#FFFFFF"
}
```

檔案路徑 MUST 可注入（測試用暫存目錄）；正式啟動時可由環境變數 `FASTBULL_TICKER_STYLE`（完整檔案路徑）覆寫【假設：比照 app-shell 的 `FASTBULL_TICKER_LOG`，名稱為本 change 自訂】。檔案大小超過 64KB MUST 視為無法讀取【假設】。App MUST NOT 要求任何額外權限（不需輔助使用、螢幕錄製、完整磁碟存取），MUST NOT 使用 sudo。

#### Scenario: 預設路徑
- **WHEN** 未設定環境變數
- **THEN** 樣式檔路徑 SHALL 為 `~/Library/Application Support/FastBullTicker/style.json`

#### Scenario: 路徑覆寫
- **WHEN** 環境變數 `FASTBULL_TICKER_STYLE` 指向暫存檔
- **THEN** 讀寫 SHALL 只發生在該檔案

#### Scenario: 過大的檔案
- **WHEN** 檔案大於 64KB
- **THEN** SHALL 視為無法解讀（見「格式錯誤時保留舊值」），不讀入全部內容

### Requirement: 啟動載入
啟動時 MUST 載入樣式檔：(1) 檔案不存在 → 使用 `TickerStyle.default`，MUST NOT 自動建立檔案（建立發生在選單寫回或「開啟樣式設定檔」時）；(2) 檔案存在且可解讀 → 套用驗證後的樣式（越界夾制並記錄警告）；(3) 檔案存在但無法解讀（語法錯誤、不是物件、`version` 非 1、過大）→ 使用預設樣式、記錄錯誤日誌，並記住「設定檔有誤」狀態供選單顯示；MUST NOT 修改或刪除該檔案。啟動載入 MUST NOT 阻塞主執行緒超過一次小檔案讀取。

#### Scenario: 無檔案
- **WHEN** 樣式檔不存在
- **THEN** 生效樣式 SHALL 等於預設，且磁碟上 SHALL 仍沒有該檔案

#### Scenario: 損壞的檔案
- **WHEN** 樣式檔內容為 `{ "fontSize": `
- **THEN** 生效樣式 SHALL 等於預設，日誌 SHALL 含錯誤，檔案內容 SHALL 不變，「設定檔有誤」狀態 SHALL 為真

#### Scenario: 部分欄位越界
- **WHEN** 樣式檔含 `"fontSize": 99`
- **THEN** 生效 `fontSize` SHALL 為 26，日誌 SHALL 有夾制警告，其餘欄位正常

### Requirement: 熱重載
App MUST 監看樣式檔所在目錄的變動，變動後經 debounce（暫定 0.3 秒【假設】）重新讀取並套用。監看目錄而非單一檔案描述元，因為多數編輯器以「寫暫存檔再改名取代」儲存，會使對原檔案的監看失效。監看機制 MUST 以可注入的協定（`StyleFileWatching`：`start(directory:onChange:)`、`stop()`）實作，測試使用可手動觸發的假監看器；正式實作使用 `DispatchSource` 檔案系統事件，MUST NOT 使用輪詢以外需要權限的機制。重新讀取的位元組與上次讀入相同，或解析後的樣式與目前生效樣式相等時 MUST 不重新套用（避免閃動與自寫入迴圈）。檔案被刪除時 MUST 保留目前生效樣式並記錄日誌（不視為重設為預設）【假設】。熱重載的回呼 MUST 在主執行緒套用，且不得阻塞渲染。

#### Scenario: 改檔後套用
- **WHEN** 假監看器在樣式檔改為 `fontSize: 20` 後觸發並經過 debounce
- **THEN** 生效樣式的 `fontSize` SHALL 為 20，並通知套用端一次

#### Scenario: 連續觸發合併
- **WHEN** 50 次觸發在 0.1 秒內發生
- **THEN** SHALL 只讀取並套用一次

#### Scenario: 內容相同不重套
- **WHEN** 觸發後讀到的位元組與上次相同
- **THEN** SHALL 不通知套用端

#### Scenario: 編輯器取代式儲存
- **WHEN** 檔案以「新檔改名覆蓋」方式被更新（目錄事件，原檔案描述元失效）
- **THEN** SHALL 仍偵測到變動並套用新內容

#### Scenario: 檔案被刪除
- **WHEN** 樣式檔在執行中被刪除
- **THEN** 生效樣式 SHALL 維持不變，日誌 SHALL 記錄

### Requirement: 格式錯誤時保留舊值並記錄日誌
熱重載讀到「整份無法解讀」的內容（JSON 語法錯誤、頂層不是物件、`version` 不是整數 1、過大、非 UTF-8）時，MUST 保留目前生效的樣式不變、記錄含原因的錯誤日誌，並記住「設定檔有誤」狀態（下一次成功載入時清除）。內容可解讀但個別欄位非法時，不屬整份失敗：依 `ticker-style` 的驗證規則（越界夾制、型別錯誤與非法色碼取該欄位預設值）產生合法樣式並套用，警告寫入日誌【假設：欄位層級的非法值取預設值而非「保留舊值」，使驗證為不依賴先前狀態的純函式】。日誌 MUST 走 App 既有的 `AppLog`（行首以 `style:` 標示）。

#### Scenario: 熱重載遇到語法錯誤
- **WHEN** 生效樣式 `fontSize` 為 20，使用者把檔案存成不合法 JSON
- **THEN** 生效 `fontSize` SHALL 仍為 20，日誌 SHALL 有錯誤，「設定檔有誤」狀態 SHALL 為真，不通知套用端

#### Scenario: 修好後恢復
- **WHEN** 使用者隨後把檔案修正為合法 JSON
- **THEN** SHALL 套用新內容，「設定檔有誤」狀態 SHALL 清除

#### Scenario: 欄位層級錯誤
- **WHEN** 檔案內 `liveBackground` 為 `blue`
- **THEN** `liveBackground` SHALL 取預設值 `#FFFFFF`，其餘欄位 SHALL 照檔案套用，日誌 SHALL 有警告

### Requirement: 寫回與備份
選單操作 MUST 修改生效樣式後寫回樣式檔。寫回 MUST：(1) 先套用到畫面，再經 debounce（暫定 0.5 秒【假設】，與位置存檔一致）合併連續變更（例如拖動滑桿）；(2) 寫入同目錄暫存檔再原子取代，MUST NOT 留下半寫入的檔案；(3) 輸出為正規化的 JSON（鍵排序、縮排、色碼大寫、結尾換行）；(4) 若磁碟上現有檔案「無法解讀」或「含未知鍵」，MUST 先把原檔複製為同目錄的 `style.json.bak`（覆蓋舊的 `.bak`）再寫入，避免覆蓋使用者手寫中的內容【假設】；(5) 目錄不存在時 MUST 建立；(6) 寫入失敗（磁碟滿、權限）MUST 記錄日誌並保留記憶體中的樣式，不得崩潰。寫回後由此引起的目錄事件 MUST 被辨識為自寫入（比對寫入內容的雜湊）而不重新套用。App 不寫入使用者未改動的狀態：僅載入與熱重載 MUST NOT 寫檔。

#### Scenario: 滑桿連續拖動
- **WHEN** 50 次 `cornerRadius` 變更在 0.1 秒內發生
- **THEN** 畫面端 SHALL 收到 50 次套用，磁碟 SHALL 只寫入最後一個值一次

#### Scenario: 原子寫入
- **WHEN** 寫回進行中
- **THEN** 任何時刻讀到的 `style.json` SHALL 是舊的完整內容或新的完整內容（測試以注入的檔案系統斷言先寫暫存檔再取代）

#### Scenario: 備份損壞的原檔
- **WHEN** 磁碟上的 `style.json` 是無法解讀的內容，使用者在選單改字級
- **THEN** SHALL 先產生內容相同的 `style.json.bak`，再寫入新的合法 `style.json`

#### Scenario: 自寫入不重套
- **WHEN** 寫回完成後假監看器觸發
- **THEN** SHALL 不通知套用端

#### Scenario: 載入不寫檔
- **WHEN** 啟動並載入一個含越界值的樣式檔
- **THEN** 檔案 SHALL 不被改寫

#### Scenario: 寫入失敗
- **WHEN** 目標目錄不可寫
- **THEN** SHALL 記錄日誌，生效樣式 SHALL 保持，App SHALL 繼續運作

### Requirement: 測試策略
載入、解析、驗證、熱重載、寫回、備份 MUST 全部使用暫存目錄與假監看器、假時鐘（重用 app-shell 的 `FeedClock` 測試替身）測試，MUST NOT 讀寫使用者真實樣式檔，MUST NOT 依賴真實檔案系統事件的時序，MUST NOT 開啟視窗。正式 `DispatchSource` 監看器的實際行為（含 TextEdit、vim 等編輯器的儲存方式）為【需人工】驗證。

#### Scenario: 假監看器
- **WHEN** 熱重載測試執行
- **THEN** 監看器 SHALL 為測試注入的假物件，觸發 SHALL 由測試明確呼叫
