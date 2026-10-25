## Why

使用者要把金十數據（https://www.jin10.com/ 即時快訊）接進跑馬燈，並希望畫面像金十網站：時間粗體、重要訊息的標題粗體突顯。實驗分支 `exp/jin10-cold-start`（冷啟動 agent 照 `docs/ADDING_A_SOURCE.md` 做出的連接器，+676 行，與 `main` 無衝突，**但測試未跑過、未經人工審查**）已有雛形；「標題粗體／重要」現有協定做不到，因為 v1 明文禁止「重要」旗標。

## What Changes

- 新增 Rust 連接器 `jin10`（API：`flash-api.jin10.com/get_flash_list`）：以實驗分支為基礎審查後納入；略過廣告（`extras.ad`）與 PLUS 鎖定／純圖片快訊；`source_link` 當 `url`；時間以北京時間 UTC+8 解讀；`data.important` 轉為 `important`；內文開頭的 `【標題】` 拆出為 `title`。
- **協定新增兩個選填欄位**：`item.title`（非空字串）、`item.important`（布林）。`v` 仍為 `1`。**推翻「v1 不含重要旗標」（2026-10-24 決定），需你確認。**
- Swift Core 解碼 `title`／`important`；渲染：`HH:mm:ss` 粗體（已有）→ `title` 粗體 → 本文；重要訊息的標題以紅色顯示（對照你的截圖，顏色為【假設】）。
- 選擇來源沿用既有機制（環境變數 `--source jin10`），不新增設定 UI。

## Capabilities

### New Capabilities
- `jin10-connector`: 金十數據連接器的抓取、解析、過濾、去重鍵與時間規則。

### Modified Capabilities
- `message-protocol`: `item` 新增選填 `title`、`important`，移除「不得含重要旗標」。
- `protocol-decoding`: Swift 型別解碼 `title`、`important`。
- `ticker-layout`: 顯示字串新增標題粗體與重要訊息配色，量測與繪製一致。

## Impact

- 程式：`ticker-connect/src/{jin10,sources,lib,model,protocol}.rs`（`model`／`protocol`／emitter 要加欄位，違反 ADDING_A_SOURCE 的「不動」清單，因此本 change 不是單純新增來源）、`protocol/schema/item.schema.json`、`protocol/fixtures`、`Sources/FastBullTickerCore`（解碼、佈局）、`Sources/FastBullTickerApp`（`ItemBitmap` 粗體／紅字）。
- 相容：舊 App 搭新 helper 會因 `additionalProperties:false` 丟掉含新欄位的訊息，兩端須同版（同一 `.app`，與 `url` 當時相同的取捨）。fastbull 連接器不輸出新欄位，行為不變。
- 外部：金十網站條款／版權未逐條閱讀；低頻輪詢（≥10 秒），僅顯示文字並連回原文。
