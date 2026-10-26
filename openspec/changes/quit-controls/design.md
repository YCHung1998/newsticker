## Context

結束 App 目前只有 `StatusMenuController.onQuit` → `NSApp.terminate(nil)`。帶子由 `TickerView` 繪製，滑鼠事件經 `NavigationInputRouter`（純邏輯、mouse-up 觸發）與 `HitTesting`（齒輪／箭頭／迴紋針／拖曳）分派；`TickerView.onPointerInside` 已回報指標進出面板。設定面板由 `SettingsPanelModel.items` 產生項目，指令 `SettingsCommand`（含 `.close`）由 `SettingsPanelController` 分派。`applicationShouldTerminate` 會優雅關閉 helper（最多約 6 秒）。

## Goals / Non-Goals

**Goals:** 帶子上有 hover 才出現的 ✕、設定面板有「結束程式」、三個入口同一流程、不改版面、沿用既有的純邏輯＋離屏測試模式。
**Non-Goals:** 確認對話框、「最小化到選單列」、結束前記住狀態以外的任何新設定、改變選單列「結束」的外觀。

## Decisions

1. **✕ 疊加在帶子最右緣，不改面板寬度。** 替代：在帶子旁加一個固定寬度的槽（像齒輪槽）——會讓可視寬度再少 28pt、且改變 `panelWidth` 與所有既有的幾何測試。代價：hover 時蓋住最右 28pt 內容（含迴紋針），以 ✕ 優先處理。
2. **hover 顯示用既有的 `onPointerInside`。** 不新增追蹤區；指標在面板內才顯示。命中測試不看 hover 狀態——按下一定發生在面板內，指標必然已進入，不會出現「看不見卻能點」的情況（點穿模式 `isEnabled == false` 時整個 router 停用）。
3. **`HitGeometry.quitSlotWidth` 預設 0**：既有直接建構 `HitGeometry` 的測試不受影響；App 的 `ShellConfig` 設成 28。優先序：齒輪 > 控制列 > **結束 ✕** > 迴紋針 > 拖曳（✕ 與齒輪、控制列不重疊，所以實際只與迴紋針競爭）。
4. **單一 `requestQuit()`**：隱藏帶子與設定面板 → `NSApp.terminate(nil)`。以注入的閉包測試（先隱藏、後結束、重入只執行一次）。替代：各入口直接 `terminate`——帶子會在 helper 收尾的最多約 6 秒內仍留在畫面上，像當掉。
5. **設定面板新指令 `.quitApp`，放在「關閉」之前**，按鈕標題用「結束程式」以與「關閉」（只關面板）區分。
6. **無確認對話框**：帶子與設定面板都是非啟用面板，`NSAlert` 會搶鍵盤焦點（與專案「不搶焦點」原則衝突）；以 hover 才出現降低誤觸。

## Risks / Trade-offs

- [誤觸直接結束] → 只有 hover 才顯示、需 mouse-up 仍在 ✕ 上；使用者可從 Finder／`open` 重新啟動。
- [✕ 蓋住最右側的迴紋針] → 僅 hover 期間；使用者可把滑鼠移到內容中間再點迴紋針（迴紋針在各則訊息的最右，捲動中會離開 ✕ 區）。
- [✕ 的實機外觀與 hover 手感] → 離屏渲染＋純邏輯測試，真機驗收（tasks 4.1）需要目視；結論如實回報。

## Migration Plan

純新增，沒有資料遷移。回滾 = revert 該 change 分支。

## Open Questions

- ✕ 的樣式（圓形灰底白 ✕ 或純 ✕）與位置（右緣 28pt）— 暫定圓形半透明灰底白色 ✕，待使用者目視。
