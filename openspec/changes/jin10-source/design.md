## Context

`exp/jin10-cold-start`（單一 commit，+676 行，僅動 `ticker-connect/`）已有連接器、fixture 與 2 個測試檔，但**未經審查、測試未跑**。API 回傳 `data[].data.content`（`【標題】本文`，含 HTML）、`important`（0/1）、`extras.ad`、`data.source_link`、`time`（無時區）。協定 v1 的 `item` 目前只有 `source/id/published_at_ms/text/url`，且 spec 明文禁止「重要」旗標。Time 粗體已存在（`ItemBitmap`）。

## Goals / Non-Goals

**Goals:** 看得到金十快訊；時間／標題粗體；重要訊息標題紅字；廣告不出現；fastbull 行為不變。
**Non-Goals:** 簡轉繁（內容維持簡體原文）；VIP／PLUS 內容；圖片、語音、日曆等其他頻道；來源切換 UI；同時顯示兩個來源。

## Decisions

1. **協定加選填 `title`、`important`，不改 `v`。** 替代方案 A：不改協定，Swift 端用正規式把 `【…】` 粗體——但「重要」無處表達。替代方案 B：`v: 2`——目前無外部消費者，成本不成比例。代價：新 helper 搭舊 App 會丟訊息，需同版（同 `url` 當時的決定）。
2. **`title` 與 `text` 不重複。** 連接器負責拆；只有標題沒本文時不輸出 `title`，避免 `text` 為空而違反協定。
3. **`important` 只在為 true 時輸出。** 減少 fastbull 與一般訊息的線上位元組，也讓 `false` 與缺少語意一致。
4. **佈局沿用 Core 的字串＋區段模式。** 時間粗體已用「前 N 字元」；擴充為粗體長度 = 時間＋標題（title 後的空白一般字重）；重要色以單獨區段表達。具體資料結構於實作時按 Core 現況決定。
5. **連接器以實驗分支為起點，但必須重驗**：跑測試、檢視 fixture 是否為真實回應、實測一次真站、再審查 `x-app-id` 標頭（網站公開 bundle 的常數）。

## Risks / Trade-offs

- [API 是網站前端私有端點，可能隨時改版或擋 UA] → 解析失敗走既有「0 則＝錯誤」＋退避；README 標註為非官方。
- [條款／版權未讀，與金十無關係] → 低頻、只顯示文字並連回原文；回報中標註風險交人類裁決。
- [UTC+8 為推定] → 以 fixture 的 `time` 與網站畫面 21:20:34 對照實測一次。
- [簡體字] → v1 不轉換；標籤文字可用 `style.json` 的 `labelText` 改成「金十數據」。
- [推翻 2026-10-24 決定] → 在此提案明列，未經確認不 apply。
- [此 change 動到 `ADDING_A_SOURCE.md` 的「不能動」清單] → 屬協定演進，不是單純新增來源；完成後更新該文件的欄位表。

## Migration Plan

同一 `.app` 內 helper 與 App 同版發行；回滾 = revert 該 change 分支。

## Open Questions

- 重要訊息要紅色標題，還是整行紅？（暫定標題紅，依截圖。）
- 是否要在 App 內加選單切換來源？（暫定不做，用環境變數。）
