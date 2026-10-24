前置：設計文件第 5.2、5.3、6、7、8 節；`show-engine-core` 已 apply（Core API 與 `Package.swift`）；`connect-engine-fastbull` 已 apply（真 helper）；`panel-feasibility-spikes` 已 apply 且 `spikes/RESULTS.md` 決定章節經使用者確認。每項標【自動】／【需人工】／【被 spike 決定阻塞】（可複合）；只標依賴與前提，不估工時。每個階段回報須附實際指令與測試檔路徑；改邏輯的項目須有 fail-then-pass 證據。

## 1. 建置與簽名

- [ ] 1.1 【自動】Makefile（`helper`／`app`／`sign`／`test`）、`Resources/Info.plist`（`LSUIElement=YES`、`LSMinimumSystemVersion`）、bundle 組裝、由內而外簽名與驗證、helper 路徑環境變數覆寫。依賴：`show-engine-core` 的 `Package.swift`、`connect-engine-fastbull` 可 `cargo build`。驗證方式：`make helper app sign` 成功；`codesign --verify --strict -vv FastBullTicker.app`；`grep -- "--deep" Makefile` 無結果；改 helper 一位元組後 verify 先失敗、重新 `make sign` 後通過（fail-then-pass）；`plutil -p` 顯示 `LSUIElement`。

## 2. FeedClient

- [ ] 2.1 【自動】`FeedClient` 核心：`Process`＋`Pipe`、`Bundle.main.url(forAuxiliaryExecutable:)`、generation token、stderr 讀走、EOF 清除 handler、指數退避 1→60 秒加 jitter（純函式，注入時鐘與亂數）、資料交給 Core `LineBuffer`；測試用假 helper 腳本（正常、崩潰、半行、stderr 灌滿）。依賴：`show-engine-core` 的 `LineBuffer`／協定型別。驗證方式：App 層測試（路徑【待確認】，如 `Tests/FastBullTickerTests/FeedClientTests.swift`）以 `swift test --filter FeedClient` 執行；每情境先對缺實作版本失敗再通過；退避以假時鐘斷言序列與「穩定 >60 秒才重置」。
- [ ] 2.2 【自動】`FeedClient` 韌性：卡死判定（≥3×心跳、任何輸出算活著）、`didWakeNotification` 寬限、不可恢復錯誤不重啟、結束流程（關 stdin→逾時 SIGTERM）、lock／pid file 雙實例處理；假 helper 補「卡死」「忽略 EOF」「無 +x」「缺檔」。依賴：2.1。驗證方式：`swift test --filter FeedClientResilience`；假時鐘斷言卡死閾值與寬限；缺檔情境嘗試次數為 1；pid file 測試以假行程驗證只剩一個實例；fail-then-pass 證據。

## 3. Persistence 與面板外殼

- [ ] 3.1 【自動】`Persistence`：螢幕 UUID＋相對偏移＋透明度存取、`didMoveNotification` debounce（注入時鐘）、螢幕缺失退回主螢幕與夾制純函式、`didChangeScreenParametersNotification` 重新夾制。依賴：無（可與 2 平行，但流程循序）。驗證方式：`swift test --filter Persistence`；夾制測試先對未夾制版本失敗；debounce 測試 50 次事件僅寫一次。
- [ ] 3.2 【自動＋被 spike 決定阻塞】`PanelShell`：`[.borderless, .nonactivatingPanel]` init 一次設定、`hidesOnDeactivate=false`、`canBecomeKey/Main=false`、`hasShadow=false`、`isOpaque=false`、`.clear` 背景、window `alphaValue`、`performDrag(with:)`、accessory、永不 `NSApp.activate`；level／collectionBehavior 取自 `ShellConfig`，值逐項來自 `RESULTS.md` 決定章節。依賴：spike 決定（S1 最終組合、S5 `performDrag` 結論）已由使用者確認；3.1。驗證方式：`swift test --filter PanelShell` 斷言所有屬性實際值；`grep -rn "activate(" Sources/FastBullTicker/` 無啟用呼叫；`ShellConfig` 與 RESULTS 逐項比對並附格代號。
- [ ] 3.3 【自動＋被 spike 決定阻塞】`StatusMenu`：`NSStatusItem`＋`NSMenu`（滑桿 `NSMenuItem.view`、隱藏／顯示、點穿、結束）、面板右鍵同一份選單、點穿不持久化且啟動重置、補料計時器種類取自 S3 決定。依賴：3.2；spike S3 決定。驗證方式：`swift test --filter StatusMenu`（項目齊全、點穿不寫入存檔、重建後為關、滑桿下限值）；計時器種類與 RESULTS 決定一致並附格代號。

## 4. 渲染與組裝

- [ ] 4.1 【自動＋被 spike 決定阻塞】`TickerRenderer` 協定與依 S4 決定的實作：消費 `TickerScheduler` 輸出、每則 bitmap 預渲染、依 S4 切塊、遮蔽（`didChangeOcclusionStateNotification`）與隱藏凍結、rebase 無跳動。依賴：spike S4 渲染方案決定；`show-engine-core` 的 Scheduler／版面輸出。驗證方式：`swift test --filter TickerRenderer`（測試替身驅動呼叫序列、切塊寬度總和、rebase 位置不變）；另附實作方案與 RESULTS 決定一致的檢查。
- [ ] 4.2 【自動】組裝 `AppDelegate`：串接 `FeedClient`→Core→`TickerScheduler`→`TickerRenderer`／`PanelShell`／`StatusMenu`，結束流程；以假 helper 啟動做 headless 煙霧測試（不顯示 UI 的邏輯串接）。依賴：2.2、3.3、4.1。驗證方式：`make test` 全過；煙霧測試以假 helper 餵 snapshot 與 items，斷言 Scheduler 收到並進入 REPLAY→LIVE；`swift build` 無警告。

## 5. 端到端驗收

- [ ] 5.1 【需人工】假 helper→真 helper 與 helper 生命週期：`kill -9` App 後無孤兒、睡眠喚醒後心跳不誤判、複製進 bundle 並簽名後 helper 可啟動。使用者要做：在機器前啟動 `.app`、執行 `kill -9`、讓機器睡眠並喚醒、目視帶子顯示真訊息。硬體：本機可睡眠、需網路。前提：4.2、`make helper app sign` 完成。依賴：4.2。驗證方式：`pgrep ticker-connect` 於 `kill -9` 後 5 秒內為空【暫定】；日誌顯示喚醒後無誤判重啟；結果寫入 `ACCEPTANCE.md`（路徑待確認）。
- [ ] 5.2 【需人工】螢幕參數變更：拔插外接螢幕、改解析度、鏡像後面板至少部分可見，下次啟動回到正確螢幕。使用者要做：拔插螢幕、改顯示器設定、重啟 App。硬體：**外接螢幕一台**；無則標「未執行：無硬體」。依賴：3.1、4.2。驗證方式：每格 PASS／FAIL／未執行（含原因）與截圖，寫入 `ACCEPTANCE.md`。
- [ ] 5.3 【需人工＋被 spike 決定阻塞】在正式簽名 `.app` 補驗 spike 結論：S1 最終組合全螢幕可見（全螢幕 Safari、Keynote 或 QuickTime、Space 切換）、S2 不搶 Focus（TextEdit 持續打字，frontmost 不變、啟用通知為零）、S3 選單展開 60 秒不斷料、S4 所選方案無可見抖動與凍結／恢復無跳動。使用者要做：進入全螢幕、打字並操作選單、目視帶子。硬體：本機（全螢幕情境另需外接螢幕者依 S1 矩陣）。依賴：4.2、spike 決定。驗證方式：`ACCEPTANCE.md` 每項 PASS／FAIL 含截圖或日誌；任一不成立回報使用者為「對 spike 決定的修正」，不自行改決定。
- [ ] 5.4 【需人工】記憶體基準與 VPN／Proxy：運行 ≥10 分鐘量 App 與 helper RSS（`ps -o rss=`）；在使用者實際 VPN／Proxy 下驗證 helper TLS。使用者要做：開啟 VPN／Proxy 後啟動 App、提供結果。硬體：本機；VPN／Proxy 環境由使用者提供，無則標「未執行：無環境」。依賴：5.1。驗證方式：`ACCEPTANCE.md` 含 RSS 基準與是否低於 App ≤35MB／helper ≤15MB【假設】；跑完後 `openspec validate app-shell --strict` 與其餘四個 change 的 `--strict` 皆通過；回報列出實際指令與結果檔路徑。
