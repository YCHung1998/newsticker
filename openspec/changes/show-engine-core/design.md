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
4. **「佇列播完」＝佇列被取空**（最後一則即時訊息排入帶子）才回 REPLAY。替代：等最後一則捲出視窗。選前者因為尾端接續才符合「接在尾端已排入最後一則後面」且避免空白帶；列為【待確認】。
5. **歷史獨立於即時佇列**。即時訊息同時進歷史，故佇列溢出丟最舊（A7）不損失重播資料。去重鍵 `source`＋`id`。
6. **時間與量測注入**：時鐘、時區、measurer 皆為協定／閉包注入，禁止 Core 讀系統狀態。
7. **解碼嚴格性集中單一位置**：message-contract 的未決項（額外欄位、空 items、空 text、順序、1MB 位元組數）在 Swift 端各只有一個常數／開關，契約測試以 manifest 為唯一預期，確認後單點翻轉。
8. **Package.swift 放倉庫根目錄**【假設】，使測試以相對路徑定位 `protocol/fixtures/`；不複製 fixtures。
9. **Core 內部用 Double**，渲染端自行轉 Float32；rebase 閾值判斷以純函數提供。

## Risks / Trade-offs

- [message-contract 未決項導致 Swift 行為日後翻轉] → 單點常數加 manifest 驅動測試；tasks 要求在回報中列出依賴項。
- [message-contract 尚未 apply，fixtures 不存在] → 契約測試 task 以其 apply 為前提，缺檔時測試失敗而非略過。
- [「佇列播完」詮釋錯誤] → 列待確認；狀態機判定集中在一個函式，易改。
- [LIVE 是否顯示時間未定，影響量測寬度] → Core 以含時間量測，列待確認；若最終不顯示時間，需調整顯示字串組裝並更新測試。
- [最大訊息寬度來源未定] → 做成注入設定，不寫死。

## Open Questions（待釐清）

與 `message-contract` 未決項有關（Swift 解碼行為依賴，不在此拍板）：
- 空 `items` 是否合法（暫定非法）。
- 順序違規（snapshot 非新到舊／items 非舊到新）是拒絕、警告或不檢查；是否有 `order` 原因類別。
- 發送端遇不合格 item 的警告 `status` 之 `state` 值（Swift 端只能接受 `ok`／`error`）。
- `text` 是否可為空字串。
- 「1MB」精確位元組數（暫定 1,048,576，以位元組計）。
- 額外欄位是否允許（暫定不允許）。
- 空行與 EOF 殘留半行的處置；非 UTF-8 的原因類別；manifest 欄位名稱與程式產生樣本的描述方式。

本 change 自身：
- 最大訊息寬度的數值／來源；LIVE 是否顯示時間；「佇列播完」詮釋；中途 `snapshot` 與 snapshot 前 `items` 的處置；去重；Package.swift 位置；macOS 14 最低版本（使用者待確認）；A1–A8 皆為【假設】，使用者尚未逐條確認。
