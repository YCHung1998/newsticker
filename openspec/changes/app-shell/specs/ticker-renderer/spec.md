## ADDED Requirements

### Requirement: TickerRenderer 介面
MUST 定義 `TickerRenderer` 協定，消費 `show-engine-core` 的 `TickerScheduler` 輸出（每則訊息的 `tapeX`／`width`／樣式／文字／時間字串，以及某 tape 時間下的位移），不得在 Renderer 內重新實作排程或狀態機。協定 MUST 允許兩種實作（displayLink／`CABasicAnimation`）以同一組測試替身驗證。具體 Core 型別名稱【待確認，待 `show-engine-core` apply 後對齊】。

#### Scenario: 以測試替身驅動
- **WHEN** 以假 Scheduler 輸出驅動 Renderer 的測試實作
- **THEN** 呼叫序列（加入訊息、設定位移、凍結、恢復）SHALL 與預期一致

### Requirement: 依 spike 決定選擇渲染實作
正式實作 MUST 為 `spikes/RESULTS.md` 決定章節所選方案（A：`NSView.displayLink`，逐幀依 tape 時間設 container layer 位置；B：單一線性 `CABasicAnimation`）。另一案 MUST NOT 同時進入正式專案。是否採用 30fps（`preferredFrameRateRange`）、長句是否切塊 MUST 依決定章節。此需求被 spike S4 決定阻塞。

#### Scenario: 與決定一致
- **WHEN** 檢查正式專案
- **THEN** 渲染實作 SHALL 與決定章節方案相同，決定章節 SHALL 含 A、B 兩案數字

### Requirement: 每則訊息預渲染為 bitmap
每則訊息 MUST 預渲染成 bitmap layer（避免每幀重繪文字）。bitmap 寬度超過紋理上限（設計文件記憶約 16384px，待 S4 實測）時 MUST 切塊，切塊接縫 MUST 無可見縫隙（目視）。是否需切塊依 S4 結果。

#### Scenario: 長句
- **WHEN** 渲染 400 字元 CJK 長句
- **THEN** 若 S4 判定需切塊，SHALL 切為多個不超過上限的塊並連續拼接；單元測試 SHALL 驗證切塊寬度總和等於原寬度且每塊不超過上限

### Requirement: 遮蔽與隱藏時凍結
當 `NSWindow.didChangeOcclusionStateNotification` 顯示面板被完全遮住，或使用者隱藏面板時，Renderer MUST 停止逐幀工作（displayLink 暫停或動畫暫停）並讓 `TickerScheduler` 凍結 tape 時間；恢復時 MUST 接續，不得瞬移。

#### Scenario: 被遮住
- **WHEN** 面板被判定為不可見
- **THEN** 逐幀回呼次數 SHALL 降為 0，CPU 應近零（以取樣驗證，需人工目視恢復無跳動）

### Requirement: Float 精度與 rebase
Renderer MUST 套用 Core 的 rebase 輸出以避免 Float32 位置精度劣化（60px/s 跑 24 小時約 5M px，精度約 0.5px）。rebase 發生時畫面 MUST 無可見跳動。

#### Scenario: rebase 邊界
- **WHEN** 觸發 rebase
- **THEN** 所有 layer 的螢幕位置 SHALL 在 rebase 前後相同（容差 < 0.5px，單元測試以測試替身驗證）
