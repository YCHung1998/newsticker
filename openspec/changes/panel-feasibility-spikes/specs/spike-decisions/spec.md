## ADDED Requirements

### Requirement: 實驗結束須產出三項決定
全部實驗執行完畢後，`spikes/RESULTS.md` MUST 含「決定」章節，包含三項：(1) 全螢幕「已知限制」清單；(2) level 與 `collectionBehavior` 的最終組合；(3) 渲染方案選擇（A displayLink 或 B 線性 `CABasicAnimation`），附 CPU、記憶體、WindowServer 負載數字。每一項決定 MUST 引用其依據的 `RESULTS.md` 格代號。三項任何一項缺漏或無依據引用，本 change 不得視為完成。

#### Scenario: 決定章節完整
- **WHEN** 執行決定完整性檢查
- **THEN** 檢查 SHALL 確認三項皆存在、每項至少引用一個存在的格代號，渲染方案項 SHALL 含 A 與 B 兩者的 CPU、RSS、WindowServer 數字

#### Scenario: 決定缺依據
- **WHEN** 某項決定引用的格代號不存在或結果為未執行
- **THEN** 檢查 SHALL 失敗

### Requirement: 已知限制清單
【使用者決定，2026-10-24：歸因規則】只有原因類別為 `平台限制`（且附「為何排除是我方錯誤」佐證）的 FAIL 格可以記入「已知限制」；原因類別為 `實作錯誤` 的格 MUST NOT 記入已知限制，MUST 修正實驗程式後重跑。決定完整性檢查（`check_results.sh --require-decisions`）MUST 對引用 `實作錯誤` 格的決定回報失敗。

「已知限制」清單 MUST 逐條列出：失敗或部分失敗的情境（App、模式、組合）、症狀、證據格代號，以及處置（接受並記錄、或需使用者決定）。若 S1 所有組合在所有必要情境皆通過，清單 MUST 明寫「無」並引用證據。清單 MUST 另記 S5 與 S2 中發現的行為限制（如某操作會搶 Focus）。

#### Scenario: 有部分失敗
- **WHEN** 最終組合在 Stage Manager 開啟時不可見
- **THEN** 清單 SHALL 含該條目、截圖路徑與處置

#### Scenario: 實作錯誤不得列為已知限制
- **WHEN** 某決定的依據格為 FAIL 且原因類別為 `實作錯誤`
- **THEN** 完整性檢查 SHALL 失敗，並提示須修正實驗程式後重跑

#### Scenario: 平台限制須有佐證才可接受
- **WHEN** 已知限制引用的 FAIL 格原因類別為 `平台限制`
- **THEN** 該格 SHALL 帶有排除我方錯誤的佐證（對照組格代號、日誌系統回傳值等），否則 `check_results.sh` 失敗

#### Scenario: 全部通過
- **WHEN** 最終組合在所有必要情境皆 PASS
- **THEN** 清單 SHALL 寫「無」並列出對應 PASS 格

### Requirement: level 與 collectionBehavior 最終組合
最終組合 MUST 是 S1 中實測通過的組合之一，明列 level（`.floating` 或 `.statusBar`，不得為 `.screenSaver`）、`canJoinAllApplications` 有無、`collectionBehavior` 完整 OptionSet、是否保留 `.stationary`。若兩種 level 皆通過，MUST 以 `.floating` 與 `.statusBar` 在 S1 的差異（如是否遮蓋選單列、被其他視窗蓋過）說明取捨；無差異時預設選擇【假設，待確認】。

#### Scenario: 組合可追溯
- **WHEN** 閱讀最終組合
- **THEN** SHALL 能對應到 S1 的某個 PASS 格代號，且 `app-shell` 的 `PanelShell` 設定 SHALL 與其逐項一致

### Requirement: S1 不過關的停止規則
S1 完成後，若**沒有任何組合**能在必要情境（見 `spike-protocol` 的 S1 通過標準）通過，執行者 MUST 停止後續依賴此結果的工作（不得進入 `app-shell` 的 `PanelShell` 實作），並將結果回報使用者，因為「蓋過全螢幕」為使用者拍板需求（設計文件 D2），調整它屬需求變更。若有組合僅在部分情境失敗，預設降級為「接受並寫入已知限制」，**此降級為【假設】，須使用者確認**；使用者確認前，MUST NOT 把該降級當成已核准。執行者 MUST NOT 自行改變 D2。

#### Scenario: 無組合通過
- **WHEN** 4 種組合在「全螢幕 Safari」皆不可見
- **THEN** 回報 SHALL 說明這是需求變更並請使用者決策；後續任務 SHALL 暫停，RESULTS 的決定章節標「待使用者決策」

#### Scenario: 部分情境失敗
- **WHEN** 最佳組合僅在某些全螢幕 App 或模式失敗
- **THEN** SHALL 寫入已知限制並標【使用者待確認，屬需求變更】，在使用者確認前不得標為已核准

### Requirement: 渲染方案決定規則
渲染方案決定 MUST 先排除未達「長時間文字不抖」與「凍結／恢復無可見跳動」的方案；兩案都保留時，MUST 以 CPU、WindowServer 負載與記憶體曲線的實測數字相對比較擇優；數字差距極小時預設選實作與狀態較單純者【假設，待確認】。決定 MUST 同時記錄長句 bitmap 是否需要切塊，以及 30fps 降幀是否採用。

#### Scenario: 一案不達標
- **WHEN** 方案 A 在 1 小時內出現可見抖動而 B 沒有
- **THEN** 決定 SHALL 為 B，並引用 A、B 的格代號與數字

#### Scenario: 兩案皆達標
- **WHEN** 兩案皆通過目視條件
- **THEN** 決定 SHALL 附兩案的平均與最大 CPU%、RSS 起訖、WindowServer CPU% 比較表，並說明擇優理由

### Requirement: 決定的下游引用
本 change 的三項決定 SHALL 為 `app-shell` 的輸入；`app-shell` 的 proposal／design MUST 引用 `spikes/RESULTS.md` 的決定章節而非重新猜測。若實驗發現設計文件第 5.2 節的任何設定（如 `hidesOnDeactivate`、`canBecomeKey/Main`、計時器作法）需修改，MUST 列為「對設計文件的修正建議」並回報使用者，不得直接改設計文件。

#### Scenario: 發現設計需修正
- **WHEN** 實驗證明設計文件 5.2 的某設定無效
- **THEN** 決定章節 SHALL 含「對設計文件的修正建議」條目，且回報使用者
