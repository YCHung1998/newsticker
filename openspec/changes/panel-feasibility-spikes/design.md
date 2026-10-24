## Context

設計文件第 6 節把平台行為分成「已查證（官方）」「官方查無（經驗）」「反例回報（未核對）」。本 change 只處理後兩類與渲染方案。工具鏈（已實測）：macOS 26.5.1、Xcode 26.6、Swift 6.3.3，無 xcodegen／tuist，故實驗用 SwiftPM 命令列專案（`spikes/`），以 `swift build` 建置、`swift run` 啟動，組合以命令列參數切換，避免為每種組合重編。

## 設計文件第 6 節「官方查無」逐條對照表

| # | 官方查無的項目 | 對應實驗 | 做法 |
|---|---|---|---|
| 1 | `.nonactivatingPanel` 必須在 init 設定 | S2（對照組） | init 設定 vs 建立後設定，並列記錄 frontmost 變化 |
| 2 | `.hudWindow` 在 borderless 下的表現 | S5(a) | 兩種 styleMask 並列，記外觀與 alpha／Focus |
| 3 | `stationary` 與 `canJoinAllSpaces`、`fullScreen*` 的互斥關係 | S1（移除 `.stationary` 對照） | 對通過組合再各跑一次無 `.stationary` |
| 4 | `performDrag` 在非 key 的 nonactivating panel 上的行為 | S5(b)，並於 S2 拖曳步驟一併觀察 Focus | 記拖動、frontmost、mouse-up 是否送達 |
| 5 | `MenuBarExtra(.window)` 是否搶 Focus | S2（對照組） | 與 `NSStatusItem`＋`NSMenu` 並列 |
| 6 | macOS 26 的行為 | 所有實驗（RESULTS 每格記 `sw_vers`） | 全部在 macOS 26.5.1 實測；其他版本不在範圍 |

另兩項來自第 6 節其他段落、一併涵蓋：
- 「反例回報」（論壇 2025-07 與 thread 759780，未核對）→ S1 全矩陣；不過關即依 `spike-decisions` 停止規則處理。
- 「`didMoveNotification` 存位置」（第 5.2 節）→ S5(c)。
- 「降幀實效未查」（第 6 節已查證項註記）→ S4 的 30fps 驗證。
- 「選單追蹤用 `NSEventTrackingRunLoopMode`，預設 mode `Timer` 停擺」（已查證）→ S3 以實測確認並比較三種計時器。

## Decisions

1. **實驗為丟棄式**：放 `spikes/`，不進 `FastBullTickerCore`／`FastBullTicker`，只有 `RESULTS.md` 的決定往下游傳。理由：避免實驗碼的捷徑污染正式碼。
2. **S5 另列**：第 6 節有兩條（`.hudWindow`、`performDrag`）及 `didMove` 不屬 S1–S4 原定範圍，另列 S5 而非塞入 S2，以保持 S2 判定單純（只看 Focus）。
3. **組合用參數切換**：S1 四種組合×多情境，每格人工成本高，程式碼不重編以減少變因。
4. **證據優先**：每格要有截圖／日誌路徑，結果檢查腳本驗證路徑存在；無證據只能寫「未驗證」。
5. **S4 不設絕對門檻**：設計文件的「CPU 穩定偏低」等無數字，本 change 暫以相對比較決定，絕對門檻列待釐清，不自行發明。
6. **自動／人工分離**：實驗程式的建置與日誌解析自動；全螢幕、睡眠、外接螢幕、拖曳、選單操作、一小時觀察需人工。S3 的選單展開維持人工，不用 System Events 自動化（見下方「使用者決定」）。

## Risks / Trade-offs

- S1 可能全數失敗 → 需求變更，停止並回報（見 `spike-decisions`）。
- S1 結果依賴使用者環境（外接螢幕、已安裝 Keynote）；缺硬體的格必須標「未執行」並說明，而非省略。
- S4 各一小時，兩方案間可能受背景負載影響；以相同條件、記錄背景狀況降低偏差，但無法完全排除。
- 實驗 App 為未簽名的 SwiftPM 可執行檔，與正式 `.app` bundle（`LSUIElement`、ad-hoc 簽名）環境不同，可能影響 accessory 行為；實驗程式須以 `NSApp.setActivationPolicy(.accessory)` 模擬，差異列入已知限制，由 `app-shell` 端到端驗收補驗。
- 量測 WindowServer 負載只用 `ps`；`ps` 無法提供 GPU 或更細的 WindowServer 負載，數字為 CPU 時間換算，解讀時須註明此限制（使用者決定不用 `powermetrics`）。

## 使用者決定（2026-10-24）

1. **失敗的歸因規則**：RESULTS 每格有「原因類別」欄；FAIL 必須是 `平台限制`（附排除我方錯誤的佐證）或 `實作錯誤`（修正後重跑，不得記為已知限制）。只有 `平台限制` 可進「已知限制」。落實於 `spike-protocol`（失敗的歸因規則）、`spike-decisions`（已知限制清單）、`spikes/check_results.sh`。
2. **權限最小化**：不用 sudo、`powermetrics`、輔助使用權限、螢幕錄製權限或任何會彈出權限對話框的 API。WindowServer／CPU／RSS 只用 `ps`／`top`；截圖與錄影由使用者以系統快捷鍵／內建工具手動完成並放到 `spikes/out/evidence/<格代號>/`；S3 選單操作維持人工。落實於 `spike-protocol`（權限最小化與不打擾）。
3. 以下【假設】維持原樣、不升級：「常用全螢幕 App」＝Safari 加 Keynote 或 QuickTime；S4 無絕對門檻先做兩案相對比較；面板約 620×42 與字型大小。
4. **apply 階段驗證限制**：使用者正在使用該機器，apply 階段不得啟動任何會出現視窗的實驗程式；驗證僅限 `swift build`、腳本對構造資料的紅綠測試、以及不建立視窗的 dry-run／headless 自測。每個實驗程式因此提供 `--dry-run`（見 `spike-protocol`「實驗程式提供不建立視窗的 dry-run」）。

## 待釐清（標【待確認】，不自行補猜）

1. **「常用全螢幕 App」範圍**：本規格暫定 Safari＋(Keynote 或 QuickTime)；是否含瀏覽器以外（如 Xcode、Terminal、遊戲）？
2. **S1 降級接受**：部分全螢幕 App 蓋不過時「接受並記錄已知限制」為設計文件的預設【假設】，需使用者確認；此為需求變更。
3. **S4 數字門檻**：「CPU 穩定偏低」「記憶體曲線平坦」的數字（例如 CPU 上限、RSS 增長容忍）使用者未定。
4. ~~WindowServer 量測方式~~：**已由使用者決定（2026-10-24）**：只用 `ps`／`top`，不用 `powermetrics`／sudo。
5. **實驗用面板尺寸與字型大小**：暫用約 620×42【假設】；字型大小影響 400 字元 bitmap 寬度（是否超過約 16384px），需使用者確認或以預計正式字型大小為準。
6. **外接螢幕與 Keynote 可得性**：使用者是否有外接螢幕與 Keynote；無則該格標未執行。
7. **兩案皆達標時的預設擇優**（選較單純者）為【假設】。
8. **`.floating` vs `.statusBar` 無差異時的預設選擇**為【假設】。
9. **`RESULTS.md` 檔名**為建議，設計文件未指定。
