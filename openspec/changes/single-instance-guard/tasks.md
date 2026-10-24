## 1. 規格與守衛

- [x] 1.1 `openspec validate single-instance-guard --strict` 與 `openspec validate --all --strict` 通過。驗證：該兩指令。【自動】
- [x] 1.2 守衛測試修改：`OpenerGuard.activationViolations` 與 `PanelShellTests.sourcesNeverCallApplicationActivation` 放行且僅放行 `SingleInstanceGuard.swift`（且該檔恰一處呼叫）；植入其他檔案仍失敗。驗證：`swift test --filter "LinkOpenerGuard|PanelShell|SingleInstanceGuard"`。【自動】

## 2. 決策邏輯（純）

- [x] 2.1 `SingleInstanceGuard.swift`：協定 `RunningInstancesProvider`／`AlertPresenter`／`InstanceTerminator`／`Sleeper` 與 `SingleInstanceGuard.run()`（排除自己、競態、環境變數、關閉流程 5s／2s）。驗證：先紅（測試先寫、型別不存在或斷言失敗）再綠，`swift test --filter SingleInstanceGuardTests`。【自動】
- [x] 2.2 測試涵蓋：無其他→繼續；取消→結束且未 terminate；關閉→terminate→消失→繼續；5 秒仍在→force；force 後仍在→第二提示並結束；不提前繼續；對方較晚→不詢問；launchDate 相同／缺漏以 pid；環境變數 1／0；terminate 只對其他 pid；多個其他實例。【自動】

## 3. 真實實作與接線

- [x] 3.1 `NSAlertPresenter`（含唯一一處 `NSApp.activate()`，旗標限一次）、`SystemInstanceTerminator`（`kill(pid,0)`）、`RunLoopSleeper`、`NSRunningApplication` provider。驗證：`swift build`；靜態守衛。【自動】（真實對話框【需人工】）
- [x] 3.2 `AppDelegate.applicationDidFinishLaunching` 最前段呼叫，結束時 `NSApp.terminate(nil)` 並 return；`instanceCheck` 可注入。驗證：靜態順序測試（檢查 guard 呼叫位於 `PanelShell(` 與 `startFeed(` 之前）。【自動】

## 4. Mutation、文件、總驗證

- [x] 4.1 `Tests/g1-mutations.py`：不排除自己、取消仍繼續、不等就繼續、不 force、競態兩邊皆詢問、他檔 activate 守衛、等。全部變紅，輸出摘要寫入 `Tests/README.md`。【自動】
- [x] 4.2 `README.md`（操作、已知限制、`FASTBULL_TICKER_ALLOW_MULTIPLE`、驗證數字）。驗證：人工閱讀。【需人工】
- [x] 4.3 全量：`swift build`、`make helper app sign test`、`swift test`（≥481）、`codesign --verify --strict build/FastBullTicker.app`、`sh Tests/app-packaging-check.sh`、`cargo test`、`python3 -m unittest discover -s protocol/tests`、`cd spikes && swift build && tests/run_script_tests.sh`。【自動】
- [ ] 4.4 人工驗收：(a) 已有一個在跑時再啟動第二個會跳對話框；(b) 取消→第二個結束、第一個不受影響；(c) 關閉→第一個結束、第二個正常啟動、`pgrep -fl ticker-connect` 只有一個 helper；(d) 同時啟動兩個不會兩邊都跳。【需人工】
