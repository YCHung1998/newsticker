# fixture
## 實驗格

### S1-01
- 實驗: S1
- 清單條目: #3
- 組合: level=floating
- 情境: 全螢幕 Safari
- 日期: 2026-10-24
- macOS: 26.5.1
- 結果: PASS
- 原因類別: -
- 佐證: -
- 觀察: 可見
- 證據: evidence/a.png
- 重跑: -

### S1-02
- 實驗: S1
- 清單條目: #3
- 組合: level=floating
- 情境: Split View
- 日期: 2026-10-24
- macOS: 26.5.1
- 結果: FAIL
- 原因類別: 平台限制
- 佐證: S1-01 同一程式同組合在全螢幕 Safari 通過；日誌 space.changed 顯示 onActiveSpace=false
- 觀察: 不可見
- 證據: evidence/b.png
- 重跑: -

### S1-03
- 實驗: S1
- 清單條目: #3
- 組合: level=floating
- 情境: 切換 Space
- 日期: 2026-10-24
- macOS: 26.5.1
- 結果: FAIL
- 原因類別: 實作錯誤
- 佐證: -
- 觀察: 忘了設 behavior
- 證據: evidence/b.png
- 重跑: S1-04

### S1-04
- 實驗: S1
- 清單條目: #3
- 組合: level=floating
- 情境: 切換 Space
- 日期: 2026-10-24
- macOS: 26.5.1
- 結果: PASS
- 原因類別: -
- 佐證: -
- 觀察: 可見
- 證據: evidence/a.png
- 重跑: -

### S1-05
- 實驗: S1
- 清單條目: #3
- 組合: level=floating
- 情境: 全螢幕 Safari
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：無外接螢幕
- 證據: -
- 重跑: -

### S4-01
- 實驗: S4
- 清單條目: #3
- 組合: level=floating
- 情境: 1h A
- 日期: 2026-10-24
- macOS: 26.5.1
- 結果: PASS
- 原因類別: -
- 佐證: -
- 觀察: 可見
- 證據: evidence/a.png
- 重跑: -

### S4-02
- 實驗: S4
- 清單條目: #3
- 組合: level=floating
- 情境: 1h B
- 日期: 2026-10-24
- macOS: 26.5.1
- 結果: PASS
- 原因類別: -
- 佐證: -
- 觀察: 可見
- 證據: evidence/a.png
- 重跑: -

## 決定

### D1
- 依據: S1-02
- 內容: Split View 下不可見，接受並記錄【使用者待確認，屬需求變更】

### D2
- 依據: S1-01
- 內容: level=floating; canJoinAllApplications=off; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]

### D3
- 依據: S4-01, S4-02
- 內容: 選 B
- A: CPU=3.1 RSS=41000 WindowServer=4.2
- B: CPU=2.0 RSS=39000 WindowServer=3.9
