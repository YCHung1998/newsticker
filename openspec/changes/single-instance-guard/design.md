## Context

`applicationDidFinishLaunching` 目前直接建立面板並啟動 `FeedClient`。兩實例共用 pid 檔會互相回收 helper。App 為 accessory（無 Dock），既有規定「永不呼叫 `NSApp.activate`」；但 `NSAlert.runModal()` 在 accessory App 中若不啟用，對話框會藏在其他視窗後面，使用者看不到。

## Goals / Non-Goals

- Goals：啟動最前段偵測重複實例；詢問；可靠關閉舊實例；競態不雙跳窗；決策邏輯 100% 可用假物件測試。
- Non-Goals：不做跨使用者／跨機器偵測；不改 pid 檔機制；不用檔案鎖或 XPC；不處理非 bundle 啟動（`swift run`，無 bundle identifier 時視為無需檢查）。

## Decisions

1. **偵測**：`NSRunningApplication.runningApplications(withBundleIdentifier:)`，排除自己的 pid。替代方案（lock file／distributed notification）較複雜且 kill -9 後遺留鎖；`NSRunningApplication` 由系統維護，無遺留問題。
2. **注入**：`RunningInstancesProvider`（回傳含自己的 `[InstanceInfo(pid, launchDate)]`，由 guard 排除自己，使「不排除自己」能被測試抓到）、`AlertPresenter`（`confirmReplace() -> ReplaceChoice`、`showCannotClose()`）、`InstanceTerminator`（`terminate(pid)`／`forceTerminate(pid)`／`isRunning(pid)`）、`Sleeper`（`sleep(seconds)`）。輪詢以「累計睡眠秒數」計時（每 0.1 秒），不需時鐘，測試用假 Sleeper 即時推進。
3. **競態【假設】**：自己要詢問，當且僅當自己對所有其他實例都「較晚」。比較鍵 `(launchDate, pid)`：兩邊 launchDate 都有且不同 → 較大者較晚；否則（相同或任一缺漏）pid 較大者較晚。較早者不詢問、照常執行；較晚者詢問並負責關舊的。
4. **關閉流程**：`terminate()` → 輪詢最多 5 秒 → 仍在者 `forceTerminate()` → 輪詢最多 2 秒 → 仍在 → `showCannotClose()` 並結束新實例。注意舊實例優雅結束最多約 6 秒（helper 收尾），而規格指定 5 秒；5 秒後 force 可能中斷其收尾，helper 殘留由新實例的 `reclaimStaleHelper`（pid 檔）處理。此為已知取捨。
5. **存活判定（真實實作）**：`kill(pid, 0)`（成功或 `EPERM` 視為存活）。理由：guard 在主執行緒阻塞輪詢，`NSRunningApplication.isTerminated` 依賴 run loop 更新；`kill(0)` 不依賴。`terminate`／`forceTerminate` 經 `NSRunningApplication(processIdentifier:)`。Sleeper 真實實作以 `RunLoop.current.run(until:)` 等待。
6. **`NSApp.activate` 例外**：僅在 `NSAlertPresenter`（`SingleInstanceGuard.swift` 內）顯示對話框前呼叫 `NSApp.activate()`，以旗標確保整個程序最多一次。守衛測試改為：該檔以外零呼叫，該檔內恰好一次。
7. **結束新實例**：此時 `feed == nil`，`applicationShouldTerminate` 立即 `.terminateNow`，不會留下 helper；之後 `return` 不建面板。
8. **接線可注入**：`AppDelegate.init` 增加 `instanceCheck` 參數（預設為真實 guard），避免任何建構 `AppDelegate` 的測試觸發真實對話框。
9. **跳過開關【假設：名稱】**：`FASTBULL_TICKER_ALLOW_MULTIPLE=1`（精確等於 "1"）。

## Risks / Trade-offs

- 舊實例優雅結束 >5 秒被 force → 其 helper 可能暫時殘留 → 新實例啟動時 pid 檔回收機制處理。
- launchDate 解析度／缺漏 → 退回 pid 比較；極端下兩邊都認為自己「較早」不詢問 → 退化為舊行為（可接受，不會雙跳窗）。
- 阻塞主執行緒最多 7 秒 → 此時尚無 UI，可接受。
- 對話框期間舊實例正常運作；使用者不回應則一直等待（模態）。

## Migration Plan

純新增行為，無資料遷移。回滾：還原 `AppDelegate` 呼叫與新檔。

## Open Questions

- 5 秒／2 秒時限、按鈕文字、環境變數名稱皆為【假設】，待使用者確認。
