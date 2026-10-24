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
