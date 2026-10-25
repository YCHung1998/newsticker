# Tests —— show-engine-core 的驗證與重現方式

工具鏈：macOS 26.5.1、Swift 6.3.3、Xcode 26.6（arm64）。測試框架 swift-testing（`import Testing`），`swift test` 不需任何額外參數、不需 sudo、不需系統權限。

## 重現

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift build
swift test                                   # 101 tests in 12 suites
swift test --filter LineBufferTests          # 單一 suite（名稱見下表）
TZ=Asia/Tokyo swift test                     # 換系統時區，結果應相同
python3 -m unittest discover -s protocol/tests   # Python 參考驗證器（11 tests）
openspec validate show-engine-core --strict
```

| task | suite（`--filter`） | 檔案（`Tests/FastBullTickerCoreTests/`） |
|---|---|---|
| 1.1 | PackageSkeletonTests | PackageSkeletonTests.swift |
| 1.2 | ProtocolDecodingTests / ContractFixturesTests | ProtocolDecodingTests.swift / ContractFixturesTests.swift |
| 2.1 | LineBufferTests | LineBufferTests.swift |
| 2.2 | TickerLayoutTests | TickerLayoutTests.swift |
| 3.1 | TapeModelTests | TapeModelTests.swift |
| 3.2 | HistoryTests | HistoryTests.swift |
| 3.3 | ReplayLiveStateTests | ReplayLiveStateTests.swift |
| 3.4 | LiveQueueLimitTests | LiveQueueLimitTests.swift |
| 3.5 | FreezeResumeTests | FreezeResumeTests.swift |
| 3.6 | RebaseTests | RebaseTests.swift |
| 4.1 | SchedulerInvariantTests | SchedulerInvariantTests.swift（固定種子 SplitMix64） |

共用輔助：`TestSupport.swift`（以 `#filePath` 往上找 `protocol/fixtures/manifest.json`）、`SchedulerSupport.swift`（假時鐘 `FakeClock`、假 measurer 於 `TickerLayoutTests.swift` 的 `flatMeasure`／`fakeMeasure`）。所有測試不碰真實時間、時區、字型或網路。

## fail-then-pass 證據

原始輸出摘要存於 `Tests/evidence/`。做法：先寫「對空實作（stub）」的測試，確認紅；再實作，確認綠；另對排程器做「故意破壞實作」的 mutation 證明測試有咬合力。

| task | 紅（stub 或破壞） | 綠 | 檔案 |
|---|---|---|---|
| 1.1 | `CoreInfo` 尚不存在 → 編譯失敗（`cannot find 'CoreInfo' in scope`）；另暫時加入 `import AppKit` → `coreSourcesDoNotImportUIFrameworks` 失敗 | `4 tests passed` | `1.1-red.log`、`1.1-appkit-injected.log`、`1.1-green.log` |
| 1.2 | `decodeLine` 空實作 → ProtocolDecodingTests 28 issues、ContractFixturesTests 41 issues；另把 `rejectExtraFields` 暫改 false → 契約測試紅（`item-extra-field` 被接受） | 19 tests / 4 tests 綠 | `1.2-red.log`、`1.2-mutation-extra-fields.log`、`1.2-green.log` |
| 2.1 | `LineBuffer` 空實作 → 多項紅（含 crash） | `13 tests passed` | `2.1-red.log`、`2.1-green.log` |
| 2.2 | 版面空實作 → `12 tests failed ... 23 issues` | `12 tests passed` | `2.2-red.log`、`2.2-green.log` |
| 3.1–3.6 | 排程器空實作（stub）→ 各 suite 紅；其中 TapeModel／ReplayLiveState／Rebase 因 stub 回傳空陣列而在 `[0]` 索引處 crash（process 崩潰也是紅） | 各 suite 綠（9/10/11/4/7/5 tests） | `3.x-*-red.log`、`3.x-*-green.log` |
| 3.x／4.1 | mutation：M1 隱藏仍推進 tape 時間、M2 rebase 不調整 `baseOffset`、M3 佇列溢出丟最新、M4 補料少了 gap、M5 LIVE 播完後重播游標不歸零 → 對應測試皆紅 | 還原後 101 tests 綠 | `mutations.log` |
| 4.1 | 以 M1／M2 證明不變量測試會咬（`mutations.log` 中 `differentSeedsAlsoHold`、`invariantsHoldOverLongRandomRun` 失敗）；同種子輸出一致由 `sameSeedIsDeterministic` 斷言 | `3 tests passed` | `mutations.log` |

誠實註記：
- 3.1–3.6 的「紅」是對同一份 stub 一次跑出，而非每個 task 各自一個 stub 版本；4.1 的不變量測試第一次執行即綠（沒有針對它的 stub 紅），其咬合力由 mutation 證明。
- 測試 `FreezeResumeTests.resumesFromFrozenTapeTime` 第一次因我方測試用精確相等比較浮點而失敗（0.1 步長），已改為容忍度比較——是測試寫法問題，非實作問題。
- `PackageSkeletonTests.checkerFailsOnMissingDirectory` 第一次紅是我方 import 檢查器的 bug（目錄不存在時 `FileManager.enumerator` 回傳空而非 nil），已修正。
- 一次 `swift test` 組合指令在 shell 裡逾時被移到背景（輸出遺失），改用輸出到檔案後無此問題；屬環境／呼叫方式因素，不是測試本身卡住（單獨重跑 0.05 秒內完成）。

## 與 Python 參考驗證器的一致性

`ContractFixturesTests.everySampleMatchesManifest` 對 `protocol/fixtures/manifest.json` 的全部樣本（含程式產生的 `generated-at-limit` 1,048,576 位元組、`generated-over-limit` 1,048,577 位元組）斷言：`accept` 者解碼成功、`reject` 者失敗且原因類別（`not_json`／`schema`／`version`／`oversize`／`order`）相同。Python 端 `protocol/tests/test_contract.py` 以同一份 manifest 斷言 `refcheck.check_line`。兩端各自與 manifest 一致，因此彼此一致（傳遞性）；`manifestAndDirectoryAreOneToOne` 另檢查 manifest 與目錄一一對應，`missingFixtureFileFailsLoudly` 檢查缺檔會失敗而非略過。


---

# app-shell 第 A 段（1.1、2.1、2.2）的驗證與重現（2026-10-24）

全部不連網、不需 sudo／系統權限。FeedClient 測試用「假 helper 腳本」（`/bin/sh` 暫存腳本）加「假時鐘」（`FakeClock`，只在 `advance(by:)` 時前進），不碰正式網站。

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift test                                       # 128 tests：Core 101 + App 27
swift test --filter FeedClientTests              # 2.1 核心（含 BackoffPolicyTests、PipeReaderTests 為同檔的另兩個 suite）
swift test --filter FeedClientResilience         # 2.2 韌性
sh Tests/app-packaging-check.sh                  # 1.1 打包與簽名（含改 helper 一位元組的 fail-then-pass）
python3 Tests/app-mutations.py                   # 2.1／2.2 的 11 組 mutation（約 3 分鐘；每組破壞→紅→還原）
```

| task | 測試檔（`Tests/FastBullTickerAppTests/`） | 內容 |
|---|---|---|
| 1.1 | （腳本）`Tests/app-packaging-check.sh` | bundle 結構、`LSUIElement`、codesign、`grep -- "--deep" Makefile` 無結果、改 helper 位元組後 verify 紅→重簽綠、helper 吃 stdin EOF 立即結束 |
| 2.1 | `FeedClientTests.swift` | 退避純函式、EOF 清 handler、正常輸出、崩潰＋退避序列（假時鐘）、穩定 >60 秒才重置、半行＋壞行、stderr 灌滿 30MB、generation token、路徑覆寫／bundle 查找 |
| 2.2 | `FeedClientResilienceTests.swift` | 卡死閾值、任何輸出（含半行）算活著、喚醒寬限（含 `WakeObserver` 模擬通知）、缺檔／無 +x／無法啟動＝嘗試 1 次、優雅結束（stdin EOF／忽略 EOF→SIGTERM）、pid file 清除孤兒 helper 且不誤殺無關行程 |
| 共用 | `Support.swift` | `FakeClock`、`EventLog`、`Sandbox`（暫存腳本）、`waitUntil` |

## fail-then-pass 證據（誠實說明）

- **做法**：測試與實作是一起寫完、再對實作做「故意破壞→測試變紅→還原→變綠」的 mutation（不是先對空實作看紅）。這與 Core 的 3.x、Rust helper 的做法相同。
- 1.1：`Tests/evidence/1.1-packaging.log`——改 helper 一位元組後 `codesign --verify` 輸出 `invalid signature (code or signature have been modified)`（紅），重新 `make sign` 後通過（綠）。
- 2.1／2.2：`Tests/evidence/app-mutations.log`——11 組 mutation 全部變紅，還原後 `27 tests in 4 suites passed`。

| mutation | 破壞內容 | 變紅的測試 |
|---|---|---|
| M1 | 退避不設上限 | `doublesFromOneAndCapsAtSixty`、`jitterIsWithinPlusMinusTwentyPercent` |
| M2 | 退避永不重置 | `backoffResetsOnlyAfterStableRunOverSixtySeconds`、`resetsOnlyWhenStableLongerThanSixtySeconds` |
| M3 | EOF 不清 handler 也不關 fd | `eofClearsHandlerAndStopsInvocations` |
| M4 | 忽略 generation token | `staleGenerationEventsAreIgnored` |
| M5 | 輸出不重置卡死計時 | `anyOutputResetsTheTimerEvenWithoutStatus`、`partialLineBytesCountAsAlive` |
| M6 | 忽略喚醒寬限 | `wakeGivesAFreshGracePeriod`、`wakeNotificationFromWorkspaceCenterReachesClient` |
| M7 | 不可恢復錯誤也進退避 | `missingExecutableIsFatalWithSingleAttempt`、`nonExecutableIsFatalWithoutBackoffLoop` |
| M8 | 逾時後不送 SIGTERM | `shutdownSendsSigtermAfterTimeoutWhenHelperIgnoresEof` |
| M9 | stderr 不讀走 | `stderrFloodDoesNotBlockHelper` |
| M10 | 不處理 pid file 遺留 helper | `staleOrphanHelperIsKilledBeforeNewOneStarts` |
| M11 | 結束時不關 stdin | `shutdownClosesStdinAndCooperativeHelperIsNotSigtermed` |

過程中的紀錄：
- M3 第一版只拿掉 `readabilityHandler = nil` 而保留 `close()`，測試仍綠——因為 macOS 的 `FileHandle.close()` 本身就會停掉 handler；改為兩者都拿掉後才變紅。結論：EOF 後「清除 handler 或關閉 fd」任一都防得住 busy loop，我們兩者都做。
- `shutdownSendsSigtermAfterTimeoutWhenHelperIgnoresEof` 第一次在完整測試併行時失敗：我方測試用固定 200ms 等腳本設好 `trap`，負載高時 SIGTERM 比 trap 早到。已改為腳本寫 ready 檔、測試等 ready 檔（我方測試的競態，非實作問題）。
- 「卡死：只有 items 沒有 status」「半行」兩個情境，用 `FeedClient.receive(_:generation:)` 直接注入位元組模擬輸出（假時鐘無法讓真腳本在特定假時間點輸出）；其餘情境用真行程。
- 未涵蓋：真機睡眠／喚醒、`kill -9` App 後的真實孤兒（pid file 測試以「父行程已結束的孤兒」模擬）、簽名後 bundle 內 helper 連真站——屬 5.1／5.3 人工驗收。

---

# app-shell 第 B 段（3.1、3.2、3.3、4.1、4.2）：Persistence、PanelShell、StatusMenu、TickerRenderer、AppDelegate

重現（專案根目錄；全部不開視窗、不連網）：

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift test                                              # 164 tests（Core 101 + App 63）；第 A 段結束時為 128
swift test --filter "Persistence"                       # 3.1
swift test --filter "PanelShell"                        # 3.2
swift test --filter "StatusMenu"                        # 3.3
swift test --filter "TickerRenderer|Tiling|TrackModel|TickerDriver|DemoCadence"   # 4.1
swift test --filter "AppSmoke"                          # 4.2（假 helper → FeedClient → Coordinator → Scheduler）
python3 Tests/shell-mutations.py                        # 15 組 mutation（約 3 分鐘；每組破壞→紅→還原）
```

| task | 測試檔（`Tests/FastBullTickerAppTests/`） | 內容 |
|---|---|---|
| 3.1 | `PersistenceTests.swift` | 夾制純函式（完全在外／螢幕缺失退回主螢幕／偏移超出）、往返、存檔介面無點穿欄位、debounce（50 次 didMove 在 100ms 內只寫一次、從最後一次起算 0.5s） |
| 3.2 | `PanelShellTests.swift` | styleMask＝`[borderless, nonactivatingPanel]` 且無 hud、`hidesOnDeactivate`／`canBecomeKey`／`canBecomeMain`／`hasShadow`／`isOpaque`／背景、level／behavior 等於 `ShellConfig.provisional`、無 `NSVisualEffectView`、透明度下限、原始碼靜態掃描無 `activate(`／`makeKeyAndOrderFront`／`.hudWindow` |
| 3.3 | `StatusMenuTests.swift` | 四類項目與標題（隱藏→「顯示帶子」）、滑桿範圍＝`alphaRange`、點穿不寫入存檔且重建後為關、結束回呼、面板右鍵與選單列為同一個 `NSMenu` 實例 |
| 4.1 | `TickerRendererTests.swift` | 切塊寬度總和與上限（含真 CGImage）、`TrackModel` rebase／prune、Driver 呼叫序列、隱藏凍結＋恢復不跳動、遮蔽與隱藏合併、rebase 前後每則螢幕位置差 < 0.5px、長時間 layer 數量有界、示範節奏（8 秒一則）會回到重播 |
| 4.2 | `AppSmokeTests.swift` | 以 `scripts/demo-helper.sh`（包一層縮短間隔）經 `FeedClient`→`AppCoordinator`→`TickerDriver`：snapshot 後 REPLAY，items 後 LIVE，佇列播完回 REPLAY（`modesSeen == [replay, live, replay]`）；示範 helper 對 stdin EOF 退出且無孤兒 |

說明：`PanelShellTests` 會建立 `NSPanel`／`TickerView` 物件並讀回屬性，但**從不 `orderFront`**，螢幕上不會出現視窗；不建立 `NSStatusItem`。

## fail-then-pass 證據（誠實說明）

做法與第 A 段相同：測試與實作一起寫，再對實作做「故意破壞→測試變紅→還原→變綠」的 mutation，**不是先對空實作看紅**。完整輸出：`Tests/evidence/shell-mutations.log`（15 組全部 rc=1，還原後 `62 tests in 13 suites passed`）。

| mutation | 破壞內容 | 變紅的測試 |
|---|---|---|
| S1 | 夾制函式不夾制 | `clampPullsFullyOffscreenFrameBackInside`、`missingScreenFallsBackToPrimaryAndIsVisible`、`offsetOutsideVisibleAreaIsClampedToPartiallyVisibleAtLeast`、`reclampAfterScreenUnplugMovesPanelOntoPrimary` |
| S2 | debounce 不取消前一個計時 | `fiftyMovesWithinOneHundredMillisecondsWriteOnceWithFinalPosition` |
| S3 | 透明度下限改 0 | `shellConfigClampsAlphaToFloor`、`sliderRangeMatchesFloorAndAlphaIsClamped`、`alphaValueDrivesOpacityAndNoVisualEffectView` |
| S4 | styleMask 加 `.hudWindow` | `styleMaskIsBorderlessNonactivatingOnlyAndNotHud`、`sourcesNeverCallApplicationActivation` |
| S5 | `canBecomeKey` 回 true | `fixedAttributes` |
| S6 | level 改 `.screenSaver` | `levelAndBehaviorComeFromShellConfigProvisionalValues` |
| S7 | 隱藏不改選單標題 | `hideTogglesTitleToShowAndFiresCallback` |
| S8 | 點穿狀態不記錄 | `clickThroughIsNeverPersistedAndResetsOnRecreate` |
| S9 | 隱藏時 Scheduler 不凍結 | `hiddenFreezesAndResumesWithoutJump` |
| S10 | rebase 不通知 renderer | `rebaseKeepsEveryScreenPositionUnchanged` |
| S11 | `TrackModel.rebase` 空實作 | `rebasePreservesVisualPositionsAndPrunesScrolledOut`、`rebaseKeepsEveryScreenPositionUnchanged` |
| S12 | 紋理不切塊 | `tileWidthsSumToTotalAndNeverExceedLimit`、`bitmapRendererProducesTilesWhoseWidthsEqualPlan` |
| S13 | 不清除已捲出的 layer | `prunesScrolledOutLayersSoMemoryDoesNotGrow`、`rebasePreservesVisualPositionsAndPrunesScrolledOut` |
| S14 | Coordinator 不把訊息轉給 driver | `snapshotThenItemsDriveSchedulerReplayToLiveToReplay` |
| S15 | 加入 `NSApp.activate(...)` | `sourcesNeverCallApplicationActivation` |

另有：`Tests/evidence/demo-cadence.log`——`scrollSpeed=60` 時 `eightSecondCadenceCyclesReplayLiveReplayRepeatedly` 為紅（240 秒只回到重播 1 次），改 90 後為綠。

過程中的紀錄（我方問題，已修正）：
- S1 第一版 mutation 造成編譯錯誤（不算紅），已改成語法正確的破壞。
- S2 第一版測試沒咬到 mutation（兩者都只寫一次），因為少了「從最後一次移動起算」的斷言；已補 `advance(by: 0.45)` 仍未寫入的檢查後才變紅。
- `Tests/app-packaging-check.sh` 原本最後一步會啟動主執行檔（空殼時會立刻結束）；現在它是會常駐的真 App（且預設會啟動真 helper 連網），所以第一次重跑時卡住。已移除該步（改成檢查 arm64），並手動清掉殘留行程。這是我方腳本沒跟著更新，不是環境因素。

## 真機啟動驗證（2026-10-24，共 3 次受控啟動）

指令（`FASTBULL_TICKER_AUTOQUIT_SECONDS` 與 `FASTBULL_TICKER_LOG` 是本次新增的除錯用環境變數）：

```sh
FASTBULL_TICKER_HELPER="$PWD/scripts/demo-helper.sh" FASTBULL_TICKER_LOG=/tmp/app.log \
FASTBULL_TICKER_AUTOQUIT_SECONDS=14 build/FastBullTicker.app/Contents/MacOS/FastBullTicker
```

- 第 1 次：日誌顯示設定值正確、snapshot 12 則、items 後 `mode -> live`，約 30 秒後又 `mode -> replay`；但**自動結束後 App 沒有結束**（`applicationShouldTerminate` 回 `.terminateLater` 再 `DispatchQueue.main.async` 回覆無效；helper 已收尾）。我方問題，已改為 semaphore 等待後 `.terminateNow`（design.md 決定 17）。手動 `kill` 掉。
- 第 2 次：確認結束流程（`quit: helper shutdown completed` → `terminate`，無殘留行程）。
- 第 3 次（最終 build，scrollSpeed 90）日誌摘錄：
  ```
  panel effective: level=25 behavior=[canJoinAllSpaces,fullScreenAuxiliary,ignoresCycle,stationary] styleMask=[borderless,nonactivatingPanel] hidesOnDeactivate=false canBecomeKey=false canBecomeMain=false isOpaque=false hasShadow=false alpha=0.90 frame={{425, 873}, {620, 42}}
  feed: snapshot items=12 / status ok demo helper started / occlusion: visible=true
  +8s feed: items count=1 → mode -> live
  quit: helper shutdown completed → final stats: snapshots=1 itemBatches=1 statuses=1 badLines=0 placed=3 → terminate
  ```
  `level=25` 是 `.statusBar` 的 rawValue。行程結束後無 FastBullTicker／demo-helper 殘留。
- **未目視驗證**（我看不到畫面）：帶子與紅色標籤是否真的出現在螢幕上、文字內容與顏色、捲動是否平順、拖曳、選單列圖示與選單、右鍵選單、透明度視覺、隱藏／顯示、點穿、全螢幕是否可見、不搶焦點、位置重啟後是否還原、中文字型。日誌中的 `occlusion: visible=true` 只表示系統認為面板可見。
- 15 秒內沒有看到 LIVE→REPLAY 的真機日誌（第 1 次有）；最終 build 的回到重播由 `DemoCadenceTests` 以假時鐘驗證。

## 切換 Space 閃爍修復：遮蔽防抖（2026-10-24，分支 `fix/space-switch-flash`）

**未目視驗證**：以下只證明防抖邏輯正確；是否真的消除閃爍，待使用者目視確認並提供日誌（見 `README.md` 5.3）。

- 實作：`Sources/FastBullTickerApp/OcclusionDebouncer.swift`（純 Foundation，可注入排程器）；延遲 `ShellConfig.provisional.occludedConfirmDelay = 1.0`【假設】。
- 測試：`Tests/FastBullTickerAppTests/OcclusionDebouncerTests.swift`（10 個，假時鐘，不開視窗）。
  重現：`swift test --filter Occlusion`
- fail-then-pass：`python3 Tests/occlusion-mutations.py`，輸出存於 `Tests/evidence/occlusion-mutations.log`。
  O1「沒有防抖（延遲 0）」→ 紅（5 個測試失敗，含 `briefInvisibilityUnderOneSecondNeverFreezes`、`flappingSequenceUnderOneSecondNeverFreezes`）；
  O2 變回可見不取消 → 紅（4 個）；O3 不解凍 → 紅（2 個）；O4 重複通知重設計時 → 紅（1 個）；O5 設定延遲 0 → 紅（1 個）；還原後 10 個全綠。
- 使用者手動隱藏維持立即：`userHiddenFreezesImmediatelyAndIsNotAffectedByDebounce`（driver 層）；既有 `hiddenFreezesAndResumesWithoutJump` 仍綠。

## ticker-navigation-link 第 N1 段：協定 `url`（tasks 1.1、2.1、3.1，2026-10-24，分支 `change/ticker-navigation-link`）

規格：`openspec/changes/ticker-navigation-link/design.md` 決定 1。`v` 維持 1【假設】。測試不連網、不開視窗。

### 重現指令
```sh
python3 -m unittest discover -s protocol/tests -v      # 12 個（原 11 + UrlRules 1；UrlRules 內 17 個 subTest）
cd ticker-connect && cargo test                         # 76 個（原 65 + 11：fastbull_parse 9、emitter_contract 2）
swift test                                              # 188 個（原 174 + ItemURLTests 14）
swift test --filter ItemURLTests --filter ContractFixturesTests
```
測試檔：`protocol/tests/test_contract.py`、`ticker-connect/tests/{fastbull_parse,emitter_contract}.rs`（`tests/common/mod.rs` 的 `prod_origin()` 以拼接避開守衛）、`Tests/FastBullTickerCoreTests/{ItemURLTests,ContractFixturesTests}.swift`。

### fail-then-pass 證據（實跑）
1. **Python（1.1）**：只加 13 個 fixtures、manifest 與測試、schema 仍為 `additionalProperties:false` 且無 `url` 時，`FAILED (failures=8)`：
   `items-with-url`、`snapshot-with-url`、`items-url-mixed`、`items-url-max-length` 四個合法樣本被拒，加上 `UrlRules` 的 4 個合法 case。改 schema 後 `Ran 12 tests ... OK`。
   mutation：刪掉 schema 的 `not` 子句 → `FAIL ... (sample='item-url-trailing-newline')` 與 `UrlRules` 的 `'https://a.example/\n'`，`FAILED (failures=2)`；還原後 `OK`。
2. **Rust（2.1）**：(a) 暫時還原舊 schema（`git show HEAD:protocol/schema/item.schema.json`），`cargo test --test emitter_contract` → `2 failed`
   （`sample items-with-url should be accepted`、roundtrip 測試）；已還原為新 schema。(b) 先寫測試、`Item` 尚無 `url` 時 `cargo test --no-run` 全部測試目標編譯失敗
   （`E0560 struct Item has no field named url`、`E0609 no field url`，`fastbull_parse` 14 個、`emitter_contract` 3 個錯誤）。實作後 `cargo test` 全綠（各目標 `test result: ok`，合計 76）。
3. **Swift（3.1）**：先只有 manifest／fixtures／schema（`Item` 尚未有 `url`）：`swift test --filter ContractFixturesTests` →
   `✘ everySampleMatchesManifest ... failed with 4 issues`（4 個合法 url 樣本被 `StrictKeys` 當額外欄位拒絕）。新增 `ItemURLTests` 後、實作前：編譯失敗
   （`value of type 'Item' has no member 'url'`、`type 'ProtocolRules' has no member 'isValidURL'`）。實作後 `swift test` → `Test run with 188 tests in 29 suites passed`。
   mutation：把 `isValidURL` 的上界 `0x7E` 改成 `0x7F` → `✘ emptyAndWhitespaceAndControlCharacters`（DEL 被放行），`14 tests ... failed with 1 issue`；還原後 14 個全綠。

### 三端一致性
三端皆直接讀 `protocol/fixtures/manifest.json`（現有 58 個樣本，含新增 13 個）：Python `test_all_samples_match_manifest`、Rust `emitter_contract_all_manifest_samples_match_reference_verdict`、Swift `ContractFixturesTests.everySampleMatchesManifest`，全部判定與原因類別一致。

## ticker-navigation-link 第 N2 段：Core 版面與識別、閱讀位置與 seek、App 純函式（tasks 4.1、5.1、6.1，2026-10-24，分支 `change/ticker-navigation-link`）

規格：`openspec/changes/ticker-navigation-link/design.md` 決定 3–9、11。測試不開視窗、不開瀏覽器、不連網。標【假設】者（8 秒保持、24pt 內縮、保留 64 則、控制列 100pt、hitSlop 4pt）尚未經使用者確認。

### 重現指令
```sh
swift test                                                   # 269 個（原 188 + 新增 81），40 個 suite
swift test --filter ListIdentityTests --filter LinkSlotLayoutTests --filter ReadingPositionTests --filter SeekHoldTests
swift test --filter SchedulerInvariantTests --filter RebaseTests --filter FreezeResumeTests
swift test --filter HitTesting --filter ControlStripLayout --filter PositionIndicator --filter PointerHover --filter LinkPolicy --filter LinkOpening --filter LinkOpenerGuard
python3 Tests/n2-mutations.py                                # 25 個 mutation，約 6 分鐘；完整輸出存於 Tests/evidence/n2-mutations.log
```
測試檔：`Tests/FastBullTickerCoreTests/{ListIdentityTests,ReadingPositionTests,SeekHoldTests,TickerLayoutTests(LinkSlotLayoutTests),RebaseTests,SchedulerInvariantTests}.swift`、
`Tests/FastBullTickerAppTests/{HitTestingTests,PositionIndicatorTests,PointerHoverTests,LinkPolicyTests,LinkOpenerGuardTests,LinkTestSupport}.swift`。

### fail-then-pass
- **紅**（先寫測試、實作尚未存在）：Core 測試編譯失敗，`Tests/evidence/N2-core-red.log`（例如 `extra argument 'linkSlotWidth' in call`、`PlacedItem has no member 'listID'`、`TickerScheduler has no member 'seek'`）；
  App 測試編譯失敗，`Tests/evidence/N2-app-red.log`（`cannot find 'HitItem'`、`ControlStripLayout`、`HitTarget` 等，98 行）。
- **綠**：實作後 `swift test` → `Test run with 269 tests in 40 suites passed`；`swift build` 0 warning。
- 實作後唯一一個既有測試需要改動：`RebaseTests.visualPositionsUnchangedAndMagnitudesShrink` 的 `abs(tapeX) < 5000` 界線。
  原因：預設 `retainPlacedCount = 64` 使 rebase 後保留最近 64 則（座標為負、每則約 150），界線放寬為 `5000 + 64 × 150`（其餘斷言不變）。這是規格要求（rebase 須保留以供 `<` 回溯）造成的必要變更，不是為了讓測試通過而放寬。
- **mutation**（`python3 Tests/n2-mutations.py`，逐一破壞 → 跑全部測試 → 還原）：25 個破壞全部變紅，還原後 269 個全綠。摘要：
  S1 seek 改動某個 tapeX → 紅（不變量 1、`seekNeverChangesAnyTapeXOrWidth` 類測試與 `SchedulerInvariantTests`）；S2 對齊偏 1pt → 紅；S3 指標停留不凍結 → 紅；
  S4 凍結期間仍消耗保持 → 紅（`pointerInsideFreezesAndDoesNotConsumeHold`、`SchedulerInvariantTests`）；S5 保持累加而非重設 → 紅；S6 強制排入少 gap → 紅；
  S7 rebase 不保留最近 N 則 → 紅；S8 內縮線 `>=` → 紅（`rightEdgeEqualToInsetMeansNextOne`）；S9 即時批次總數不含佇列 → 紅；S10 清單第一則 `<` 不停住 → 紅；
  S11 隱藏中 seek 仍動作 → 紅；S12 `setPointerInside` 不先推進時鐘 → 紅；S13 seq 重複 → 紅；L1 連結欄位未扣截斷預算 → 紅；L2 無 url 也保留欄位 → 紅；
  P1 `LinkPolicy` 放行 `javascript:` → 紅；P2 放行 userinfo → 紅；P3 不限長度 → 紅；P4 按鈕不再優先 → 紅；P5 忽略 hitSlop → 紅；P6 標籤內迴紋針有效 → 紅；
  P7 `(n/N)` 格式 → 紅；P8 隱藏面板仍算在內 → 紅；P9 失敗時重試 → 紅；P10 守衛放寬 → 紅。
  S13 在第一輪時以 helper 崩潰（`Duplicate values for key`）呈現，同樣是紅；已把輔助函式改為不崩潰後重跑，變成 16 個測試的斷言失敗（見 log 末尾補記）。

### 守衛
`LinkOpenerGuardTests` 掃描 `Tests/` 不得出現真實開啟連結的呼叫（`NSWorkspace` 加 `.shared.open`；守衛自己以拼接組字串避免掃到自己），`Sources/` 只有 `Workspace*Opener.swift` 可以出現（目前尚無，`WorkspaceURLOpener.swift` 屬 N3），
並掃描 `Sources/` 不得有 `NSApp.activate`／`activate(ignoringOtherApps`。守衛會失敗這件事以「暫存目錄植入違規」證明（`plantedViolationInTestsFails` 等），不修改真實檔案。

### 不變量對應（design.md 決定 4）
`SchedulerInvariantTests`（固定種子 20261024，30,000 步；另 5 個種子各 8,000 步）以 A（會 rebase）／B（對照，不 rebase）兩個排程器吃同一串 tick／items／hide／show／seek（連按 1–4 次）／指標進出／rebase，逐步斷言：
1 既有訊息 tapeX／width 不因 seek 改變（A、B 皆驗）；2 相鄰間距恆為 gap（含強制排入）；3 兩次 seek／rebase 之間 `scrollOffset` 為 tape 時間純函數；
4 隱藏與指標停留不推進時間、不消耗保持，隱藏 ≥1 小時恢復不跳動；5 rebase 前後視覺位置相同、保留最近 `retainPlacedCount` 則、清單總數仍可查；
6 每則即時訊息只播一次（含 `>` 強制排入）；7 `readingPosition` 為純函數且 A、B 一致；8 seek 成功後 `readingItem == target`、目標貼齊視覺左緣 0、保持重設。
涵蓋計數也被斷言（seek >1000、成功 >300、強制排入 >50、指標進入 >100、凍結 tick >1000、保持中 tick >100），避免空轉通過。
該場景把 `seekHoldSeconds` 設為 2（預設 8 會讓隨機 seek 幾乎總在保持中、帶子長期靜止）；預設值本身由 `SeekHoldTests` 驗證。

---

## ticker-navigation-link 第 N3 段：渲染與視圖、組裝與煙霧測試、整體驗證（tasks 7.1、8.1、10.1，2026-10-25，分支 `change/ticker-navigation-link`）

規格：`openspec/changes/ticker-navigation-link/design.md` 決定 7–11。**自動測試不開真實視窗、不開瀏覽器、不連正式網站**（`LinkOpenerGuardTests` 掃描保證 `Tests/` 沒有真實開啟連結的呼叫，`Sources/` 只有 `WorkspaceURLOpener.swift` 有）。標【假設】者（粗體字型 Semibold、迴紋針自繪外觀、控制列配色、26pt 連結欄位、4pt hitSlop）尚未經使用者確認；**所有視覺行為未目視驗證**。

### 重現指令（專案根目錄）
```sh
swift test                                                       # 309 個（N2 為 269，N3 新增 40 個），48 個 suite
swift test --filter TickerRenderer                               # 7.1：粗體時間、迴紋針像素、add 冪等、向後 seek 重建、控制列版面
swift test --filter NavigationView                               # 7.1：滑鼠事件分派（mouse-up 觸發、右鍵、拖曳注入點、追蹤區）
swift test --filter NavigationLinkOpener                         # 7.1：opener 只收 OpenableURL
swift test --filter AppSmoke                                     # 8.1：headless 煙霧（含 AppSmokeNavigationTests）
swift test --filter LinkOpenerGuard                              # 守衛：Tests/ 不得真開連結；Sources/ 只有 Workspace*Opener.swift；不得啟用本 App
python3 Tests/demo-helper-protocol-check.py                      # 示範 helper 輸出通過協定驗證（含 url），約 7 秒
python3 Tests/n3-mutations.py                                    # 22 組 mutation（約 4 分鐘）；輸出存於 Tests/evidence/n3-mutations.log
N3_SNAPSHOT_DIR=/某目錄 swift test --filter PanelSnapshot        # 離屏渲染 PNG（範例：Tests/evidence/n3-panel-offscreen.png）
```
測試檔：`Tests/FastBullTickerAppTests/{TickerRendererTests,NavigationViewTests,NavigationLinkOpenerTests,AppSmokeTests,PanelSnapshotTests}.swift`；實作：`Sources/FastBullTickerApp/{ItemBitmap,TickerView,TickerDriver,ShellConfig,PositionIndicator,NavigationInput,NavigationActions,WorkspaceURLOpener,AppCoordinator,AppDelegate}.swift`、`scripts/demo-helper.sh`。

### fail-then-pass
- **紅**：先寫完測試、實作尚未存在時 `swift build --build-tests` 編譯失敗，233 個 error（`cannot find 'ControlStripState'`、`'ItemText'`、`value of type 'ShellConfig' has no member 'strip'`、`'TickerDriver' has no member 'reconcilePointer'`、`extra argument 'seq'`…），完整輸出 `Tests/evidence/N3-red.log`。
- **綠**：實作後 `swift test` → `Test run with 309 tests in 48 suites passed`；`swift build` 0 warning。
- 實作後我方測試自己的兩個錯誤（不是實作問題）：`linkOnlyWithinVisibleBandNotUnderControlStrip` 的幾何算錯（visualLeft 應為 130／250，已修）、`driverPushesControlStateOnlyWhenItChanges` 誤期待初始就送一次狀態（初始與視圖預設相同不送，已改）。
- 唯一動到的既有測試：`TickerRendererTests` 的 `RecordingRenderer`／`TrackModelTests` 改用 `TrackModel.add(seq:tapeX:width:)`（`TrackModel` 依 design 決定 7 改以 Core 的 `seq` 為鍵），斷言內容不變。

### mutation（`python3 Tests/n3-mutations.py`，逐一破壞→跑全部測試→還原）
22 組全部變紅，還原後 309 個全綠。**第一輪有 1 組存活（A1：迴紋針開啟了別則的連結）**——因為測試只比對 host 與 path 前綴，且點的剛好是第一則；已把測試改為點非第一則並比對完整網址（`https://example.com/demo/<被點擊那一則的 id>`），補跑 A1 後變紅（附在 log 末尾）。摘要：

| 破壞 | 變紅的測試 |
|---|---|
| N1 按鈕改在 mouse-down 觸發 | `buttonsFireOnMouseUpNotMouseDown`、`releasingOutsideThePressedTargetDoesNotFire`、`arrowButtonsChangePositionAndHoldTimer` |
| N2 mouse-up 不核對目標 | `releasingOutsideThePressedTargetDoesNotFire` |
| N3 右鍵當左鍵 | `rightAndOtherButtonsNeverTrigger` |
| N4 `.drag` 不呼叫 performDrag／N5 按鈕與迴紋針也拖曳 | `onlyDragTargetCallsPerformDrag`（及 `linkFiresOnMouseUpWithItsSeq` 等） |
| N6 點穿仍處理事件 | `disabledRouterIgnoresEverything` |
| R1 `TrackModel.add` 不冪等 | `trackModelAddIsIdempotentPerSeq`、`viewAddTwiceKeepsOneLayer`、`backwardSeekRebuildsPrunedLayersWithoutDuplicates` |
| R2 向後 seek 不重建圖層 | `backwardSeekRebuildsPrunedLayersWithoutDuplicates`、`seekNextForcePlacesAndAddsNewLayer` |
| R3 seek 後不同步位移／R4 控制列狀態每次推送／R5 `TickerView.add` 不冪等 | `backwardSeek…`／`driverPushesControlStateOnlyWhenItChanges`／`viewAddTwiceKeepsOneLayer`（以 scrollLayer 實際子圖層數抓出孤兒圖層） |
| B1 時間不粗體／B2 迴紋針不繪製 | `boldPrefixIsExactly…`、`timeRunIsBoldAndRestIsRegular`／`paperclipIsDrawnInLinkSlotOnlyWhenItemHasLink` |
| V1 可視寬度寫死 470／V2 裁切區蓋到控制列／V3 `<` 永遠啟用 | `tapeViewportIsDerivedFromControlStripNotHardCoded`、`viewLayoutMatchesControlStripLayoutAndHitTesting`／`stateFromReadingPosition` |
| H1 核對不採用 mouseLocation／H2 進出事件不轉給 Core | `lostExitEventIsRecoveredByMouseLocationReconcile`／`pointerInsideFreezesScrollingAndLeavingResumes` |
| A1 開了別則連結（補強後）／A2 迴紋針沒接上／A3 `>` 沒接上 | `clickingPaperclipOpensExactly…`／同左、`failedOpenIsNotRetried`、`policyBlockedURLNeverReachesTheOpener`／`arrowButtonsChangePositionAndHoldTimer` |
| O1 opener 啟用本 App | `realTreeIsClean`、`sourcesNeverCallApplicationActivation` |

### 8.1 煙霧測試涵蓋（`AppSmokeNavigationTests`，不開視窗、假 opener）
點迴紋針→假 opener 恰收到一次 https 網址且等於被點擊那一則；無 `url` 的訊息不產生迴紋針、點遍整條帶子 opener 為零；`javascript:` 被 `LinkPolicy` 擋下；opener 失敗不重試；點 `<`／`>` 使 `(n/N)` 與保持計時（8 秒、第 5 秒仍不動、第 9 秒恢復、再點重設）符合預期；清單第一則按 `<` 無動作；指標進入凍結、離開恢復；exit 事件遺失由 `mouseLocation` 核對補救（面板點穿或隱藏時不暫停）；`router.isEnabled = false`（點穿）時無動作；示範 helper 經 `FeedClient` 嚴格解碼 `badLines == 0` 且 `url` 有帶與沒帶者都存在。`grep -rn "activate(" Sources/` 無對 `NSApp`／`NSApplication` 的呼叫（只有註解與 `NSWorkspace.OpenConfiguration.activates` 屬性，那是讓瀏覽器成為前景）。

### 10.1 整體驗證（2026-10-25 實跑）
`swift build` 0 warning；`make helper app sign test` 成功（309 個）；`codesign --verify --strict build/FastBullTicker.app` 通過；`sh Tests/app-packaging-check.sh` ALL PASS；`cargo test` 76 通過；`python3 -m unittest discover -s protocol/tests` 12 個 OK；`cd spikes && swift build && tests/run_script_tests.sh` passed=41；`openspec validate --all --strict` 13 項全過。

### 真機啟動驗證（一次，約 13 秒；示範 helper、`FASTBULL_TICKER_AUTOQUIT_SECONDS=12`）
日誌（節錄；視覺一律**未目視驗證**）：
```
layout: tapeViewport=370 controlStrip=100 linkSlot=26 hitSlop=4 panel=620x42
panel effective: level=25 behavior=[canJoinAllSpaces,fullScreenAuxiliary,ignoresCycle,stationary] styleMask=[borderless,nonactivatingPanel] hidesOnDeactivate=false canBecomeKey=false canBecomeMain=false isOpaque=false hasShadow=false alpha=0.90 …
feed: snapshot items=12 withUrl=8
reading: (1/10)   …   reading: (2/10)
feed: items count=1 withUrl=1      mode -> live
final stats: … withUrl=25/37 badLines=0 placed=3 …     quit: helper shutdown completed     terminate
```
注意（環境因素，不是本段程式缺陷）：這台機器在我啟動前已有一個舊的 `FastBullTicker`（pid 39445，22:38 啟動，使用者或協調者開的）與其 helper 在執行，兩個實例共用同一個 pid file（`~/Library/Application Support/FastBullTicker/helper.pid`）。我的實例啟動時依既有「回收殘留 helper」邏輯**終止了該舊實例的 helper**（日誌 `reclaimed stale helper pid=39512`），雙方因此互相回收、日誌中 helper 反覆 `exited`／重啟（`snapshots=3`）。舊實例（39445）及其新 helper 在我結束後仍在執行，我沒有動它。**我自己啟動的行程已全部結束**。


---

# ticker-style-settings 第 S1 段（1.1、2.1、3.1）的驗證與重現（2026-10-25）

全部不開真實視窗、不連網、不開瀏覽器、不碰真實 `~/Library/Application Support/FastBullTicker/style.json`（StyleStore 測試一律用 `FileManager.default.temporaryDirectory` 下的暫存目錄，`StyleEnv` 以 `precondition` 強制）。熱重載用假監看器（`FakeStyleWatcher`）＋假時鐘（`FakeClock`）；另有 3 個用真實 `DispatchSource` 的測試，但同樣只在暫存目錄。

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift test                                              # 410 tests in 55 suites（基準 309 + 101）
swift test --filter TickerStyleTests                    # 1.1  15 個
swift test --filter StyleParserTests                    # 1.1  25 個
swift test --filter ReconfigureTests                    # 2.1  19 個
swift test --filter TickerLayoutTests                   # 2.1  含新增 4 個 showTime
swift test --filter SchedulerInvariantTests             # 2.1  含 2 個 reconfigure 長序列（固定種子，30,000 步／5 個種子各 8,000 步）
swift test --filter StyleStore                          # 3.1  StyleStoreLoadTests／HotReloadTests／WriteBackTests
swift test --filter DispatchSourceWatcherTests          # 3.1  真實 DispatchSource（暫存目錄）
python3 Tests/s1-mutations.py                           # 36 組 mutation（約 40 分鐘；每組破壞→紅→還原）
```

| task | 測試檔 | 內容 |
|---|---|---|
| 1.1 | `Tests/FastBullTickerAppTests/TickerStyleTests.swift` | 15 鍵齊全、往返、正規化輸出（鍵排序／大寫／結尾換行）、僅 import Foundation、預設值逐項、與原型常數（`ShellConfig.provisional`、`TickerView` 內色彩字面值）一致且 ≤ 1/255、範圍、色碼合法／非法、WCAG 參考值（21、4.48、1.07）、三組預設配色 ≥ 4.5 |
| 1.1 | `Tests/FastBullTickerAppTests/StyleParserTests.swift` | 缺鍵／未知鍵、越界夾制（含 `1e30`）、型別錯誤、`replayCount` 整數規則、非法色碼、`labelText`（修剪／截斷／grapheme）、對比度警告但照用、整份失敗（語法／非物件／非 UTF-8／version／64KB）、BOM、固定種子 3,000 組隨機輸入永遠得到合法樣式、2,000 組隨機位元組不崩潰 |
| 2.1 | `Tests/FastBullTickerCoreTests/ReconfigureTests.swift`、`TickerLayoutTests.swift`、`SchedulerInvariantTests.swift` | 改速度視覺連續（含「流逝但未 tick 的時間以舊速度結算」、速度 0 往返）、已排入不變、新設定只影響之後排入且間距仍為 gap、縮小／放大 `replayCount`、放大可視寬度補料、隱藏中呼叫、保持不受速度影響、seek／rebase 與 reconfigure 交錯、六欄位限制、`showTime` 與 `layoutItem` |
| 3.1 | `Tests/FastBullTickerAppTests/StyleStoreTests.swift` | 載入（無檔案不建立／損壞保留／越界夾制／過大／環境變數）、熱重載（debounce、50 次觸發合併、位元組相同不解析、樣式相等不通知、改名取代、刪檔保留、語法錯誤保留再恢復、欄位層級錯誤）、寫回（滑桿連發只寫一次、暫存檔→取代的順序、正規化輸出、`.bak` 三種情況與兩種不備份、自寫入不重套也不重新解析、寫入失敗、重設為預設、`ensureFileExists`） |

## fail-then-pass 證據（誠實說明）
| task | 紅 | 綠 | 檔案 |
|---|---|---|---|
| 1.1 | 先寫完整實作才補測試，故紅是**對 stub**：把 `parse` 改成恆回預設、`hex` 恆回 `#000000`、`ratio` 恆回 1 → TickerStyleTests／StyleParserTests 多項斷言失敗；還原後綠 | 40 tests passed | `Tests/evidence/s1-1.1-red.log`、`s1-1.1-green.log` |
| 2.1 | 測試先於實作：`SchedulerTunables`／`reconfigure` 不存在 → **編譯失敗型**紅 | 實作後 50 tests（5 suites）passed | `s1-2.1-red.log`、`s1-2.1-green.log` |
| 3.1 | 實作先於測試，故紅是**對移除 StyleStore.swift／StyleFileWatching.swift**：`cannot find 'StyleStore' in scope`（編譯失敗型）；還原後綠 | 36 tests passed（重跑 3 次皆綠） | `s1-3.1-red.log`、`s1-3.1-green.log` |

## mutation（`Tests/s1-mutations.py`，輸出 `Tests/evidence/s1-mutations.log`）
36 組破壞全部變紅（存活 0），還原後 `swift test` 410 個全綠。
| 範圍 | mutation → 抓到它的測試（代表） |
|---|---|
| 1.1 | T1 預設 `fontSize` 17→`defaultsAreExactlyThePrototypeValues`；T2 放寬上限→`rangesAreTheSpecifiedOnes`；T3 接受 8 位色碼→`invalidHexForms`；T5 亮度係數對調→`contrastRatioMatchesWCAGReferenceValues`；T6 低對比度不照用→`lowContrastWarnsButKeepsValues`；T9 `version` 2 也接受→`wholeFileFailures`；T12 鍵不排序→`normalizedJSONIsSorted…`；其餘見 log |
| 2.1 | C1 改速度不調整 `baseOffset`→`speedChangeKeepsVisualPositionsAndContinuesAtNewSpeed`、`invariantsHoldWithRuntimeReconfigure` 等；C2 不結算舊速度流逝時間→`timeElapsedBeforeReconfigureIsCountedAtOldSpeed`；C3 重新量測已排入訊息→`placedItemsUnchangedAndNewOnesUseNewTunables`；C8 解除隱藏→`reconfigureWhileHiddenIsLegal…` |
| 3.1 | S1 移除自寫入辨識→`ownWriteIsNotReappliedAndNotEvenReparsed`；S2 載入時改寫→`partialOutOfRangeFields…`；S3 失敗載入覆蓋舊值→`syntaxErrorKeepsOldValueThenRecovers`；S4 無 debounce→`editAppliesAfterDebounceExactlyOnce`；S5 不備份→`backups…`；S6 寫回無 debounce→`sliderBurstAppliesEveryTimeButWritesOnce`；S13 不訂閱事件→`realWatcherFiresOnCreateAndOnRenameReplace` |

誠實註記：
- S1 mutation 一開始設計時預期「S1 移除自寫入辨識」可能被「樣式相等不通知」遮蔽（兩層去重）；因此測試額外斷言 `parseCount` 不增加（內容比對先於解析），mutation 才能被咬到。
- 測試過程中我方測試的 bug（非實作問題）：`#"…"#` 原始字串遇到 `"#FF0000"` 提前結束（改 `##"…"##`）；`URL` 比較因結尾斜線不同（改比 `.path`）；真實 watcher 測試的 `afterReplace` 計數有競態（先睡 0.3 秒再取值）；`gap` 不變量在 `reconfigure` 速度 ≥ 160 時會被「尾端已捲出左緣就改排到右緣」的既有規則打破，故隨機序列速度限制 ≤ 100（單元測試另以 250 測保持）。
- 以上均未改動任何實作行為；309 個既有測試未減少、未放寬（唯一的既有測試檔改動：`TickerRendererTests.swift` 一處 `TickerStyle` 改寫為 `FastBullTickerCore.TickerStyle`，因 App 新增同名型別造成型別查找歧義）。
- 仍為【需人工】：正式 `DispatchSource` 監看器對 TextEdit／vim 儲存方式的相容性（自動測試只證明改名取代式更新在暫存目錄中有事件）。

---

# ticker-style-settings 第 S2 段（4.1、5.1、6.1、7.1、9.1）的驗證與重現（2026-10-25）

全部不開真實視窗（`TickerView` 不放進視窗、不呼叫 `orderFront`）、不連網、不開瀏覽器或編輯器（「開啟樣式設定檔…」只經 `RecordingFileOpener`）、不碰真實 `style.json`（一律 `StyleEnv` 的暫存目錄）。守衛 `LinkOpenerGuardTests`／`StyleMenuGuardTests` 掃描：`Tests/` 不得出現真實的 `open` 呼叫；`Sources/` 只有 `WorkspaceURLOpener.swift` 與 `WorkspaceFileOpener.swift` 兩個檔案出現；樣式相關原始碼（去掉註解後）不含 `NSAlert`、`NSWindow(`、`NSApp.activate`。

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift test                                              # 471 tests in 65 suites（S1 後 410，S2 新增 61、10 個 suite）；見下方「基準線上的 1 個紅」
swift test --filter StyleApply                          # 4.1  StyleApplyViewTests／StyleApplySchedulerTests／StyleApplyBoldTimeTests
swift test --filter DefaultStyleRendersLikePrototypeTests   # 4.1  預設樣式渲染＝原型（取代過渡性斷言）
swift test --filter StyleMenu                           # 5.1  StyleMenuModelTests／StyleMenuControllerTests／StyleMenuGuardTests
swift test --filter StyleAction                         # 5.1  StyleActionRunnerTests（假 opener）
swift test --filter StatusMenu                          # 5.1  項目斷言由四項改為五項
swift test --filter AppSmokeStyle                       # 6.1  headless 煙霧測試（假 helper＋暫存 StyleStore＋假 opener）
S2_SNAPSHOT_DIR=$PWD/Tests/evidence swift test --filter StyleSnapshotTests   # 離屏 PNG（非實機畫面）
python3 Tests/s2-mutations.py                           # 36 組 mutation（約 10 分鐘；只跑樣式相關 suite，最後一輪跑完整 swift test）
```

| task | 測試檔 | 內容 |
|---|---|---|
| 4.1 | `Tests/FastBullTickerAppTests/StyleApplyTests.swift` | **預設渲染＝原型**：字級 16 與粗體時間、量測寬度等於原型公式、速度 90 實際每秒捲 90、標籤文字／空隙底色／標籤紅（≤1/255 且同為 Generic RGB 色彩空間）、live 白底黑字／replay 黑底白字的像素；**時間粗體**：`showTime=false` 時內文以 `12:34:56` 開頭不被誤判為粗體（量測端與繪製端各一）、繪製端用 `timeString` 長度而非偵測；**套用語意**：改顏色位置與寬度不變且 bitmap 就地重繪（即時改色、重播不變）、非顏色變更不重繪、改字級只影響之後排入的訊息（舊訊息位元組不變、新訊息以 20pt 量測、間距仍為 gap）、字級改變後再改色舊訊息仍用舊字級重繪、被清除的訊息在字級改變後重建仍用原字級、圓角夾制 21 與圖層裁切、圓角不改命中幾何、`showLabel` 隱藏時可視寬度 370→520 且 `tapeX` 不變且命中幾何同步、標籤文字／顏色／空隙色、相同樣式不重套；**排程器**：速度改變視覺連續、`replayCount`／`showTime` 傳到 Core、`ShellConfig.schedulerConfig(style:)`、套用不重建任何已排入訊息 |
| 5.1 | `Tests/FastBullTickerAppTests/StyleMenuTests.swift` | 純資料 `StyleMenuModel`：項目清單與順序（含「設定檔有誤」提示行為第一項且停用）、字級 13／16／20／24 與 17 時皆不打勾、訊息量 5／10／20、速度 20–300 與圓角 0–21 的滑桿範圍＝`StyleRanges`、即時配色三組可讀且需兩個色碼都相同才打勾、動作只改自己的欄位（預設配色不動重播色）、任何動作結果夾制後合法；`NSMenu` 組裝（打勾狀態、展開前重建、動作與滑桿呼叫 `onAction`、滑桿旁整數值、不建立視窗）；`StatusMenu` 五項；`StyleActionRunner`：選單動作→`StyleStore`→去抖寫回、檔案不存在先建立再呼叫 opener 恰一次、存在不改寫、opener 失敗只記日誌、重設備份、熱重載後選單同步；守衛 |
| 6.1 | `Tests/FastBullTickerAppTests/AppSmokeTests.swift`（`AppSmokeStyleTests`） | 啟動載入並經同一路徑套用（檔案不被改寫）、無檔案＝預設且不套用、改檔→生效樣式改變且畫面端只收到一次套用（含 `changed=[…]` 日誌）、同內容事件不重套、損壞檔案→樣式不變＋日誌 `style: error`＋選單出現提示行＋恢復、選單改字級→立即套用＋去抖後寫回＋自寫入不重套、滑桿連續拖動只寫一次檔、開啟設定檔只用假 opener、重設→預設＋`.bak`、假 helper 餵 snapshot 後連續變更樣式不使圖層位置跳動 |
| 4.1 | `Tests/FastBullTickerAppTests/StyleSnapshotTests.swift` | 離屏渲染＋像素斷言（圓角外露出底色、黃底面積、標籤隱藏後沒有標籤紅）；`S2_SNAPSHOT_DIR` 設定時輸出 PNG |
| 7.1 | `Tests/FastBullTickerAppTests/TickerStyleTests.swift`（`readmeFieldTableListsExactlyTheStyleKeys`） | 讀 `README.md` 第 5.5 節欄位表的鍵名，與 `TickerStyle.keys` 比對（缺漏或多出都紅；已手動把表中 `replayText` 改成 `replayTextX` 驗證會紅、還原後綠）；`README` 含 `style.json` |

## fail-then-pass 證據（誠實說明）
**4.1／5.1／6.1 是先寫完實作再補測試**（新型別的測試在實作之前無法編譯），所以沒有「對舊程式先紅」的紀錄；紅的證據是下方的 mutation：36 組逐一破壞實作、對應測試確實變紅，還原後回到基準線。這與 S1 的 1.1、3.1 相同的誠實程度。另外，過渡性測試的改寫見「過渡性測試如何改寫」。

## mutation（`Tests/s2-mutations.py`，輸出 `Tests/evidence/s2-mutations.log`）
36 組破壞全部變紅（存活 0），還原後完整 `swift test` 只剩「基準線上的 1 個紅」（見下）。
| 範圍 | mutation → 抓到它的測試（代表） |
|---|---|
| 時間粗體 | B1 `showTime=false` 仍偵測→`showTimeFalseBodyThatLooksLikeATimeIsNeverBold`；B2 繪製端回到偵測字串內容→同；B3 `showTime=false` 多一個前導空白→同（`parts.text == body`） |
| 渲染 | B4 配色寫死→`colorChangeKeepsPositionsAndRedrawsBitmapsInPlace`；B5 色碼改用 sRGB 建構→`viewLayersMatchPrototypeConstants`（色彩空間與預設的紅）、`defaultStyle` 快照像素 |
| 視圖 | V1 顏色變更不重繪→`colorChangeKeepsPositionsAndRedrawsBitmapsInPlace`；V2 重繪一律用目前字級→`colorChangeAfterFontChangeStillUsesTheOldFontForOldItems`；V3 不記錄舊字級世代→`prunedItemReaddedAfterFontChangeIsRebuiltWithItsOriginalFont`；V4 圓角不夾制、V5 不裁切→`cornerRadiusIsClampedToHalfPanelHeightAndMasksAllLayers`；V6 命中幾何不更新、V7 裁切範圍不隨 `showLabel`、V10 不隱藏標籤→`hidingTheLabelWidensViewportAndKeepsTapePositions`；V8 空隙色、V9 標籤文字不套用→`labelTextAndColorsApplyImmediately`；V11 改色時位置跳動→`colorChangeKeepsPositionsAndRedrawsBitmapsInPlace` |
| 套用端 | A1 不呼叫 `reconfigure`、A4 `replayCount` 沒傳、A5 舊 measurer、A6 速度沒傳→`speedChangeKeepsVisualPositionsThenAdvancesAtNewSpeed`、`replayCountAndShowTimeReachTheScheduler`、`fontSizeOnlyAffectsItemsPlacedAfterTheChange`；A2 可視寬度不隨 `showLabel`→`hidingTheLabelWidens…`；A3 相同樣式也重套→`applyingTheSameStyleTwiceIsANoOp`；**D1** `ShellConfig.schedulerConfig` 忽略 `style.scrollSpeed`：**第一輪存活**（套用端另外呼叫 `reconfigure`，遮蔽了它），補 `shellConfigBuildsTheSchedulerConfigFromTheStyle` 後補跑變紅 |
| 選單 | M1 檔位 20→21、M2 不打勾、M6 訊息量 40（超出範圍）、M4 速度範圍放寬、M5 提示行可點→`StyleMenuModelTests`；M3 預設配色連重播色一起改→`actionsChangeOnlyTheirOwnFieldsAndStayValidAfterClamp`；M7 不先建立檔案、M8 opener 呼叫兩次→`openFileWhenMissingCreatesItFirstThenOpensExactlyOnce`；M9 重設不備份→`resetBacksUpThenWritesDefault`；M10 展開前不重建→`menuNeedsUpdateRefreshesFromTheLatestStyle`；M11 少了「樣式」項目→**測試行程崩潰**（`StatusMenuTests` 強制解包 nil，exit signal；仍判為偵測到，但不是漂亮的斷言失敗）；M12 熱重載／選單沒接到套用端→`AppSmokeStyleTests` 多項；M13 滑桿不寫回→`actionItemsAndSlidersCallOnAction` |

## 基準線上的 1 個紅（不是本 change 的程式問題；需要你決定）
工作樹的 `Sources/FastBullTickerApp/ShellConfig.swift` 有**不屬於我的未提交修改**（我開工時只有 `level: .screenSaver → .statusBar` 一行；工作過程中又出現 `itemPadding: 14 → 10`，我沒有動過它們，重新套用我的 ShellConfig 修改時保留了它們）。`itemPadding` 的原型值是 14，`TickerStyleTests.defaultsAgreeWithShellConfigPrototypeConstants` 會斷言它，因此該測試紅：`Expectation failed: (p.labelWidth == 150 && p.itemPadding == 14 → false)`。這正是這條斷言存在的目的（原型常數被改了）。要不要保留留白 10（若是你調的，則需同步改測試與 spec `ticker-style` 的「單則左右留白 14pt」）或還原成 14，請你決定。其餘 468 個全綠（含 S2 新增的 61 個）。

## 過渡性測試如何改寫（S1 → S2）
- `TickerStyleTests.defaultsAgreeWithShellConfigPrototypeConstants`：原本有一行 `Double(p.fontSize) == d.fontSize && p.scrollSpeed == d.scrollSpeed && p.labelText == d.labelText`（讀 `ShellConfig.provisional`）。`ShellConfig` 不再有這三個欄位，所以該行移除，**語意由 `DefaultStyleRendersLikePrototypeTests` 接手且更強**：字級 16 看的是實際 CTFont 大小與 Semibold 粗體時間；速度 90 看的是 `schedulerConfig(style:.default)` 與實際捲動每秒 90；標籤文字看的是圖層上實際的字串。仍留在 `ShellConfig` 的值（面板尺寸、標籤寬、留白、透明度範圍／預設）維持原斷言不動。
- `TickerStyleTests.prototypeColorLiteralsStillInTickerViewSource`（grep `TickerView.swift` 的 `red: 0.09, green: 0.09, blue: 0.10` 等字面值）：字面值已不在該檔，改為 `DefaultStyleRendersLikePrototypeTests.viewLayersMatchPrototypeConstants`：斷言實際圖層的空隙底色、標籤紅、標籤字色與原型常數（0.09/0.09/0.10、0.85/0.10/0.13）差 ≤ 1/255，**且色彩空間同為 Generic RGB**；另以 `liveIsWhiteOnBlackTextAndReplayIsBlackOnWhiteTextPixels` 驗證 bitmap 像素。沒有為了讓測試過關而刪除任何斷言；被移除的只是「讀來源字面值」這種實作細節的斷言。
- 其他既有測試的改動：`TickerRendererTests.swift` 的 `DemoCadenceTests` 一行（`ItemBitmapRenderer(fontSize: cfg.fontSize …)` → `ItemBitmapRenderer(style: .default, config: cfg)`）；`StatusMenuTests.swift` 四項→五項；`StyleStoreTests.swift` 新增 `InlineFakeClock` 與 `StyleEnv(inline:)`（既有測試不受影響）。309＋101 個既有測試未減少、未放寬。

## 色彩空間的發現（影響預設值的解讀）
原型以 `CGColor(red:green:blue:alpha:)`（Generic RGB）建構標籤紅與空隙底色。實測（`CGColor.converted(to: sRGB)`）：Generic RGB (0.09, 0.09, 0.10) 顯示時等於 sRGB 位元組 (30, 30, 34)，而 S1 的預設色碼 `#17171A` 當作 sRGB 是 (23, 23, 26)；標籤紅 (0.85, 0.10, 0.13) 等於 sRGB (227, 49, 43)，`#D91A21` 當 sRGB 是 (217, 26, 33)——**紅色的綠通道差 23，肉眼可辨**。為了「不改設定時畫面與原型一致」，S2 的 `RGBColor.cgColor` 刻意用同樣的 `CGColor(red:green:blue:alpha:)`（Generic RGB），也就是**色碼以 Generic RGB 解讀**；離屏快照的標籤紅像素斷言為 (227, 49, 43)。代價：`style.json` 中的 `#FFE45C` 與網頁上的 `#FFE45C`（sRGB）在螢幕上略有不同（bitmap 內為 (255, 231, 110)），這個差異是否可接受、以及 S1 spec 中「色碼為不透明 sRGB」的敘述是否要改，**需要你決定**（未改任何 spec）。

## 離屏渲染（`Tests/evidence/s2-*.png`；CALayer.render，**不是實機畫面**）
我用 Read 看過這 6 張圖（1240×84，2x）：
- `s2-default.png`：左側紅色斜切標籤、白字「即時財經快訊」；中間黑底白字「**08:00:00** 快訊內容第 12 則：美股盤前走勢」（時間粗體）；之後是深灰空隙；右端控制列深灰底，`<` 淡化、`(1/10)`、`>`；四個外角都是直角。
- `s2-corner21.png`：同一畫面，面板四個外角（標籤左側兩角、控制列右側兩角）都成半圓，外面露出我刻意鋪的藍灰底色；標籤與控制列沒有被破壞，文字完整。
- `s2-live-yellow.png`：即時訊息為黃底（`#FFE45C`）黑字「**08:00:10** 即時：布蘭特原油突然拉升逾 2%」，標籤紅不變。這張是「先以預設色跑起來，再套用黃色」，所以也是就地重繪的離屏證據。
- `s2-font24.png`：套用 24pt 後再跑 10 秒；新排入的訊息字明顯變大（時間粗體），標籤不變；較早排入的訊息此時已捲出。
- `s2-no-label.png`：沒有標籤，訊息從面板最左緣起顯示（左側可見前一則被截斷的訊息尾端），右端控制列仍在。
- `s2-combo.png`：圓角 12、標籤綠底文字「快訊」、重播訊息為深藍底、新排入的訊息不含時間、20pt。
這些圖證明圖層樹與 bitmap 的結果，**不證明**螢幕上的實際觀感（字體平滑、透明度、視窗合成、捲動時的視覺連續）。

## 真機啟動驗證
**未執行。** 開始前 `pgrep -fl "FastBullTicker|ticker-connect"` 找到已有一個實例在跑（`build/FastBullTicker.app` 的 `FastBullTicker`，pid 8721，00:52 啟動，及其 helper pid 8788；不是我啟動的），依規則不啟動第二個實例（兩個實例共用 helper pid 檔會互相回收 helper）。改以 headless 煙霧測試（`AppSmokeStyleTests`）涵蓋啟動載入、熱重載、損壞檔案、選單變更的路徑；`AppDelegate` 本身（正式監看器 `DispatchSourceStyleWatcher`、`WorkspaceFileOpener`、選單列圖示）**沒有被任何自動測試或真機日誌執行過**。注意：我重新建置了 `build/FastBullTicker.app`（`make helper app sign`），那個已在跑的實例仍是舊二進位檔，需要重新啟動才會是新版。


---

# nav-layout-tweaks（停留 1 秒、控制列移到標籤右側、符號垂直對齊）的驗證與重現（2026-10-25）

不開視窗、不連網、不寫使用者的 `style.json`、未啟動 App。

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift test                                          # 481 個（原 471 + 新增 10），全綠
swift test --filter StripAlignmentTests             # 符號對齊：離屏渲染＋像素墨跡外框量測
swift test --filter "DefaultSeekHoldTests|HitTestingTests|ControlStripLayoutTests|StyleApplyTests"
python3 Tests/t1-mutations.py > Tests/evidence/t1-mutations.log   # 10 組 mutation（約 1 分鐘）
N3_SNAPSHOT_DIR=<目錄> S2_SNAPSHOT_DIR=<目錄> swift test --filter "PanelSnapshotTests|StyleSnapshotTests"   # 重新輸出離屏 PNG
openspec validate nav-layout-tweaks --strict
```

## 對齊量測與 fail-then-pass（`Tests/FastBullTickerAppTests/StripAlignmentTests.swift`）
標準：離屏 `CALayer.render`（@2x，控制列高 84 px、中線 42），取與控制列底色最大通道差 > 64 的像素之最小外接矩形（墨跡外框），垂直中心 = (minRow + maxRow + 1) / 2；`<`、`(n/N)`、`>` 兩兩相差 ≤ 1 px 且各自相對中線 ≤ 1 px。
- **紅（舊實作，CATextLayer）**：`<`、`>` 中心 47.5 px（低於中線 5.5 px）、`(4/10)` 中心 40.5 px（高於中線 1.5 px），`<` 與 `(n/N)` 差 7 px。`Tests/evidence/nav-layout-align-red.log`（9 個 issue）。
- **綠（chevron 路徑 + 墨跡置中位圖）**：`<`、`>` 中心 42.0 px、`(n/N)` 42.5 px（各 4 組文字、`showLabel` 開／關＋圓角 21 皆同）。`Tests/evidence/nav-layout-align-green.log`。

## 停留 1 秒的紅
把 `SchedulerConfig.seekHoldSeconds` 預設改為 1 之後、尚未改測試前，`swift test` 共 34 個 issue（其中 9 個是當時仍紅的對齊測試，其餘 25 個為：`previousAlignsTargetToLeftEdgeAndStartsHold`、`holdFreezesThenResumesWithoutJump`、`arrowButtonsChangePositionAndHoldTimer`、`newConfigDefaultsDoNotChangeExistingBehaviour` 等硬編 8 秒的斷言）；改測試後綠（見 mutation T1 反向驗證：預設改回 8 → 5 個測試紅）。

## mutation（`Tests/t1-mutations.py`，輸出 `Tests/evidence/t1-mutations.log`）
| 破壞 | 偵測到的測試（摘要） |
|---|---|
| T1 停留預設退回 8 | `defaultIsOneSecond`、`holdsForOneSecondThenResumesWithoutJump`、`secondSeekResetsToOneSecondNotAccumulates`、`newConfigDefaultsDoNotChangeExistingBehaviour`、`arrowButtonsChangePositionAndHoldTimer` |
| T2 可視寬度忘了扣控制列左側占用寬 | `tapeViewportWidthFormula`、`gearSlotCanBeInsertedByShiftingTheSingleOffset`、`hidingTheLabelWidens…` 等 9 個 |
| T3 控制列範圍退回貼面板左緣 | `buttonsAreInTheControlStripRightOfTheLabel`、`rangesTileTheStripRightOfTheLabel` 等 9 個 |
| T4 `>` 命中範圍少 4pt | `buttonsAreInTheControlStripRightOfTheLabel`、`rangesTileTheStripRightOfTheLabel` 等 6 個 |
| T5 迴紋針命中區沿用舊座標 | `linkZoneIncludingHitSlop`、`clickingPaperclipOpens…` 等 12 個 |
| T6 `showLabel` 切換不更新命中幾何 | `hidingTheLabelWidensViewportAndKeepsTapePositions` |
| T7 clip 左緣寫死標籤寬（`showLabel=false` 座標） | `hidingTheLabelWidens…`、`startupLoadsTheFileAndAppliesThroughTheSamePath` |
| T8 控制列底不延伸到標籤斜切下方 | `viewLayoutMatchesControlStripLayoutAndHitTesting` |
| T9 chevron 垂直偏離中心 3pt | `threeGlyphsShareOneVerticalCenter`、`alignmentHoldsForOtherTexts`、`alignmentHoldsWithoutLabelAndWithRoundedCorners` |
| T10 位置指示以基線置中（不依墨跡外框） | 同 T9 的三個對齊測試 |

10 組全紅、還原後 481 個全綠、存活 0。誠實註記：T10 第一版（`size.height / 2 - 4`，與正確值只差約 0.3pt）**存活**——差距在 1 px 容差之內，不是測試漏洞；改成差距明顯的版本（基線置於中線）後被抓到。

## 既有斷言的改動（皆為規格改變，沒有刪除斷言）
- 8 秒 → 1 秒：`ListIdentityTests.newConfigDefaultsDoNotChangeExistingBehaviour`（預設 1）、`AppSmokeTests.arrowButtonsChangePositionAndHoldTimer`（保持 1 秒／0.5 秒仍不動／1.5 秒後恢復／重設為 1）。`SeekHoldTests` 與 `ReconfigureTests.holdIsUnaffectedBySpeedChange` 是「機制」測試，改為在 `make` 內明確指定 `seekHoldSeconds = 8`（原斷言一字不動，仍檢查 8 秒下的機制）；預設值為 1 的行為由新增 `DefaultSeekHoldTests`（3 個）覆蓋。
- 控制列在右端 → 標籤右側：`HitTestingTests`（整組座標重寫為 150..<250 的版面，並新增 `showLabel=false`、齒輪槽偏移場景）、`ControlStripLayoutTests`、`NavigationViewTests`（座標 530→160、610→240、430→540、570→200）、`AppSmokeTests`（點擊座標與迴紋針座標基準 `tapeLeft`）、`TickerRendererTests.viewLayoutMatchesControlStripLayoutAndHitTesting`／`tapeViewportIsDerivedFromControlStripNotHardCoded`、`StyleApplyTests`（clip 與 scroll 原點、`showLabel=false` 時控制列貼左、標籤回來後回到標籤右側）。

## single-instance-guard（G1 段）
測試檔：`Tests/FastBullTickerAppTests/SingleInstanceGuardTests.swift`（17 個，全部用假物件：假 provider／terminator／sleeper／alert；不建立真實 `NSAlert`、不呼叫真實 `terminate`、不開視窗）。執行：`swift test --filter SingleInstanceGuardTests`。
- **紅**：先寫測試、實作不存在 → 編譯失敗（`cannot find type 'ReplaceChoice'／'AlertPresenter'`）；實作後初跑 3 個測試紅（測試自身的浮點下限與暫存檔清理寫錯），修正後綠。
- **綠**：`swift test` 全部 **498 個、68 個 suite** 通過（原 481，新增 17）。
- 涵蓋：無其他實例→繼續；取消→結束且未 terminate；關閉→terminate→繼續且不 force；5 秒內不提前繼續；5 秒仍在→force；force 後仍在→第二提示並結束；terminate 只對其他 pid；對方較晚→不詢問；launchDate 相同／缺漏以 pid 判斷；同一世界兩視角最多一邊詢問；`FASTBULL_TICKER_ALLOW_MULTIPLE` 為 `1` 跳過、其他值不跳過；靜態守衛（`NSApp.activate` 只在 `SingleInstanceGuard.swift` 且恰一處、植入他檔會被抓、Tests 不得引用真實實作類別、`AppDelegate` 檢查早於 `PanelShell(`／`startFeed`）。
- **守衛修改**：`OpenerGuard.activationViolations` 改為「`SingleInstanceGuard.swift` 以外任何啟用呼叫、或該檔超過一處」才算違規；`PanelShellTests.sourcesNeverCallApplicationActivation` 對該檔略過 `activate(` 檢查（次數由前者把關）。
- **mutation**：`python3 Tests/g1-mutations.py`（輸出 `Tests/evidence/g1-mutations.log`）。14 組全部 KILLED，還原後 GREEN，存活 0：G1 不排除自己、G2 取消仍繼續、G3 不等就繼續、G4 不 force、G5 競態兩邊都詢問、G6 不以 pid 判斷、G7 環境變數不跳過、G8 force 後仍在卻繼續、G9 對自己 terminate、G10 無第二提示、G11 他檔 `NSApp.activate`、G12 例外檔內兩處、G13 檢查晚於面板、G14 結束後不 return。
- **未自動覆蓋**：真實 `NSAlert` 外觀與預設按鈕、真實 `NSRunningApplication.terminate`、`kill(pid,0)` 存活判定、真實同時啟動競態——見 README「人工驗收」。


---

# settings-gear 第 A 段（tasks 1–6）：齒輪槽、齒輪、設定值、helper 重啟、開機啟動服務（2026-10-25）

全部不開真實視窗、不連網、不啟動 App、不真的註冊登入項目、不寫使用者真實的 `style.json`（測試只用暫存目錄與假服務）。離屏渲染是 `CALayer.render`，**不是實機畫面**。

```sh
cd /Users/eason.hung/Documents/github/newsticker
swift test                                   # 587 個、77 個 suite（A 段開工前 498 個；新增 89 個，既有斷言一個沒刪，見下方「調整的既有斷言」）
swift test --filter GearLayout               # task 1  Tests/FastBullTickerAppTests/GearLayoutTests.swift
swift test --filter GearHit                  # task 2  GearHitTests.swift（命中／優先序／mouse-up／hover）
swift test --filter GearSnapshot             # task 2  GearSnapshotTests.swift（離屏量測；GA_SNAPSHOT_DIR=… 另輸出 PNG）
swift test --filter SettingsValues           # task 3  SettingsValuesTests.swift
swift test --filter ReconfigureTests         # task 4  Tests/FastBullTickerCoreTests/ReconfigureTests.swift（seekHold 區段）
swift test --filter SnapshotResend           # task 5  Tests/FastBullTickerCoreTests/SnapshotResendTests.swift
swift test --filter "HelperArguments|FeedClientReconfigure"   # task 5  FeedClientReconfigureTests.swift
swift test --filter PollIntervalSmoke        # task 5  PollIntervalSmokeTests.swift（真 FeedClient 重啟＋AppCoordinator）
swift test --filter LaunchAtLogin            # task 6  LaunchAtLoginTests.swift
GA_SNAPSHOT_DIR=$PWD/Tests/evidence swift test --filter GearSnapshot   # 輸出 Tests/evidence/ga-gear-*.png
python3 Tests/ga-mutations.py [G|S|K|P|L 前綴…]                       # mutation（完整約 10 分鐘；每組破壞→紅→還原）
```

## fail-then-pass 證據（誠實說明）

- **紅**：task 1、2 先寫測試再實作，對尚未實作的程式 `swift build --build-tests` 以**編譯失敗**為紅（`Tests/evidence/ga-1-2-red.log`，196 行 `error:`，例如 `ShellConfig has no member 'gearSlotWidth'`、`TickerView has no member 'pointerMoved'`）。task 3、4、5、6 同樣是測試先寫、對缺少新 API 的程式編譯失敗（`SchedulerTunables has no member 'seekHoldSeconds'`、`FeedClientConfig has no member 'helperArguments'` 等）——**這幾次的紅只在終端機看過，沒有存成檔案**。編譯失敗的紅證明「測試引用了尚不存在的行為」，不證明斷言的咬合力；咬合力由下方 mutation 證明。
- **綠**：`Tests/evidence/ga-1-2-full-green.log`（526 個）、`ga-3-green.log`（541）、`ga-4-green.log`（550）、`ga-5-green-1.log`（575）、最終 587 個（見下方「最終驗證」）。
- `SnapshotResendTests`（8 個）是**特徵化測試**：它固定的是 Core 本來就有的行為（中途 snapshot 只取代歷史），所以寫出來就是綠；其咬合力由 mutation P7（中途 snapshot 清掉即時佇列）、P8（把模式設回 replay）證明。
- 第一次對 `FeedClientReconfigureTests.sameArgumentsDoNotRestart` 的紅是**我方測試的競態**（假 helper 腳本在平行測試負載下啟動較慢，300ms 後 args 檔還不存在），已改為先等腳本實際跑起來再斷言；不是實作問題。

## 調整的既有斷言（面板寬度 620→648、座標偏移 +28；斷言數量沒有減少）

| 檔案：測試 | 調整 |
|---|---|
| `TickerStyleTests.defaultsAgreeWithShellConfigPrototypeConstants` | `panelSize.width == 620` → `648`，並新增「等於 28 + 150 + 100 + 370」的推導斷言（高度 42、其餘值不變） |
| `TickerStyleTests.encodedKeysMatchSpecTableExactly`、`normalizedJSONIsSortedIndentedUppercaseWithTrailingNewline` | 鍵數 15 → 17（原 15 個鍵逐字不變，新增 `seekHoldSeconds`、`pollIntervalSeconds`） |
| `TickerRendererTests.viewLayoutMatchesControlStripLayoutAndHitTesting` | 控制列偏移 `inset` 納入齒輪槽（28 + 150） |
| `TickerRendererTests.tapeViewportIsDerivedFromControlStripNotHardCoded` | `620 − 150 − 120` → `648 − 28 − 150 − 120`（可視寬 350 不變）；`clipFrame` 的 minX／maxX 平移 28 |
| `StyleApplyTests.viewLayersMatchPrototypeConstants`、`hidingTheLabelWidensViewportAndKeepsTapePositions` | `clipFrame`／`stripFrame`／`previousFrame` 的絕對座標平移 28（620→648、150→178、250→278、0→28、100→128） |
| `StyleSnapshotTests.defaultStyle` | 量測標籤紅的取樣點 `(2, 2)` → `(30, 2)`（最左 28pt 現在是齒輪槽，另新增斷言 `(2,2)` 是槽底色 51,51,51）；寬度 1240 → 1296 |
| `NavigationViewTests`（9 個測試） | 點擊 x：160→188、240→268、540→568、200→228、570→598、185→213（皆 +28）；300、60 不變（仍分別在帶子與標籤上） |
| `AppSmokeNavigationTests` | `tapeLeft` 納入齒輪槽；`<`／`>` 點擊改用 `prevX`／`nextX`（188／268）；連結可見的右界由 600 改為「面板寬 − 20」；「無迴紋針」測試掃描範圍由 250..<620 改為 `tapeLeft`..<面板寬；指標核對用的假面板 frame 寬 620→648 |
| `AppSmokeStyleTests.startupLoadsTheFileAndAppliesThroughTheSamePath` | 標籤隱藏時 `clipFrame` 100/620 → 128/648 |
| `ReconfigureTests.tunablesExposeExactlySixFields` | 改名為 `…SevenFields`，欄位清單增 `seekHoldSeconds`（原六個名稱逐字不變） |
| `SchedulerInvariantTests` 的 reconfigure 場景 | 追加隨機改 `seekHoldSeconds`（0／0.5／1／3）；原有不變量斷言不變 |
| `README.md`（非測試） | 欄位表加兩列，維持既有測試「README 欄位表與 `TickerStyle.keys` 一致」 |

## mutation（`Tests/ga-mutations.py`；輸出 `Tests/evidence/ga-mutations-1-2.log`、`-3-5.log`、`-6.log`）

共 37 組破壞（G1–G13、S1–S6、K1–K4、P1–P9、L1–L5；初跑存活 3 組，已處理，見下），**最終全數變紅**，還原後完整 `swift test` 綠。

| 組 | 破壞內容 | 抓到的測試（節錄） |
|---|---|---|
| G1–G6 | 面板寬寫死 620／標籤不右移／可視寬度漏加槽寬／命中漏加槽寬／控制列圖層漏加槽寬／命中幾何不帶槽寬 | `GearLayoutTests`、`NavigationViewTests`、`StyleApplyTests`、`TickerRendererTests`… |
| G7–G13 | 齒輪不命中／mouse-down 就觸發／離開不復原 hover／hover 恆真／齒輪偏離中心 3pt／mouse-up 不檢查位置／點穿仍觸發 | `GearHitTests`、`GearSnapshotTests`（G11 靠墨跡置中量測） |
| S1–S6 | 範圍下限放寬、平手取小、解析不夾制、`clamped()` 不夾制、預設改 2、動作寫錯欄位 | `SettingsValuesTests`、`TickerStyleTests` |
| K1–K4 | `reconfigure` 不更新／清掉進行中保持、`StyleApplier` 漏傳、`Tunables.init(config:)` 不帶現值 | `ReconfigureTests`、`StyleApplyTests` |
| P1–P9 | 計畫性重啟進退避／相同參數也重啟／不合併／不更新參數／啟動也回呼／預設也帶參數／Core 中途 snapshot 清佇列／改模式／不升級 SIGTERM | `FeedClientReconfigureTests`、`PollIntervalSmokeTests`、`SnapshotResendTests`、`StyleApplyTests` |
| L1–L5 | 需核准時開關為開／吞掉錯誤／狀態對應錯／重複註冊／refresh 不清錯誤 | `LaunchAtLoginTests` |

初跑存活的三組：**G13**（點穿）——因為 mouse-down 在點穿時本來就不記錄 `pressed`，mutation 是等價的；補測「按住期間才開點穿」（`clickThroughTurnedOnBetweenDownAndUpCancelsTheGear`）後變紅。**L1**——`isOn` 在需核准分支被硬寫，破壞無效果；重構 `makeState` 讓開關位置只由 `status == .enabled` 決定後變紅。**L6**（`@unknown default` 改成已啟用）——該分支以現行系統列舉不可達，無法測；已從腳本移除並在此註明。

## 離屏 PNG（非實機畫面；2x，1296×84）

`Tests/evidence/ga-gear-default.png`、`ga-gear-hover.png`、`ga-gear-nolabel.png`、`ga-gear-round21.png`。用 Read 看過的內容：最左是深灰齒輪槽，內有白灰色八齒齒輪（中心孔可見），垂直置中；其右是紅色斜切標籤「即時財經快訊」；再右是控制列 `<  (2/10)  >`；其後是訊息帶子（含迴紋針、粗體時間）。`nolabel`：齒輪仍在最左，控制列 `<  (2/10)  >` 緊接其後，訊息帶子加寬。`round21`：圓角 21 時左緣為半圓，齒輪完整不被裁切。量測（`GearSnapshotTests`）：齒輪墨跡中心與槽中心 (14, 21) 差 ≤ 1 device px、與 `<`／`>` 垂直中心差 ≤ 1 px、圓角 0／21 的墨跡像素數相同。**齒輪大小、齒形、hover 手感只能實機判斷（未驗證）。**

## 已知問題：既有測試 `AppSmokeTests.snapshotThenItemsDriveSchedulerReplayToLiveToReplay` 偶發失敗

加入 A 段測試後全量 `swift test` 約 12 次中失敗 2 次（`Tests/evidence/ga-5-green-2.log` 是其中一次）：該測試在收到 snapshot 後立刻斷言 `driver.mode == .replay`，但示範 helper 約 2 秒後就送 items；同一個 `@MainActor` suite 內另一個測試用阻塞式 `waitUntil`（`demoHelperExitsOnStdinEofWithoutOrphan`）占住主執行緒時，這個測試的輪詢被延後，items 先到就看到 `.live`。這是**既有測試的時間敏感設計**（單獨重跑該 suite 8 次全過），不是 A 段實作的問題；但 A 段新增的測試增加了平行負載，可能提高發生機率。未修改該測試。

---

# settings-gear 第 B 段（tasks 7–11）：設定面板殼、控制項、開關與全域滑鼠監看、組裝、文件（2026-10-25）

接手前一位工程師被中途停止留下的半成品：盤點時 `swift build` 通過、`swift test` 658 個全綠（含新增 71 個 `SettingsPanel*` 測試），保留沿用；我補的是 `FeedClientReconfigureTests` 的競態修正、離屏 PNG、mutation 重跑、8 次連跑與文件。全部不開真實視窗（`SettingsPanel` 只當離屏宿主、從不顯示）、不裝真實全域監看器、不真的註冊登入項目、不寫真實 `style.json`。

```sh
swift test                                              # 658 個、83 個 suite（A 段 587；B 段新增 71）
swift test --filter SettingsPanelShell                  # task 7   SettingsPanelShellTests.swift（styleMask／位置純函式／面板外判斷）
swift test --filter SettingsPanelModel                  # task 8   SettingsPanelModelTests.swift
swift test --filter SettingsPanelControls               # task 8   SettingsPanelControlsTests.swift（直接呼叫控制項 action）
swift test --filter SettingsPanelDismiss                # task 9   SettingsPanelDismissTests.swift（假監看器）
swift test --filter SettingsPanelSmoke                  # task 10  SettingsPanelSmokeTests.swift（假視窗＋暫存 StyleStore＋假 helper 腳本＋真 FeedClient）
GB_SNAPSHOT_DIR=$PWD/Tests/evidence swift test --filter SettingsPanelSnapshot   # 離屏 PNG
python3 Tests/gb-mutations.py                           # 20 組 mutation，輸出 Tests/evidence/gb-mutations.log
```

## 證據（誠實說明）

- **紅**：前一位工程師的先紅後綠沒有留下檔案；我沒有重做逐項先紅，改以 mutation 證明咬合力。**20 組破壞全部變紅**（重跑結果 `Tests/evidence/gb-mutations.log`：G1–G6 位置／間距／夾制／面板外／key／層級，G7–G11 監看器移除／齒輪關了又重開／遮罩加鍵盤／跑馬燈按下不回報／onGear 未接，G12–G14 輪詢檔位／字級檔位／停留步進與選單不一致，G15–G17 控制項重建／拖動回彈／開啟不重讀開機狀態，G18–G20 開機啟動寫進樣式／樣式變更不重新整理／熱重載不更新），還原後原始檔雜湊與破壞前相同，`SettingsPanel` 71 個全綠。
- **本次修正的我方測試競態**：`FeedClientReconfigureTests.staleOutputFromTheOldGenerationIsIgnoredAfterRestart`（8 連跑第一輪曾紅：`log.messages.count 2 == 1`）。原因是新世代 helper 的合法 snapshot 晚於基準值到達，被誤判成舊世代洩漏；改為先等兩個 snapshot 到齊再取基準（沒有放寬斷言）。
- **綠**：`make helper app sign test` 658 個通過；`codesign --verify --strict build/FastBullTicker.app` 通過；`sh Tests/app-packaging-check.sh` ALL PASS；`cargo test` 76；`python3 -m unittest discover -s protocol/tests` 12；`spikes` 建置＋`run_script_tests.sh` 41；`openspec validate --all --strict` 16 通過；`swift build` 0 warning。

## 連跑 8 次 `swift test`（`Tests/evidence/gb-8x-swift-test.log`）：**沒有全綠**

最後一次 8 連跑：6 次 658 全綠、2 次紅，兩次都是 `AppSmokeNavigationTests.coordinatorCountsItemsWithURLFromDemoHelper`（`AppSmokeTests.swift:271` 逾時；其中一次 `itemsReceived` 只有 snapshot 的 12，代表 10 秒內連一個 items 批次都沒到）。前一批 8 連跑也有 2 次紅（同一測試；另一輪 `FeedClientReconfigure` 那條競態，已修）。對照：以 `git archive HEAD`（A 段）在暫存目錄建置，連跑 12 次 587 個全綠、0 次紅；以 `--skip SettingsPanelSmoke` 連跑 14 次，10 次全綠後第 11 次有 4 個行程類測試（假 helper 啟動／EOF／SIGTERM 等待）逾時。結論：這是**行程啟動時序在測試平行負載下的逾時**，B 段新增的測試量增加了負載使其更容易出現，**並非單一 B 測試的邏輯錯誤，也不是 `SettingsPanelSmoke` 專屬**；根因未證實，我沒有放寬任何斷言或逾時。需要協調者決定處理方式（例如串行化行程類 suite 或加大測試負載隔離）。
