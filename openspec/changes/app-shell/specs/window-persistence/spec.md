## ADDED Requirements

### Requirement: 存檔內容
`Persistence` MUST 儲存：螢幕 UUID（`CGDisplayCreateUUIDFromDisplayID`）、面板相對該螢幕的偏移、透明度。MUST NOT 儲存點穿狀態。儲存媒介使用 UserDefaults 或單一 plist/JSON 檔【待確認】（2026-10-24 暫定實作：UserDefaults【假設】）。

#### Scenario: 往返
- **WHEN** 存入螢幕 UUID、偏移 (120, 40)、透明度 0.6 再讀出
- **THEN** SHALL 得到相同值（單元測試，檔案位置可注入）

### Requirement: 以 didMoveNotification 存位置並 debounce
位置存檔 MUST 聽 `NSWindow.didMoveNotification` 並 debounce（間隔【待確認】，暫定 0.3–1 秒；2026-10-24 實作取 0.5 秒【假設】），MUST NOT 依賴 mouse-up。拖曳過程中的連續事件 MUST 合併成一次寫入。

#### Scenario: 連續移動
- **WHEN** 在 100ms 內送出 50 次 didMove
- **THEN** SHALL 只寫入一次最終位置（注入假時鐘的單元測試）

#### Scenario: mouse-up 未送達
- **WHEN** 拖曳結束但無 mouse-up
- **THEN** 位置 SHALL 仍在 debounce 後被儲存

### Requirement: 螢幕缺失時退回並夾制
啟動還原時，若存檔螢幕 UUID 找不到，MUST 退回主螢幕，並 MUST 把面板夾在該螢幕可視區（`visibleFrame`）內，使面板至少部分可見。夾制為純函式，MUST 有單元測試。

#### Scenario: 外接螢幕已拔除
- **WHEN** 存檔位於不存在的螢幕
- **THEN** 面板 SHALL 出現在主螢幕可視區內

#### Scenario: 偏移超出螢幕
- **WHEN** 存檔偏移使面板完全落在可視區外
- **THEN** 夾制後 SHALL 至少部分可見（fail-then-pass：先寫測試，未夾制時失敗）

### Requirement: 螢幕參數變更
App MUST 監聽 `NSApplication.didChangeScreenParametersNotification`，在螢幕拔插、解析度變更、鏡像後重新計算面板位置並夾制；面板 MUST 至少部分可見。拔除後再插回原螢幕時是否自動移回【待確認】（預設：不自動移回，下次啟動依存檔 UUID 還原）。

#### Scenario: 拔除外接螢幕
- **WHEN** 面板在外接螢幕時拔除該螢幕
- **THEN** 面板 SHALL 移到主螢幕可視區內

#### Scenario: 下次啟動回到正確螢幕
- **WHEN** 面板曾放在外接螢幕，結束後外接螢幕仍連接，再啟動
- **THEN** 面板 SHALL 出現在該外接螢幕（需人工驗收）
