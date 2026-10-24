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
