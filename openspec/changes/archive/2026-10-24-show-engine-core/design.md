## Context

來源：設計文件第 5.1、5.3、3、6、9 節與 `TASKS-feed-and-modes.md` 第 4 節（A1–A5，設計文件 5.1 補 A6–A8）。依賴 `message-contract`（協定型別與 fixtures）。`panel-feasibility-spikes` S4 尚未決定渲染方案，所以 Core 的 API 不得預設任何一種。工具鏈已實測：macOS 26.5.1、Swift 6.3.3、Xcode 26.6。

## Goals / Non-Goals

**Goals:**
- 把「排什麼、排在哪、何時排」變成決定性純邏輯，以假時鐘與假 measurer 測試。
- Core 的輸出只有 `tapeX`／`width`／樣式／時間字串／文字，加上「某 tape 時間的位移」。
- 契約測試直接吃 `protocol/fixtures/`，與 Rust 端對齊。

**Non-Goals:**
- 不做 AppKit、渲染、視窗、選單、`FeedClient`、Makefile、簽名。
- 不決定渲染方案；不指定捲動速度數值（目測調整，屬 apply 或 `app-shell` 階段）。

## Decisions

1. **tape 座標加純函數位移**。`visualX = tapeX − scrollOffset(tapeTime)`，`scrollOffset = baseOffset + speed × tapeTime`。替代：逐幀累加位置。選前者因為凍結／恢復／rebase 都只是改 `tapeTime` 或對 `baseOffset` 與 `tapeX` 同加 delta，沒有累積誤差，且同時相容 displayLink（每幀查位移）與線性 `CABasicAnimation`（以 `speed` 與起點建動畫）。
2. **補料位置固定為「尾端 + gap」**，而非「補料當下的右緣」。使 tick 頻率不影響版面，測試可決定性重現。代價：tick 太晚時訊息可能已部分進入視窗（由 `app-shell` 保證 tick 夠密；Core 不處理）。
3. **供料器 pull 模式**：`tick()` 讀時鐘、更新 tape 時間、補料並回傳新排入的訊息。替代：計時器推送。選前者因為 Core 不擁有計時器（選單展開時 timer 斷料問題屬 S3 與 `app-shell`）。
4. **「佇列播完」＝佇列被取空**（最後一則即時訊息排入帶子）才回 REPLAY。替代：等最後一則捲出視窗。選前者因為尾端接續才符合「接在尾端已排入最後一則後面」且避免空白帶；列為【假設】（使用者 2026-10-24 維持暫定）。
5. **歷史獨立於即時佇列**。即時訊息同時進歷史，故佇列溢出丟最舊（A7）不損失重播資料。去重鍵 `source`＋`id`。
6. **時間與量測注入**：時鐘、時區、measurer 皆為協定／閉包注入，禁止 Core 讀系統狀態。
7. **解碼嚴格性集中單一位置**：message-contract 的決定（額外欄位、空 items、空 text、順序、1MB 位元組數；2026-10-24 已決定）在 Swift 端集中於 `ProtocolRules`，契約測試以 manifest 為唯一預期。
8. **Package.swift 放倉庫根目錄**【假設】，使測試以相對路徑定位 `protocol/fixtures/`；不複製 fixtures。
9. **Core 內部用 Double**，渲染端自行轉 Float32；rebase 閾值判斷以純函數提供。

## Risks / Trade-offs

- [message-contract 未決項導致 Swift 行為日後翻轉] → 單點常數加 manifest 驅動測試；tasks 要求在回報中列出依賴項。
- [message-contract 尚未 apply，fixtures 不存在] → 契約測試 task 以其 apply 為前提，缺檔時測試失敗而非略過。
- [「佇列播完」詮釋錯誤] → 列為假設；狀態機判定集中在一個函式，易改。
- [LIVE 是否顯示時間] → 已決定（2026-10-24）顯示，LIVE 與 REPLAY 皆以含時間的顯示字串量測。
- [最大訊息寬度來源未定] → 做成注入設定，不寫死。

## Open Questions（2026-10-24 決定紀錄與剩餘假設）

已決定（2026-10-24，與 `protocol/` 已實作內容一致）：
- 空 `items` 非法；順序違規拒絕，原因類別 `order`（相鄰相等合法）；`text` 不得為空；額外欄位不允許；`status.message` 在 `ok` 時可為空；單行上限 1,048,576 位元組（以位元組計，恰為上限合法）；空行 → `not_json`；非 UTF-8 → `not_json`；`v`=1；manifest 格式以 `protocol/fixtures/manifest.json` 為準。
- 整則所有 item 合法才接受，任一非法整則非法；發送端（Rust helper）負責先過濾不合格 item 並另發 `status`（`state: error`），Core 不處理混有非法 item 的容錯。
- 即時訊息也顯示時間（LIVE 與 REPLAY 皆含 `HH:mm:ss`，時區仍為【假設 A4】）。
- 最大訊息寬度為注入參數 `maxItemWidth`（預設 600 為【假設】）。
- 中途 `snapshot` 視為重設基準（取代歷史，不觸發 LIVE、不清佇列與帶子）；snapshot 之前收到 `items` 忽略並回報錯誤事件（細節為【假設】）。

仍為【假設】（使用者維持暫定，未升級）：
- 「佇列播完」＝供料器補料時即時佇列已空；EOF 殘留半行不輸出；Core 以 `source`＋`id` 防禦性去重；`Package.swift` 放倉庫根目錄；macOS 14 最低部署目標；Swift 6 語言模式；`maxItemWidth` 預設值；`historyLimit`（200）；超長行事件於 0x0A 到達時輸出；A1–A8 維持原樣標示。
