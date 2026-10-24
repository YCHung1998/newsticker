## ADDED Requirements

### Requirement: 假 helper 先於真 helper
`FeedClient` MUST 先以假 helper 腳本通過整合測試，再換真 helper。假 helper 腳本情境 MUST 含：正常輸出、崩潰、半行、卡死、stderr 灌滿。測試 MUST NOT 連網。

#### Scenario: 五種情境
- **WHEN** 執行 FeedClient 整合測試
- **THEN** 每種情境 SHALL 有獨立測試，並有 fail-then-pass 證據（先對缺實作版本失敗，再通過）

#### Scenario: 換真 helper
- **WHEN** 假 helper 測試全過後以真 `ticker-connect` 啟動
- **THEN** 面板 SHALL 顯示來自 snapshot 的重播訊息（需人工目視，需網路）

### Requirement: helper 生命週期驗收
MUST 驗證：(1) `kill -9` App 後數秒內無孤兒 helper；(2) 睡眠喚醒後心跳不被誤判；(3) stderr 灌滿不阻塞；(4) 複製進 bundle 並簽名後 helper 仍可啟動。

#### Scenario: kill -9
- **WHEN** 執行 `kill -9 $(pgrep FastBullTicker)` 後等待數秒
- **THEN** `pgrep ticker-connect` SHALL 無結果（等待秒數上限【待確認】，暫定 5 秒）

#### Scenario: 睡眠喚醒
- **WHEN** 機器睡眠後喚醒
- **THEN** helper SHALL 不被誤殺重啟，或若重啟 SHALL 記錄在日誌並判定為缺陷（需人工，硬體：本機可睡眠）

### Requirement: 螢幕參數變更驗收
MUST 驗證拔插外接螢幕、改解析度、鏡像後面板至少部分可見，且下次啟動回到正確螢幕。

#### Scenario: 外接螢幕
- **WHEN** 面板在外接螢幕上時拔除螢幕、再插回、再重啟 App
- **THEN** 拔除後面板 SHALL 部分可見於主螢幕；重啟後 SHALL 回到外接螢幕（需人工，硬體：外接螢幕一台）

#### Scenario: 無硬體
- **WHEN** 無外接螢幕
- **THEN** 該格 SHALL 標「未執行：無硬體」，不得標通過

### Requirement: spike 結論在正式 bundle 補驗
spike 使用未簽名 SwiftPM 可執行檔，MUST 在簽名後的 `.app` bundle 環境補驗至少：S1 最終組合在全螢幕可見、S2 不搶 Focus（frontmost 不變、啟用通知為零）、S3 選單展開 60 秒不斷料、S4 所選方案無可見抖動。結果 MUST 記錄在 `docs` 外的驗收紀錄檔（路徑【待確認】，暫定 `app-shell` 目錄下 `ACCEPTANCE.md`，apply 階段才建立）。若任一結論不成立，MUST 列為對 spike 決定的修正並回報使用者，不得自行改決定。

#### Scenario: 結論成立
- **WHEN** 於 bundle 重跑上述四項
- **THEN** 紀錄 SHALL 含每項 PASS/FAIL、日期、macOS 版本與證據路徑

#### Scenario: 結論不成立
- **WHEN** bundle 環境下 S1 全螢幕不可見
- **THEN** SHALL 回報使用者，標示 spike 決定待修正，後續驗收暫停

### Requirement: 記憶體基準量測
MUST 量測 App 與 helper 在穩定運行 ≥ 10 分鐘時的 RSS 基準。App ≤ 35MB、helper ≤ 15MB 為【假設】，先量基準再收緊；超標不自動視為失敗，MUST 回報使用者決定是否調整門檻。macOS 14 最低版本與記憶體門檻待使用者確認。

#### Scenario: 記錄基準
- **WHEN** 運行 10 分鐘後以 `ps -o rss= -p <pid>` 取樣
- **THEN** 紀錄 SHALL 含兩行程 RSS 與是否低於假設門檻

### Requirement: VPN／Proxy 下 helper TLS 驗證
MUST 在使用者實際網路環境（VPN 或 Proxy 開啟）驗證 helper 能否成功連線並通過 TLS 驗證。此項為【待驗證】，環境與結果由使用者提供；若失敗 MUST 回報給 `connect-engine-fastbull` 作為後續修正，本 change 不修改 helper。

#### Scenario: VPN 開啟
- **WHEN** 在 VPN 開啟下啟動 App
- **THEN** 紀錄 SHALL 含 helper `status` 為 ok 或 error 與錯誤訊息

#### Scenario: 使用者無 VPN／Proxy
- **WHEN** 使用者無此環境
- **THEN** 該格 SHALL 標「未執行：無環境」
