## Why

設計文件（`docs/superpowers/specs/2026-10-24-fastbull-ticker-design.md`）第 6 節指出：「蓋過全螢幕 App」「不搶 Focus」「選單展開時計時器不斷料」等平台行為，官方文件查無或有反例回報（Apple 開發者論壇 2025-07「NSWindowCollectionBehavior in Full Screen Spaces」與 thread 759780，**未經核對**），只能靠實測決定。渲染方案（displayLink vs 線性 `CABasicAnimation`）也要用數字決定。若在這些問題未解時就寫正式 App（`show-engine-core`、`app-shell`），可能整批返工；其中「蓋過全螢幕」若不成立更屬需求變更。

本 change 把設計文件第 7 節的 S1–S4 寫成可驗收的規格，並把第 6 節「官方查無」清單中沒有被 S1–S4 涵蓋的項目補成 S5，使每一條都有對應實驗。

## What Changes

- 定義**丟棄式**可行性實驗的規格：實驗矩陣、每格通過標準、結果紀錄格式（`spikes/RESULTS.md`）、人工與自動的分工。
- S1 全螢幕可見性（level × `canJoinAllApplications`，含 `stationary` 對照）；S2 不搶 Focus（含 `.nonactivatingPanel` 於 init 設定的對照、`MenuBarExtra(.window)` 對照）；S3 選單展開補料計時器；S4 渲染 A/B 一小時實測與紋理上限；S5 面板補充（`.hudWindow` 於 borderless、`performDrag(with:)` 於非 key 的 nonactivating panel、`didMoveNotification` 存位置）。
- 定義實驗結束後**必須產出三項決定**：全螢幕「已知限制」清單、level 與 `collectionBehavior` 最終組合、渲染方案（附 CPU／記憶體／WindowServer 數字）。
- 定義 S1 不過關時的處置：停止並回報使用者（需求變更）；預設降級「接受並記錄已知限制」屬【假設】、需使用者確認。
- 本 change 的產出是「規格」；apply 階段的產出是 `spikes/` 實驗程式（丟棄式、不進正式專案）＋`spikes/RESULTS.md`＋決定。**本階段不建立 `spikes/`，不寫任何 Swift。**
- 不在範圍：正式 `FastBullTickerCore`、`TickerScheduler`、`FeedClient`、正式 `PanelShell`；helper 生命週期與螢幕參數變更（設計文件第 7 節明訂併入 `app-shell` 驗收）。

## Capabilities

### New Capabilities
- `spike-protocol`: 實驗的共通規則與各實驗（S1–S5）的矩陣、步驟、通過標準、結果紀錄格式、自動／人工分工、丟棄式隔離。
- `spike-decisions`: 實驗結束後必須產出的三項決定、S1 不過關的停止規則、決定的完整性檢查與下游引用。

### Modified Capabilities
（無。）

## Impact

- 依賴：設計文件第 5.2、6、7、8 節。與 `message-contract`、`connect-engine-fastbull` 無檔案依賴（實驗用假訊息，不使用協定）。
- 下游：`app-shell` 依本 change 的三項決定實作 `PanelShell`、`TickerRenderer`；`show-engine-core` 不受影響。
- 新增目錄（apply 階段）：`spikes/`（SwiftPM 命令列專案，丟棄式，不進正式專案）。
- 硬體／環境前提：macOS 26.5.1、Xcode 26.6、Swift 6.3.3（已實測）、**外接螢幕一台**（S1 外接情境）、需使用者在場操作（見 `tasks.md`）。
- 風險：S1 可能不過關而導致需求變更；S4 各一小時實測需整段時間不被打擾。
