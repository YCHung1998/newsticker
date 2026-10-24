# spikes/RESULTS.md — 可行性實驗結果

> 狀態：**範本，所有格尚未執行。** 任何結果欄位在人工輪實測前一律為「未執行」，不得預填。
> change：`panel-feasibility-spikes`。平台：macOS 26.5.1、Xcode 26.6、Swift 6.3.3、arm64（每格仍須自填 `sw_vers`）。
> 檔名 `RESULTS.md` 為建議（設計文件未指定）。

## 填寫規則

- 每格一個 `### 代號` 區塊；欄位格式 `- 欄位: 值`。檢查：`spikes/check_results.sh`（`--require-decisions` 檢查「決定」章節）。
- 結果 ∈ `PASS`／`FAIL`／`未執行`；FAIL 與未執行必須保留，不得刪除。
- **原因類別（2026-10-24 使用者決定）**：每格必填。`PASS` 與 `未執行` 填 `-`；`FAIL` 必須二選一：
  - `平台限制`：macOS 本身不允許或行為不符，且已排除我方實驗程式問題。**必須**在「佐證」欄寫明為何排除是我方錯誤（例如：同一程式在另一組合通過、對照組格代號、日誌中系統回傳值）。只有此類可記入「已知限制」。
  - `實作錯誤`：實驗程式或我方 code 的 bug。**不得記成已知限制**；須修正實驗程式後重跑，並在「重跑」欄填入重跑格代號（該格須為 PASS 或 FAIL(平台限制)）。
- PASS／FAIL 另須：`日期`(ISO 8601)、`macOS`(`sw_vers -productVersion`)、`證據`(相對於 `spikes/` 的既存檔案路徑，逗號分隔；截圖由使用者以系統快捷鍵手動取得，見 README)。
- 未執行：`觀察` 必須以「未執行」開頭並寫明原因（如「未執行：尚未進行人工輪」「未執行：無外接螢幕」）。
- `清單條目` 對應 `design.md` 的「官方查無」對照表編號（#1–#6）或其他來源（論壇反例、降幀實效、didMove 存位置）。

## 實驗格

### S1-01
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 全螢幕 Safari
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-02
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 全螢幕 Keynote 或 QuickTime（擇一，於觀察記錄）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-03
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: Split View
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-04
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 切換 Space 後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-05
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 睡眠喚醒後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-06
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: Stage Manager 開
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-07
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: Stage Manager 關
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-08
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 外接螢幕（螢幕有獨立 Space：開）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-09
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 外接螢幕（螢幕有獨立 Space：關）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-10
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 全螢幕 Safari
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-11
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 全螢幕 Keynote 或 QuickTime（擇一，於觀察記錄）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-12
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: Split View
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-13
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 切換 Space 後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-14
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 睡眠喚醒後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-15
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: Stage Manager 開
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-16
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: Stage Manager 關
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-17
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 外接螢幕（螢幕有獨立 Space：開）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-18
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=floating; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 外接螢幕（螢幕有獨立 Space：關）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-19
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 全螢幕 Safari
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-20
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 全螢幕 Keynote 或 QuickTime（擇一，於觀察記錄）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-21
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: Split View
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-22
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 切換 Space 後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-23
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 睡眠喚醒後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-24
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: Stage Manager 開
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-25
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: Stage Manager 關
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-26
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 外接螢幕（螢幕有獨立 Space：開）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-27
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=off; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle]
- 情境: 外接螢幕（螢幕有獨立 Space：關）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-28
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 全螢幕 Safari
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-29
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 全螢幕 Keynote 或 QuickTime（擇一，於觀察記錄）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-30
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: Split View
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-31
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 切換 Space 後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.2）
- 證據: -
- 重跑: -

### S1-32
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 睡眠喚醒後
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-33
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: Stage Manager 開
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-34
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: Stage Manager 關
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-35
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 外接螢幕（螢幕有獨立 Space：開）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

### S1-36
- 實驗: S1
- 清單條目: 論壇反例回報（未核對）；S1 全矩陣
- 組合: level=statusBar; canJoinAllApplications=on; stationary=on; collectionBehavior=[canJoinAllSpaces,fullScreenAuxiliary,stationary,ignoresCycle,canJoinAllApplications]
- 情境: 外接螢幕（螢幕有獨立 Space：關）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -

<!--
S1 無 `.stationary` 對照（#3）：對通過全部必要情境的組合，複製下列區塊補跑（代號用 S1-NS-01、S1-NS-02…），
spike-s1 加上 `--stationary off`，組合欄寫明 stationary=off 與完整 collectionBehavior。

### S1-NS-01
- 實驗: S1
- 清單條目: #3 stationary 與 canJoinAllSpaces、fullScreen* 的互斥關係
- 組合: level=...; canJoinAllApplications=...; stationary=off; collectionBehavior=[...]
- 情境: ...
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 2.3）
- 證據: -
- 重跑: -
-->

### S2-01
- 實驗: S2
- 清單條目: 正式方案基準；#4 performDrag 時的 Focus 觀察
- 組合: menu=statusitem; nonactivating=init; style=plain; level=floating
- 情境: 在 TextEdit 持續打字 abcdefghij…，同時點擊／拖曳面板、操作選單與滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.2）
- 證據: -
- 重跑: -

### S2-02
- 實驗: S2
- 清單條目: #1 .nonactivatingPanel 必須在 init 設定
- 組合: menu=statusitem; nonactivating=after; style=plain; level=floating
- 情境: 在 TextEdit 持續打字 abcdefghij…，同時點擊／拖曳面板、操作選單與滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.2）
- 證據: -
- 重跑: -

### S2-03
- 實驗: S2
- 清單條目: #5 MenuBarExtra 是否搶 Focus
- 組合: menu=menubarextra; nonactivating=init; style=plain; level=floating
- 情境: 在 TextEdit 持續打字 abcdefghij…，同時點擊／拖曳面板、操作選單與滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.2）
- 證據: -
- 重跑: -

### S2-04
- 實驗: S2
- 清單條目: #5 MenuBarExtra 是否搶 Focus
- 組合: menu=menubarextra; nonactivating=after; style=plain; level=floating
- 情境: 在 TextEdit 持續打字 abcdefghij…，同時點擊／拖曳面板、操作選單與滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.2）
- 證據: -
- 重跑: -

### S3-01
- 實驗: S3
- 清單條目: 已查證：選單追蹤用 NSEventTrackingRunLoopMode（實測確認）
- 組合: timer=default（預設 mode Timer）
- 情境: 選單展開 ≥ 60 秒並持續拖動滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 4.2）
- 證據: -
- 重跑: -

### S3-02
- 實驗: S3
- 清單條目: 已查證：選單追蹤用 NSEventTrackingRunLoopMode（實測確認）
- 組合: timer=common（.common Timer）
- 情境: 選單展開 ≥ 60 秒並持續拖動滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 4.2）
- 證據: -
- 重跑: -

### S3-03
- 實驗: S3
- 清單條目: 已查證：選單追蹤用 NSEventTrackingRunLoopMode（實測確認）
- 組合: timer=dispatch（DispatchSourceTimer）
- 情境: 選單展開 ≥ 60 秒並持續拖動滑桿
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 4.2）
- 證據: -
- 重跑: -

### S4-01
- 實驗: S4
- 清單條目: 全部：長時間文字抖動／CPU／記憶體
- 組合: scheme=A; fps-cap=none; level=floating; 620x42 【假設】
- 情境: 1 小時連續捲動（10 則假訊息，含 400 字元 CJK 長句）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S4-02
- 實驗: S4
- 清單條目: 全部：長時間文字抖動／CPU／記憶體
- 組合: scheme=B; fps-cap=none; level=floating; 620x42 【假設】
- 情境: 1 小時連續捲動（10 則假訊息，含 400 字元 CJK 長句）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S4-03
- 實驗: S4
- 清單條目: 降幀實效未查（第 6 節已查證項註記）
- 組合: scheme=A; fps-cap=30; level=floating; 620x42 【假設】
- 情境: 30fps 實效驗證（幀間隔分佈與 CPU 變化）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S4-04
- 實驗: S4
- 清單條目: 降幀實效未查（第 6 節已查證項註記）
- 組合: scheme=B; fps-cap=30; level=floating; 620x42 【假設】
- 情境: 30fps 實效驗證（幀間隔分佈與 CPU 變化；B 以 --frame-observer on 觀察）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S4-05
- 實驗: S4
- 清單條目: 長句 bitmap 寬度 vs 紋理上限（約 16384px，記憶待實測）
- 組合: tile=off 與 tile=on；font-size 與 scale 見觀察
- 情境: 400 字元 CJK 長句在真實面板內顯示是否空白／截斷（dry-run 只驗 CPU 端寬度）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S4-06
- 實驗: S4
- 清單條目: 凍結／恢復無可見跳動
- 組合: scheme=A
- 情境: 隱藏 10 秒再顯示（錄影＋日誌 freeze/resume 位置）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S4-07
- 實驗: S4
- 清單條目: 凍結／恢復無可見跳動
- 組合: scheme=B
- 情境: 隱藏 10 秒再顯示（錄影＋日誌 freeze/resume 位置）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 5.2）
- 證據: -
- 重跑: -

### S5-01
- 實驗: S5
- 清單條目: #2 .hudWindow 在 borderless 下的表現
- 組合: style=plain vs style=hud 並列
- 情境: 外觀（陰影、圓角、背景、透明度）、alphaValue 是否生效、是否影響不搶 Focus
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.3）
- 證據: -
- 重跑: -

### S5-02
- 實驗: S5
- 清單條目: #4 performDrag 在非 key 的 nonactivating panel
- 組合: drag=performdrag
- 情境: 拖動是否成功、frontmost 是否不變、mouse-up 是否送達
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.3）
- 證據: -
- 重跑: -

### S5-03
- 實驗: S5
- 清單條目: 第 5.2 節：didMoveNotification 存位置
- 組合: restore=on
- 情境: 拖曳後結束並重啟，位置還原誤差 ≤ 1px（analyze.py position）
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.3）
- 證據: -
- 重跑: -

### S5-04
- 實驗: S5
- 清單條目: 已查證項確認：opaque view 的 mouseDownCanMoveWindow 預設 false
- 組合: drag=none vs performdrag
- 情境: 日誌 config.effective 的 mouseDownCanMoveWindow 與拖曳方式一致
- 日期: -
- macOS: -
- 結果: 未執行
- 原因類別: -
- 佐證: -
- 觀察: 未執行：尚未進行人工輪（任務 3.3）
- 證據: -
- 重跑: -

## 決定

> 全部實驗完成後由任務 6.1 填寫；之前保持「待決定」。`check_results.sh --require-decisions` 在填寫前必定失敗（這是預期的）。

### D1
- 名稱: 全螢幕「已知限制」清單
- 依據: 待決定
- 內容: 待決定

### D2
- 名稱: level 與 collectionBehavior 最終組合
- 依據: 待決定
- 內容: 待決定

### D3
- 名稱: 渲染方案（A displayLink 或 B 線性 CABasicAnimation）
- 依據: 待決定
- 內容: 待決定
- A: 待決定（格式：CPU=平均 RSS=KB WindowServer=平均；另列最大、p95、RSS 起訖差）
- B: 待決定

## 對設計文件的修正建議

（無；若實驗證明設計文件第 5.2 節某設定無效，列於此並回報使用者，不直接修改設計文件。）

## 待確認事項

（任務 6.1 彙整。）
