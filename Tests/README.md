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
