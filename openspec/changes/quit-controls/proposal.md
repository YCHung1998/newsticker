## Why

現在要結束 App 只有選單列報紙圖示 →「結束」（或右鍵選單），或終端機 `pkill`／`stop-old.sh`。使用者覺得不夠直覺：跑馬燈上沒有任何關閉的 X，設定面板（齒輪）裡也沒有結束程式的按鈕（面板現有的「關閉」只是關掉設定面板本身，容易誤會）。

## What Changes

- 跑馬燈**帶子最右側**新增 ✕：平常不顯示，**滑鼠移上帶子才出現**，點一下**直接結束程式**（沒有確認對話框，因為帶子是非啟用面板，彈對話框會搶鍵盤焦點）。
- 設定面板新增「**結束程式**」按鈕，放在現有「關閉」按鈕之前；一次點擊即結束。
- 三個入口（✕、設定面板按鈕、選單列「結束」）走**同一個結束流程**：先隱藏帶子與設定面板（畫面立刻消失），再走既有的優雅結束（關閉抓取程式，最多約 6 秒）。
- ✕ 以疊在帶子最右緣的方式顯示，**不改變面板寬度與可視寬度**；✕ 顯示期間會蓋住最右側約 28pt 的內容（包含那裡的迴紋針），✕ 的點擊優先。
- 點穿模式下滑鼠事件穿透，✕ 不會出現也不可點（選單列「結束」仍可用）。

## Capabilities

### New Capabilities
- `quit-controls`: ✕ 的顯示與命中規則、設定面板的「結束程式」按鈕、統一的結束流程。

### Modified Capabilities
<!-- 無：既有的 settings-panel／ticker-navigation 規格尚在未歸檔的 change 中，本 change 以獨立能力描述，不做 delta。 -->

## Impact

- 程式：`HitTesting.swift`（新目標 `.quit`）、`NavigationInput.swift`（`onQuit`）、`TickerView.swift`（✕ 圖層與 hover 顯示）、`ShellConfig.swift`（`quitSlotWidth`）、`SettingsPanelModel.swift`／`SettingsPanelController.swift`／`SettingsPanelWiring.swift`（新指令與按鈕）、`AppDelegate.swift`（統一的 `requestQuit`）。
- 不改協定、不改 Rust、不改樣式檔格式。
- 風險：誤觸會直接結束程式（無確認）——以「只有 hover 才出現」降低；使用者需重新啟動才能再看到跑馬燈。
