## Context

來源選擇現在只有 `FeedClientConfig.sourceID(environment:)` 讀 `NEWSTICKER_SOURCE`，`AppDelegate` 啟動時組 `helperArguments(pollIntervalSeconds:source:)`。輪詢間隔變更已有「計畫性重啟 helper」機制（`StyleApplier.onPollIntervalChange` → `feed.reconfigure(arguments:)`）。helper 已有 `--list-sources`。排程器的 `snapshot` 只取代歷史，不清佇列與帶子。使用者要：選單列點一下切換、清單檔記錄來源與顯示名稱、即時切換，且選項必須對應真的有連接器的來源。

## Goals / Non-Goals

**Goals:** 不用終端機就能切換；清單檔人看得懂、可手改；切換不混訊息、不殘留 helper；無連接器的來源不會被選到。
**Non-Goals:** 貼網址自動產生連接器（每個網站仍需 Rust 連接器；`ADDING_A_SOURCE.md` 流程不變）；同時顯示多個來源；設定面板（齒輪）裡的來源選項；來源清單的熱重載監看（只在開選單時重讀）；修 `helper.pid` 共用問題。

## Decisions

1. **獨立檔案 `sources.json`，不併進 `style.json`。** 來源是「資料」、樣式是「外觀」，且 `style.json` 寫回會丟未知鍵；分開避免互相覆蓋。替代：`style.json` 加 `source` 欄位——被否決。
2. **可用來源以 `ticker-connect --list-sources` 為準。** 單一事實來源，新增連接器後不用改 Swift；失敗時退回只有 fastbull。替代：Swift 內硬編碼清單——會和 Rust 登錄表漂移。
3. **選單開啟時才重讀檔案**（`NSMenuDelegate.menuNeedsUpdate`）而非檔案監看：少一套 watcher，足夠「改完檔點選單就看到」。
4. **切換 = 寫檔 → 重啟 helper → `scheduler.reset()` → 清畫面圖層 → 套用標籤**，並用「世代編號」丟棄舊 helper 在切換後才送達的訊息（`FeedClient` 已有 `gen`）。替代：重啟整個 App——畫面閃、位置還原，被使用者選項否決。
5. **標籤：來源 `label` 優先，不寫 `style.json`。** 替代：切換時改寫 `labelText`——會覆蓋使用者自訂。代價：使用者若想自訂金十標籤，要改 `sources.json` 的 `label`，不是 `style.json`。
6. **環境變數優先且不寫檔**：保留開發／測試用法，也避免偶然的環境變數永久改掉使用者的選擇。

## Risks / Trade-offs

- [切換瞬間舊 helper 的訊息混入] → 世代丟棄（Decision 4）＋測試。
- [`--list-sources` 啟動多一次行程] → 約毫秒級、逾時 5 秒、失敗退回 fastbull。
- [停用項目的原因（尚無連接器）使用者看不懂] → 選單文字直接寫明，並在 README 說明如何新增連接器。
- [`sources.json` 被改壞] → 容錯＋備份（比照 `style.json`）。
- [兩個實例共用 `helper.pid`] → 既有問題，不在範圍。

## Migration Plan

沒有檔案的既有使用者：首次啟動自動建立，預設 fastbull，行為不變。回滾 = revert 該 change 分支；`sources.json` 無害留下。

## Open Questions

- 來源 `label` 想不想也能在選單裡改？（暫定不做，改檔。）
- 預設清單要不要把金十放在 FastBull 前面？（暫定 FastBull 在前。）
