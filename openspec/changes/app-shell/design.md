## Context

來源：設計文件第 5.2、5.3、6、7、8 節。與舊文件衝突以設計文件為準。標【假設】者尚未經使用者確認，本 change 原樣標示。工具鏈：macOS 26.5.1、Xcode 26.6、Swift 6.3.3、cargo；無 xcodegen／tuist，故用 SwiftPM＋Makefile 組裝 `.app`。spike 用的是未簽名 SwiftPM 可執行檔，與正式 `.app` bundle 環境不同，所以結論需補驗。

## Goals / Non-Goals

**Goals:**
- 把平台相關設定全部集中在薄層（`PanelShell`、`StatusMenu`、`TickerRenderer`），邏輯留在 Core 與可注入的 `FeedClient`，使可用假 helper 做整合測試。
- 所有受 spike 影響的值以單一設定點引用 `spikes/RESULTS.md` 決定章節，避免散落魔術值。
- 驗收區分自動／需人工，避免把需目視的項目假裝成自動測試。

**Non-Goals:** 見 proposal 與設計文件第 10 節。

## Decisions

1. **被 spike 決定的值集中成一個 `ShellConfig`（名稱暫定）**：level、collectionBehavior、渲染方案旗標、計時器種類、是否切塊。實作時由 `spike-decisions` 的最終組合逐項填入；任一項尚未被使用者確認，對應任務保持阻塞。理由：避免自行猜測，也讓日後修正只改一處。
2. **`FeedClient` 以可注入的 helper 路徑與時鐘建構**：生產用 `Bundle.main.url(forAuxiliaryExecutable:)`，環境變數可覆寫（開發用）；測試傳入假 helper 腳本與假時鐘。理由：設計文件 5.3 要求假 helper 整合測試。
3. **generation token**：每次啟動 helper 遞增；`terminationHandler`、`readabilityHandler`、卡死計時器的回呼都帶 token，與當前不符即忽略。理由：避免舊行程事件汙染新行程狀態。
4. **卡死判定**：閾值 = 心跳間隔（設計文件 3 節：至少每 30 秒）× 3 = 至少 90 秒；任何 stdout 位元組都重置計時；`NSWorkspace.didWakeNotification` 後給寬限期（長度【待確認】，暫定 ≥ 一個心跳間隔×3 的重新起算）。
5. **雙實例窗口**：App 啟動時取得 lock／pid file（位置【待確認】，暫定 `~/Library/Application Support/FastBullTicker/`）；若上一個 helper 的 pid 仍存活且其父行程已不在，先終止它再啟動。理由：`kill -9` App 後 helper 靠 stdin EOF 退出需數秒，快速重啟會有兩個 helper 同時輪詢。
6. **簽名順序**：先簽 helper、再簽 App 主執行檔／bundle，最後 `codesign --verify --strict` 驗證；不使用 `--deep`。理由：設計文件 5.3 與風險 4。
7. **點穿不持久化**：不寫入 UserDefaults；啟動即為關。理由：風險 5（點穿模式鎖住自己）。

## Risks / Trade-offs

- [spike 決定未出] → 相關任務被阻塞，不以暫定值提前實作；`ShellConfig` 欄位先留空並使編譯失敗，而非預設猜值。
- [正式 bundle 與 spike 環境不同] → 驗收項 `app-acceptance` 補驗 S1／S2／S3／S4 的核心結論；若結論不成立，列為對 spike 決定的修正並回報使用者。
- [人工驗收多] → tasks 逐項標明硬體與前提；無硬體則該格標「未執行：無硬體」，不得標通過。
- [tasks 容量] → 本 change 已逼近 12 項上限；若 apply 時發現放不下，建議拆為 `app-shell-feed`（`FeedClient`＋假 helper 驗收）與 `app-shell-ui`（面板、選單、持久化、渲染、打包）。

## Open Questions

見各 spec 內標【待確認】項：寬限期長度、lock/pid file 位置、滑桿下限（20% 或 30%）、jitter 比例、不可恢復錯誤的完整分類、`ShellConfig` 與 Core API 的實際型別名稱（待 `show-engine-core` apply 後對齊）、App bundle identifier 與名稱。
