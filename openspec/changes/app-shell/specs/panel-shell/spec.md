## ADDED Requirements

### Requirement: 面板基本設定
`PanelShell` MUST 是 `NSPanel`，其 styleMask MUST 在 init 一次設定為 `[.borderless, .nonactivatingPanel]`，MUST NOT 使用 `.hudWindow`，MUST NOT 事後修改 styleMask 以加入 `.nonactivatingPanel`。面板 SHALL 設 `hidesOnDeactivate = false`、`canBecomeKey = false`、`canBecomeMain = false`、`hasShadow = false`、`isOpaque = false`、`backgroundColor = .clear`。預設尺寸約 620×42【假設】，單一視窗。

#### Scenario: 啟動後屬性正確
- **WHEN** App 啟動並顯示面板
- **THEN** 單元測試或啟動日誌 SHALL 證明上述每個屬性的實際值，且 styleMask 不含 `.hudWindow`

#### Scenario: App 失去啟用狀態
- **WHEN** 使用者切換到其他 App
- **THEN** 面板 SHALL 仍然可見（`hidesOnDeactivate` 為 false）

### Requirement: level 與 collectionBehavior 引用 spike 決定
面板的 `level`、`collectionBehavior`（含 `canJoinAllApplications` 有無、是否保留 `.stationary`）MUST 逐項等於 `spikes/RESULTS.md` 決定章節的「最終組合」，並 MUST 能對應到 S1 的某個 PASS 格代號；本 change MUST NOT 自行選擇這些值，MUST NOT 使用 `.screenSaver` level。設計文件 5.2 的候選 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` 僅為 spike 的起點，不是本規格的決定。若決定章節狀態為「待使用者決策」，本需求對應任務 MUST 保持阻塞。

#### Scenario: 與決定逐項一致
- **WHEN** 檢查 `ShellConfig` 與 `RESULTS.md` 決定章節
- **THEN** level、collectionBehavior OptionSet、`canJoinAllApplications` 三者 SHALL 逐項相同，且 RESULTS 引用的格代號存在

#### Scenario: 決定尚未產出
- **WHEN** `RESULTS.md` 決定章節缺漏或標「待使用者決策」
- **THEN** 不得實作此需求，tasks 對應項目 SHALL 維持阻塞

### Requirement: Accessory App 且永不啟用
App MUST 為 accessory（Info.plist `LSUIElement=YES`，無 Dock 圖示）。程式碼 MUST NOT 呼叫 `NSApp.activate` 或 `NSApplication.activate(ignoringOtherApps:)`，MUST NOT 呼叫 `makeKeyAndOrderFront` 以外會令 App 啟用的 API 來顯示面板（顯示面板用 `orderFrontRegardless`）。

#### Scenario: 靜態檢查
- **WHEN** 對 `Sources/FastBullTicker/` 執行 `grep -rn "activate(" Sources/FastBullTicker/`
- **THEN** SHALL 無對 `NSApp`／`NSApplication` 的啟用呼叫

#### Scenario: 操作期間 frontmost 不變
- **WHEN** 使用者在另一 App 打字並同時點擊、拖曳面板與操作選單
- **THEN** `frontmostApplication` SHALL 不變、本 App 啟用通知 SHALL 為零（此為需人工驗收，見 `app-acceptance`）

### Requirement: 拖曳以 performDrag 實作
點擊帶子 MUST 等同拖曳（v1 不做開啟詳情）。拖曳 MUST 使用 `performDrag(with:)`。由於 mouse-up 可能不送達，MUST NOT 依賴 mouse-up 觸發任何狀態更新（位置存檔見 `window-persistence`）。若 spike S5 發現 `performDrag` 在非 key 的 nonactivating panel 上行為異常，MUST 依決定章節的處置實作【依 spike-decisions】。

#### Scenario: 拖曳移動視窗
- **WHEN** 使用者按住帶子並拖動
- **THEN** 面板 frame.origin SHALL 隨滑鼠移動，frontmost App SHALL 不變

### Requirement: 整條帶子以 window alphaValue 調整透明度
整條帶子（含文字）的透明度 MUST 由 window `alphaValue` 控制；背景 MUST 為純色，MUST NOT 使用 `NSVisualEffectView` 或毛玻璃。滑桿下限 MUST 約為 20–30%（確切值【待確認】），使帶子不致完全看不見。

#### Scenario: 透明度範圍
- **WHEN** 滑桿拖到最小
- **THEN** `alphaValue` SHALL 等於下限值且大於 0.2

#### Scenario: 無毛玻璃
- **WHEN** 檢查面板 view 階層
- **THEN** SHALL 不含 `NSVisualEffectView`
