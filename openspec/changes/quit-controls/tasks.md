## 1. 命中測試與路由（純邏輯，先紅後綠）

- [ ] 1.1 `HitGeometry.quitSlotWidth`（預設 0）與 `HitTarget.quit`；優先序與邊界（半開區間、與迴紋針重疊時 ✕ 優先）；單元測試
- [ ] 1.2 `NavigationInputRouter.onQuit`：mouse-up 才觸發、按下後移開取消、右鍵不觸發、點穿（停用）不觸發；單元測試

## 2. 畫面與設定面板

- [ ] 2.1 `ShellConfig.quitSlotWidth = 28` 並接入 `hitGeometry`；`TickerView` 的 ✕ 圖層（疊加、hover 才顯示、點穿時隱藏、不改尺寸）；離屏測試
- [ ] 2.2 設定面板新指令 `.quitApp` 與「結束程式」按鈕（在「關閉」之前）；模型與控制器測試，「關閉」行為不變

## 3. 統一結束流程

- [ ] 3.1 `requestQuit()`：先隱藏帶子與設定面板、再 `terminate`、可重入；✕、設定面板、選單列三個入口接上；注入式測試（順序、重入、三入口等價）
- [ ] 3.2 整合測試：以假 helper 走完整結束，確認 App 與 helper 都消失、不殘留

## 4. 整合與文件

- [ ] 4.1 真機驗證（`FASTBULL_TICKER_ALLOW_MULTIPLE` 隔離）：hover 出現 ✕、點 ✕ 結束、設定面板「結束程式」結束，附日誌與截圖
- [ ] 4.2 README（快速開始「怎麼結束」與設定面板說明）更新
- [ ] 4.3 `swift test`、`cargo test`、`openspec validate --all --strict` 全綠
