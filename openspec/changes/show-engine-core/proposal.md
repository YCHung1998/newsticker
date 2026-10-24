## Why

Show engine（Swift App）的核心價值在「何時、以什麼樣式、排在帶子哪個位置」顯示哪一則訊息，這是純邏輯，容易在 timer、模式切換、隱藏／恢復的邊界出錯（參考設計文件第 8 節風險 2、6）。若與 AppKit／渲染混寫，無法做決定性測試。本 change 先建立 SwiftPM 專案骨架與不依賴 AppKit 的 `FastBullTickerCore`，以假時鐘與假 measurer 把行為鎖進自動化測試；後續 `app-shell` 只負責把 Core 的輸出畫出來。

## What Changes

- 新增 SwiftPM 專案：`FastBullTickerCore`（library）＋ 測試 target（swift-testing）＋ `FastBullTicker`（executable，僅空殼，正式內容屬 `app-shell`）。`swift build`／`swift test` 可在命令列執行。
- 新增協定型別（Codable）與單行解碼器，對應 `message-contract` 的 `snapshot`／`items`／`status`／`item`，並以 `protocol/fixtures/` 與 manifest 做契約測試（不複製 fixtures）。
- 新增 `LineBuffer`：0x0A 切行、保留半行、單行上限、超長行丟棄且不終止串流。
- 新增 `TickerScheduler`：注入時鐘、tape 座標模型、REPLAY／LIVE 狀態機、即時佇列上限、隱藏凍結 tape 時間、定期 rebase 的純函數介面。
- 新增版面計算：注入 measurer、以量測寬度截斷加「…」、本機時區 `HH:mm:ss` 時間字串（時區注入）。
- Core 的輸出與渲染方案無關：只輸出每則訊息的 `tapeX`／`width`／樣式類型／文字與時間字串，以及「某 tape 時間下的位移」。

不在範圍：任何 AppKit／渲染／視窗／選單、`FeedClient`／`Process` 管理、Makefile 組裝與簽名（屬 `app-shell`）；渲染方案選擇（屬 `panel-feasibility-spikes` S4）。

## Capabilities

### New Capabilities
- `core-package`: SwiftPM 骨架、部署目標、Swift 6 模式、swift-testing、Core 不依賴 UI 框架。
- `protocol-decoding`: 協定 Codable 型別、單行解碼、錯誤分類，與以 message-contract fixtures 做契約測試。
- `line-buffer`: 位元組串流切行、半行保留、超長行處理、壞行隔離。
- `ticker-scheduler`: tape 座標模型、供料器、REPLAY／LIVE 狀態機、佇列上限、凍結／恢復、rebase。
- `ticker-layout`: 注入式 measurer、量測寬度截斷、時間字串格式與時區注入。

### Modified Capabilities
（無。）

## Impact

- 新增：`Package.swift`、`Sources/FastBullTickerCore/`、`Sources/FastBullTicker/`（空殼）、`Tests/FastBullTickerCoreTests/`（apply 階段才建立）。
- 依賴 `message-contract` 已 apply（需要 `protocol/fixtures/` 與 manifest）。若尚未 apply，契約測試任務不得開始（見 tasks）。
- 不影響 `connect-engine-fastbull`、`panel-feasibility-spikes`。`app-shell` 依賴本 change 的 Core API 與 S4 決定。
- 本 change 的規格階段不建立任何 Swift 程式碼。
