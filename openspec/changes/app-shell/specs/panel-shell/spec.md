## ADDED Requirements

### Requirement: 面板基本設定
`PanelShell` MUST 是 `NSPanel`，其 styleMask MUST 在 init 一次設定為 `[.borderless, .nonactivatingPanel]`，MUST NOT 使用 `.hudWindow`，MUST NOT 事後修改 styleMask 以加入 `.nonactivatingPanel`。面板 SHALL 設 `hidesOnDeactivate = false`、`canBecomeKey = false`、`canBecomeMain = false`、`hasShadow = false`、`isOpaque = false`、`backgroundColor = .clear`。預設尺寸約 620×42【假設】，單一視窗。

#### Scenario: 啟動後屬性正確
- **WHEN** App 啟動並顯示面板
- **THEN** 單元測試或啟動日誌 SHALL 證明上述每個屬性的實際值，且 styleMask 不含 `.hudWindow`

#### Scenario: App 失去啟用狀態
- **WHEN** 使用者切換到其他 App
- **THEN** 面板 SHALL 仍然可見（`hidesOnDeactivate` 為 false）

### Requirement: level 與 collectionBehavior（暫定值，待 spike 決定確認）
面板的 `level`、`collectionBehavior`（含 `canJoinAllApplications` 有無、是否保留 `.stationary`）**（2026-10-24 修訂【假設】）暫定實作先行**：在 `spikes/RESULTS.md` 決定章節經使用者確認前，MUST 使用暫定值——level `.statusBar`、collectionBehavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`、`canJoinAllApplications` 先不加（待 S1）——集中於 `ShellConfig`，並標示「暫定（待 spike 決定確認後調整）」。決定章節確認後 MUST 逐項等於其「最終組合」並對應 S1 的 PASS 格代號。MUST NOT 使用 `.screenSaver` level。暫定值不代表已通過 S1。

#### Scenario: 與決定逐項一致（決定章節確認後）
- **WHEN** 檢查 `ShellConfig` 與 `RESULTS.md` 決定章節
- **THEN** level、collectionBehavior OptionSet、`canJoinAllApplications` 三者 SHALL 逐項相同，且 RESULTS 引用的格代號存在

#### Scenario: 決定尚未產出
- **WHEN** `RESULTS.md` 決定章節缺漏或標「待使用者決策」
- **THEN** SHALL 使用暫定值實作，`ShellConfig` 與文件 SHALL 標示「暫定（待 spike 決定確認後調整）」，5.3 SHALL 仍須補驗

### Requirement: Accessory App 且永不啟用
App MUST 為 accessory（Info.plist `LSUIElement=YES`，無 Dock 圖示）。程式碼 MUST NOT 呼叫 `NSApp.activate` 或 `NSApplication.activate(ignoringOtherApps:)`，MUST NOT 呼叫 `makeKeyAndOrderFront` 以外會令 App 啟用的 API 來顯示面板（顯示面板用 `orderFrontRegardless`）。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/FastBullTicker/` 執行 `grep -rn "activate(" Sources/FastBullTicker/`
- **THEN** SHALL 無對 `NSApp`／`NSApplication` 的啟用呼叫

#### Scenario: 操作期間 frontmost 不變
- **WHEN** 使用者在另一 App 打字並同時點擊、拖曳面板與操作選單
- **THEN** `frontmostApplication` SHALL 不變、本 App 啟用通知 SHALL 為零（此為需人工驗收，見 `app-acceptance`）

### Requirement: 拖曳以 performDrag 實作
點擊控制列的箭頭按鈕或訊息的迴紋針命中區為動作（於 mouse-up 且目標未變時觸發，不拖曳）；其餘點擊（標籤、訊息文字、位置指示等）MUST 等同拖曳。命中測試以純函式決定，優先序為按鈕 > 迴紋針 > 拖曳（見 `ticker-navigation-link` 的「命中測試與拖曳區分」）。拖曳 MUST 使用 `performDrag(with:)`。由於 mouse-up 可能不送達，拖曳 MUST NOT 依賴 mouse-up 觸發任何狀態更新（位置存檔見 `window-persistence`）。【2026-10-24 修訂，來源 change：`ticker-navigation-link`；取代原「點擊帶子 MUST 等同拖曳（v1 不做開啟詳情）」，該句與本 change 的箭頭與迴紋針動作衝突】若 spike S5 發現 `performDrag` 在非 key 的 nonactivating panel 上行為異常，MUST 依決定章節的處置實作【依 spike-decisions】。

#### Scenario: 拖曳移動視窗
- **WHEN** 使用者按住帶子並拖動
- **THEN** 面板 frame.origin SHALL 隨滑鼠移動，frontmost App SHALL 不變

### Requirement: 整條帶子以 window alphaValue 調整透明度
整條帶子（含文字）的透明度 MUST 由 window `alphaValue` 控制；背景 MUST 為純色，MUST NOT 使用 `NSVisualEffectView` 或毛玻璃。滑桿下限 MUST 約為 20–30%（確切值【待確認】；2026-10-24 實作取 30%【假設】），使帶子不致完全看不見。

#### Scenario: 透明度範圍
- **WHEN** 滑桿拖到最小
- **THEN** `alphaValue` SHALL 等於下限值且大於 0.2

#### Scenario: 無毛玻璃
- **WHEN** 檢查面板 view 階層
- **THEN** SHALL 不含 `NSVisualEffectView`
