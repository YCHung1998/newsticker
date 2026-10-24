前置：設計文件第 5.2、6、7、8 節；工具鏈 macOS 26.5.1、Xcode 26.6、Swift 6.3.3（SwiftPM 命令列）。**本 change 的 apply 才建立 `spikes/`。** 每項標「自動」或「需人工」；需人工項的「使用者要做什麼／硬體／前提」寫在該項內。依賴以「依賴」標示，不估工時。每個階段回報須附實際指令與結果檔路徑（`spikes/RESULTS.md`、日誌、CSV）。

## 1. 骨架與紀錄

- [ ] 1.1 【自動】建立 `spikes/` SwiftPM 專案骨架（共用 harness：可由命令列參數建立測試面板、寫日誌、列出 `sw_vers`）與 `spikes/RESULTS.md` 範本，以及 `spikes/check_results.sh`（驗證格式：日期、macOS 版本、組合、結果、證據路徑存在；驗證「決定」章節完整）。依賴：無。驗證方式：`cd spikes && swift build` 成功；`spikes/check_results.sh` 對含缺欄位的樣本 RESULTS 回報錯誤（先失敗），對完整樣本通過（fail-then-pass）。

## 2. S1 全螢幕可見性

- [ ] 2.1 【自動】實作 S1 實驗程式：面板（`[.borderless, .nonactivatingPanel]`、`hidesOnDeactivate=false`）、`--level`、`--join-all-apps`、`--stationary` 參數、生效值寫入日誌、截圖輔助腳本（`screencapture`）。依賴：1.1。驗證方式：`swift build`；以四種參數組合各啟動一次，日誌中的實際 level／collectionBehavior 與參數逐項相符（腳本比對）。
- [ ] 2.2 【需人工】執行 S1 第一輪：全螢幕 Safari、全螢幕 Keynote 或 QuickTime、Split View、切換 Space，4 組合 × 情境，截圖並寫入 RESULTS。使用者要做：依腳本提示進入各全螢幕情境、切換 Space、確認截圖。硬體：僅本機。前提：已裝 Safari 與 Keynote 或 QuickTime；螢幕不被其他工作占用。依賴：2.1。驗證方式：`spikes/check_results.sh` 通過，且上述每格皆為 PASS／FAIL／未執行（含原因）。
- [ ] 2.3 【需人工】執行 S1 第二輪：Stage Manager 開／關、外接螢幕（「螢幕有獨立 Space」開與關各一次）、睡眠喚醒後，並對通過組合補跑「無 `.stationary`」對照。使用者要做：開關系統設定、插拔外接螢幕、讓機器睡眠並喚醒。硬體：**外接螢幕一台**。前提：可變更系統設定；睡眠測試期間不執行其他重要工作。依賴：2.2。驗證方式：`spikes/check_results.sh` 通過；無外接螢幕則該格標「未執行：無硬體」。若 S1 無組合通過，依 `spike-decisions` 停止並回報使用者。

## 3. S2／S5 Focus 與拖曳

- [ ] 3.1 【自動】實作 S2／S5 實驗程式：`didActivateApplicationNotification` 與 `frontmostApplication` 取樣日誌、打字字串比對腳本、`NSStatusItem`＋`NSMenu` 與 `MenuBarExtra(.window)` 兩版選單、styleMask init vs 事後設定對照、`.hudWindow` 對照、`performDrag` 與 `didMoveNotification` debounce 存位置。依賴：1.1。驗證方式：`swift build`；以腳本餵入假日誌，判定器對「frontmost 改變」「本 App 啟用通知」「缺字」各回報失敗，對正常樣本通過（fail-then-pass）。
- [ ] 3.2 【需人工】執行 S2：在 TextEdit 持續輸入已知字串，同時點擊／拖曳面板、操作選單列選單與滑桿，兩種選單版本與兩種 styleMask 設定時機各跑一次。使用者要做：邊打字邊操作。硬體：僅本機。前提：TextEdit 開啟空白文件；輔助功能權限非必需。依賴：3.1。驗證方式：日誌判定器輸出 PASS／FAIL，結果與日誌路徑寫入 RESULTS；通過標準為 frontmost 不變、無缺字、本 App 啟用通知 0。
- [ ] 3.3 【需人工】執行 S5：`.hudWindow` 外觀對照截圖、`performDrag` 拖曳（是否拖動、mouse-up 是否送達）、拖曳後結束並重啟驗證位置還原。使用者要做：滑鼠拖曳面板、結束再重啟 App。硬體：僅本機。前提：3.1 完成。依賴：3.1。驗證方式：RESULTS 的 S5 各格含截圖或日誌；重啟後位置還原由程式輸出座標比對（誤差 ≤ 1px）。

## 4. S3 選單補料計時器

- [ ] 4.1 【自動】實作 S3 實驗程式：假帶子、補料計時器三種（預設 mode `Timer`、`.common` `Timer`、`DispatchSourceTimer`）、預定／實際觸發時間日誌與尾端空位記錄、誤差統計腳本（最大、p99、漏補次數）。依賴：1.1。驗證方式：`swift build`；統計腳本對人為構造的日誌（含 150ms 誤差與漏補）回報失敗，對正常日誌通過。
- [ ] 4.2 【需人工】執行 S3：每種計時器展開選單 ≥ 60 秒並持續拖動滑桿。使用者要做：點開選單、保持展開、拖動滑桿，並目視帶子有無空白。硬體：僅本機。前提：4.1 完成；三種計時器各跑一次（總計約數分鐘整段不被打擾）。依賴：4.1。驗證方式：統計腳本輸出寫入 RESULTS；通過標準為誤差 < 100ms、帶子無空白、滑桿即時生效。

## 5. S4 渲染 A/B

- [ ] 5.1 【自動】實作 S4 實驗程式：方案 A（`NSView.displayLink`）與 B（線性 `CABasicAnimation`）、10 則假訊息（含 400 字元 CJK 長句）、預渲染 bitmap 寬度測試（含切塊選項）、`preferredFrameRateRange` 30fps 開關、幀間隔記錄、CPU／RSS／WindowServer 的 CSV 取樣腳本、CSV 統計腳本（平均、最大、p95、RSS 起訖差）。依賴：1.1。驗證方式：`swift build`；跑 2 分鐘煙霧測試，CSV 筆數與取樣間隔相符；bitmap 寬度測試輸出像素寬度與是否超過 16384。
- [ ] 5.2 【需人工】執行 S4：方案 A、B 各 1 小時，另做 30fps 實效驗證與凍結／恢復目視（隱藏 10 秒再顯示，錄影）。使用者要做：啟動、讓機器插電並不動它、在指定時點目視文字有無抖動與跳動、結束後確認錄影。硬體：本機；前提：插電、關閉螢幕保護與睡眠、其他重負載程式關閉；總計至少兩個整段一小時（含設定時間）。依賴：5.1。驗證方式：兩份 CSV（各 ≥ 360 筆）與統計輸出寫入 RESULTS；30fps 與切塊結果有證據路徑。

## 6. 決定與收尾

- [ ] 6.1 【需人工】彙整三項決定寫入 RESULTS「決定」章節（已知限制、level＋collectionBehavior 最終組合、渲染方案含 A/B 數字），並列出待確認事項與「對設計文件的修正建議」，呈交使用者確認。使用者要做：審閱並確認降級假設（接受已知限制）、擇優理由與待釐清項。硬體：無。依賴：2.3、3.2、3.3、4.2、5.2。驗證方式：`spikes/check_results.sh` 完整性檢查通過（三項皆有、引用格代號存在、渲染方案含 A/B 兩者三項數字）；`openspec validate panel-feasibility-spikes --strict`、`openspec validate message-contract --strict`、`openspec validate connect-engine-fastbull --strict` 皆通過；回報須列出實際指令與結果檔路徑。
