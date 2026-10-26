## 1. 清單檔（Core 純邏輯，先紅後綠）

- [x] 1.1 `SourceRegistry` 型別與解析：欄位規則、重複 id、單筆非法略過、未知鍵警告；單元測試
- [x] 1.2 預設內容、原子寫入、損毀備份、唯讀降級；測試（暫存目錄）
- [x] 1.3 `selected` 規則（記住、指向不存在退回 fastbull）；測試

## 2. 可用來源與排程器重設

- [x] 2.1 `--list-sources` 取得器（逾時 5 秒、失敗退回 fastbull）；以假 helper 腳本測試
- [x] 2.2 `TickerScheduler.reset()`（歷史、佇列、帶子、閱讀位置、模式；`seq` 單調）；測試含 items-before-snapshot
- [x] 2.3 `TickerView`／driver 清空圖層與渲染快取；測試

## 3. 切換流程與選單

- [x] 3.1 `StatusMenu` 加「來源」子選單（打勾、停用「尚無連接器」、開啟來源設定檔…）、開選單時重讀；選單模型單元測試
- [x] 3.2 `AppDelegate` 切換流程：寫檔、重啟 helper（保留輪詢間隔）、reset、丟棄舊世代訊息、環境變數優先且不寫檔；測試
- [x] 3.3 標籤隨來源（`label` 優先，不寫 `style.json`）；測試

## 4. 整合與文件

- [ ] 4.1 真機啟動驗證（`FASTBULL_TICKER_ALLOW_MULTIPLE` 隔離）：用 Finder 風格的 `open` 啟動、切換兩個來源、日誌與截圖證據
- [ ] 4.2 README（快速開始改為「選單列切換」、`sources.json` 說明、如何新增來源）與 `CLAUDE.md` 若需要
- [ ] 4.3 `swift test`、`cargo test`、`openspec validate --all --strict` 全綠
