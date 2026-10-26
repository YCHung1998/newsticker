## Why

現在換資料來源（FastBull ↔ 金十）只能在終端機用環境變數 `NEWSTICKER_SOURCE=jin10 …/FastBullTicker &` 啟動，而且標籤文字要另外手改 `style.json`；使用者覺得不順、不想開 code 或終端機。要能「點一下就切換」，並把可用來源記在一個使用者看得懂的檔案裡。

## What Changes

- 新增來源清單檔 `~/Library/Application Support/FastBullTicker/sources.json`：每筆有 `id`、顯示名稱 `name`、選填標籤文字 `label`；另記錄上次選的 `selected`。首次啟動檔案不存在時自動建立（含 fastbull、jin10 兩筆）。
- 選單列新增「來源」子選單：列出清單中的來源，打勾目前使用的，點一下**即時切換**（重啟抓取程式、清空舊來源的訊息、換標籤），不必開終端機，用 Finder 雙擊 App 也能用；另有「開啟來源設定檔…」。
- **只有真的有連接器的來源才能選**：App 以 helper 的 `--list-sources` 為準；清單裡有但 helper 不認得的 id 會顯示為停用（「尚無連接器」），不會被選到、也不會讓 helper 反覆崩潰重啟。
- `NEWSTICKER_SOURCE` 環境變數保留，優先於檔案（僅本次執行，不寫檔），維持既有用法與測試。
- Core 排程器新增「重設」操作，切換來源時清掉舊來源的歷史、佇列與帶子，避免兩個來源的訊息混在一起。
- 不改協定、不改 Rust。

## Capabilities

### New Capabilities
- `source-registry-file`: `sources.json` 的格式、預設內容、驗證與容錯。
- `source-switching`: 選單列來源切換的行為（有效來源、即時切換、標籤、環境變數優先）。

### Modified Capabilities
- `ticker-scheduler`: 新增「為切換來源而重設」的需求（ADDED）。

## Impact

- 程式：`Sources/FastBullTickerApp/`（新 `SourceRegistry`、`StatusMenu` 加子選單、`AppDelegate` 切換流程、`FeedClient` 重啟參數）、`Sources/FastBullTickerCore/TickerScheduler.swift`（`reset`）、`TickerView`（清空圖層）。
- 檔案：新增使用者檔案 `sources.json`（App 自動建立，不放進 repo）。
- 相容：未建立檔案、未設環境變數的既有使用者，預設仍是 fastbull，行為不變。
- 風險：切換瞬間的狀態（舊 helper 尚未結束就來新訊息）需丟棄；兩個實例共用 `helper.pid` 的既有問題**不在本 change 範圍**。
