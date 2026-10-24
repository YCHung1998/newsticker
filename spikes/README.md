# spikes — 可行性實驗（丟棄式）

change：`panel-feasibility-spikes`。這裡是獨立的 SwiftPM 專案，**不依賴、也不被**根目錄 `Package.swift`／`Sources/`／`Tests/` 引用；實驗結論只以 `RESULTS.md` 的「決定」章節傳給下游。所有指令都在 `spikes/` 目錄下執行。

目前狀態：5 個「自動」任務（1.1、2.1、3.1、4.1、5.1）完成；**所有實驗結果格都是「未執行」**，等使用者做人工輪（見最後一節）。

## 權限最小化（使用者決定，2026-10-24）

實驗與腳本**不使用** sudo、powermetrics、輔助使用（Accessibility）權限、螢幕錄製權限，也不呼叫任何會彈出權限對話框的 API；程式也不呼叫 `NSApp.activate`。

- CPU／RSS／WindowServer：只用 `ps`（`scripts/sample_proc.sh`）。
- 截圖／錄影：**由你手動**完成，腳本不截圖。
  - 截圖：Shift-Command-3（全螢幕）或 Shift-Command-5（選項 → 儲存位置 → 其他位置，指到 `spikes/out/evidence/<格代號>/`）。預設會存到桌面，再手動搬進該資料夾即可。
  - 錄影：Shift-Command-5 的「錄製螢幕」，同樣存到該資料夾。
  - RESULTS 的「證據」欄填相對於 `spikes/` 的路徑，如 `out/evidence/S1-01/safari.png`；日誌在 `out/*.log`。（`out/` 已被 `.gitignore` 排除，不進版控。）
- S3 的選單操作維持人工（不用 System Events）。

## 建置與目錄

```
swift build                      # 產生 .build/debug/{spike-s1,spike-focus,spike-s3,spike-render}
Sources/SpikeKit                 # 共用：Args（嚴格參數）、EventLog、PanelConfig/面板工廠、TextBitmap、假訊息
Sources/SpikeS1                  # S1 全螢幕可見性
Sources/SpikeFocus               # S2 不搶 Focus + S5 面板補充（含 MenuBarExtra(.window) 對照）
Sources/SpikeS3                  # S3 選單展開補料計時器
Sources/SpikeRender              # S4 渲染 A/B、bitmap 寬度、凍結／恢復
scripts/analyze.py               # 判定器與統計（s1config focus typing s3 csv frames position）
scripts/sample_proc.sh           # 只用 ps 的 CPU/RSS/WindowServer CSV 取樣
scripts/check_results.sh         # RESULTS.md 格式與決定完整性檢查
tests/run_script_tests.sh        # 腳本的紅綠(fail-then-pass)驗證，fixtures 在 tests/fixtures/
RESULTS.md                       # 結果範本（54 格，全部「未執行」）
```

日誌格式：`<ISO8601含毫秒>\t<event>\t<k=v ...>`；每次啟動都寫 `start`（含 `sw_vers`）、`config.requested`、`config.expected`；真實面板建立後再寫 `config.effective`（從面板讀回的值）。

## 不建立視窗的 dry-run（apply 階段可驗證的部分）

每支實驗程式都有 `--dry-run`：只解析參數、列印並寫入「將會套用的生效值」後結束，`dryrun.done window-created=false`。

```
.build/debug/spike-s1 --dry-run --level statusBar --join-all-apps on        # 看 config.expected
.build/debug/spike-focus --dry-run --menu menubarextra --nonactivating after --style hud
.build/debug/spike-s3 --dry-run --timer dispatch
.build/debug/spike-render --dry-run --font-size 21 --tile on                # 另列 10 則訊息的 bitmap 像素寬度（CoreText，無視窗）
.build/debug/spike-render --bitmap-width-test --font-size 21 --tile off
.build/debug/spike-s3 --headless-selftest --timer default --selftest-seconds 6   # 無視窗，模擬選單追蹤 run loop mode
```

dry-run **不能**驗證的（留給人工輪）：面板實際讀回的 level／collectionBehavior（`config.effective`）、可見性、Focus、渲染 CPU／幀間隔、GPU 紋理上限（dry-run 只證明 CPU 端 CGContext 能畫出該寬度，不代表 layer 在 GPU 上不被截斷）。

## 腳本的紅綠證據（可重現）

```
cd spikes && swift build && tests/run_script_tests.sh
```

這支測試腳本對**人為構造的壞資料**必須回報失敗（RED，退出碼 1），對正常資料必須通過（GREEN，退出碼 0）；任何一項結果與預期不符就整體失敗。不啟動任何實驗程式視窗。共 41 項，涵蓋：

| 腳本 | 紅（構造的壞資料） | 綠 |
|---|---|---|
| `check_results.sh` | 缺日期、缺 macOS、證據路徑不存在、FAIL 無原因類別、`平台限制` 無佐證、`實作錯誤` 無重跑、結果值非法、未執行無原因、D1 引用 `實作錯誤`／不存在／未執行的格、D3 缺數字、D2 用 `.screenSaver`、D2 引用 FAIL 格、出貨範本加 `--require-decisions`（範本尚未決定，必須失敗） | 完整樣本（含決定）、出貨範本（僅格式） |
| `analyze.py s1config` | 日誌 level.raw 錯、behavior 缺項、假的 dry-run 程式（statusBar 回報 3） | 日誌正確；真的 `spike-s1 --dry-run` 8 種組合全相符 |
| `analyze.py focus`/`typing` | frontmost 變成 Finder、本 App 的 didActivate、打字缺一個字元 | 正常日誌＋正常打字 |
| `analyze.py s3` | 150ms 誤差、漏補 2 格、尾端空位為負（空白）、選單只開 15 秒 | 最大誤差 15ms、選單 70 秒、有滑桿回呼 |
| `analyze.py csv` | 100 列（<360）、取樣間距 25 秒、非數值欄位 | 360 列 @10 秒 |
| `analyze.py frames`/`position` | 無 frames 事件、還原位置差 59.5px | 有資料、還原誤差 0 |
| `spike-s1` 參數 | `--level screenSaver` 以退出碼 2 拒絕 | — |

`analyze.py` 統計定義：誤差 = 實際觸發 − 預定（ms）；p99 為 nearest-rank；漏補 = 預定格（slot）序列中沒有觸發的格數；空白 = 補料前 `gap_before < 0` 的次數；S3 判定門檻 max 誤差 < 100ms、漏補 0、空白 0、選單展開 ≥ 60 秒。

取樣腳本煙霧測試（無視窗）：對 `yes > /dev/null` 行程跑 `scripts/sample_proc.sh --pid <pid> --out out/smoke-sample.csv --interval 10 --duration 120`，得 12 列（= 120/10），`analyze.py csv --min-rows 12` 通過（App CPU 約 99.5%）。

## RESULTS.md 填寫與檢查

```
scripts/check_results.sh                        # 格式檢查（日期、macOS、組合、結果、原因類別、佐證、證據路徑存在）
scripts/check_results.sh --require-decisions    # 另檢查「決定」章節（任務 6.1 完成後才應通過）
```

規則（使用者決定，2026-10-24）：每格要有**原因類別**。FAIL 必須是 `平台限制`（macOS 本身不允許或行為不符，已排除我方實驗程式問題；**必須附佐證**：同一程式在另一組合通過、對照組格代號、日誌中的系統回傳值…）或 `實作錯誤`（實驗程式的 bug；**不得記成已知限制**，要修正後重跑，並在「重跑」欄填重跑格代號）。只有 `平台限制` 可進「已知限制」。

## 人工輪操作摘要（詳細清單見回報／tasks.md）

先 `swift build`。所有程式都從選單列的狀態項目 Quit 結束，或用 `--duration 秒數` 自動結束，或在另一個終端機 `pkill -x spike-s1`（程式名同 binary）。

- **2.2／2.3 S1**：`.build/debug/spike-s1 --level floating|statusBar --join-all-apps on|off [--stationary off] --duration 600`，進入各全螢幕情境，手動截圖；結束後 `python3 scripts/analyze.py s1config --log out/s1-*.log` 確認 `config.effective` 與參數相符。
- **3.2 S2**：`.build/debug/spike-focus --menu statusitem|menubarextra --nonactivating init|after --target-bundle com.apple.TextEdit --duration 180`；在 TextEdit 連打 `abcdefghij` 重複，操作面板與選單；之後把 TextEdit 內容存成純文字，`python3 scripts/analyze.py focus --log out/focus-*.log --target-bundle com.apple.TextEdit --typed-file <文字檔>`。
- **3.3 S5**：`spike-focus --style plain|hud`、`--drag performdrag`、`--restore on --position-file out/s5-position.json`；拖曳後等 0.5 秒結束，再以 `--restore on` 重啟；`python3 scripts/analyze.py position --before <第一次log> --after <第二次log>`。
- **4.2 S3**：`.build/debug/spike-s3 --timer default|common|dispatch --duration 300`；點選單列「S3:…」展開選單 ≥ 60 秒並持續拖滑桿；`python3 scripts/analyze.py s3 --log out/s3-*.log --require-slider`。
- **5.2 S4**：`.build/debug/spike-render --scheme A|B --duration 3700`，另開終端機 `scripts/sample_proc.sh --pid <spike-render 的 pid> --out out/s4-A.csv --duration 3660`；結束後 `python3 scripts/analyze.py csv --file out/s4-A.csv`。30fps：`--fps-cap 30`（B 加 `--frame-observer on`），`analyze.py frames --log ...`。長句：`--font-size N --tile on|off`。凍結／恢復：`--auto-hide-at 120` 或選單「Hide 10s then show」，日誌 `freeze`／`resume`／`resume.after100ms` 有位置數字，再配合手動錄影目視。

已知限制（工具鏈層面）：實驗為未簽名的 SwiftPM 可執行檔、以 `setActivationPolicy(.accessory)` 模擬正式 App 的 `LSUIElement`，行為可能與正式 `.app` bundle 有差異，由 `app-shell` 端到端驗收補驗。S4 方案 B 的幀間隔觀察者（`--frame-observer on`）量的是顯示器 display link 回呼，不等同 Core Animation 實際合成頻率，解讀 B 的 30fps 結果時須搭配 CPU 變化與目視。
