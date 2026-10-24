> 實作紀錄（2026-10-24）：全部 `--filter` 名稱與實際一致；測試共 101 個、12 個 suite；fail-then-pass 證據與重現指令見倉庫根目錄 `Tests/README.md` 與 `Tests/evidence/`。
>
> 通則：每個邏輯 task 先寫測試並記錄「失敗」輸出，再實作並記錄「通過」輸出（fail-then-pass）。完成階段回報須附實際指令與測試檔路徑。測試檔位於 `Tests/FastBullTickerCoreTests/`，下列 `--filter` 名稱為建議，apply 時可調整但須同步更新本檔。

## 1. 骨架與協定

- [x] 1.1 建立 SwiftPM 骨架：`Package.swift`（macOS 14、Core 為 Swift 6 模式）、`FastBullTickerCore`、`FastBullTickerCoreTests`（swift-testing）、`FastBullTicker` 空殼，並加入「Core 不得 import AppKit／SwiftUI／QuartzCore／Cocoa／UIKit」的自動化測試。驗證：先寫 import 檢查測試與一個冒煙測試使 `swift test --filter PackageSkeletonTests` 失敗，建立骨架後 `swift build && swift test --filter PackageSkeletonTests` 通過；暫時加入 `import AppKit` 時該測試須失敗，移除後通過。
- [x] 1.2 協定 Codable 型別、單行解碼器（`not_json`／`schema`／`version`／`oversize`，嚴格性集中單一位置）與契約測試（讀取 `protocol/fixtures/manifest.json` 驗證所有樣本，缺檔／多檔必須失敗）。前提：`message-contract` 已 apply。驗證：`swift test --filter ProtocolDecodingTests` 與 `swift test --filter ContractFixturesTests`；含 items 混有非法 item 整則拒絕、`id` 為數字拒絕、版本不支援；暫時移走一個 fixture 時契約測試須失敗；fail-then-pass；message-contract 的決定已於 2026-10-24 定案並集中於 `ProtocolRules`（回報列出採用值）。

## 2. LineBuffer 與版面

- [x] 2.1 `LineBuffer`：切行、半行、UTF-8 邊界、逐位元組、恰為上限／上限加一、超長跨 chunk 且緩衝有上界、空行、EOF 殘留不輸出、A／亂碼／B 整合。驗證：`swift test --filter LineBufferTests`；fail-then-pass。
- [x] 2.2 版面計算：measurer 注入、量測寬度截斷加「…」（CJK 對比、grapheme、連「…」都放不下）、`HH:mm:ss` 時間字串（UTC+8、UTC、補零、不受系統語系影響）。驗證：`swift test --filter TickerLayoutTests`；`1792832201957` 在 UTC+8 為 `16:56:41`；fail-then-pass。

## 3. TickerScheduler

- [x] 3.1 tape 座標與供料器：注入時鐘（含回撥）、`scrollOffset` 純函數、補料位置為尾端加 `gap`、空帶子從右緣開始、tapeX／width 排入後不變。驗證：`swift test --filter TapeModelTests`，含「排入後 tapeX 不變」與「tick 時機不規則間距恆定」；fail-then-pass。
- [x] 3.2 歷史與最新 10 則：snapshot 取代、items 併入、依 `source`＋`id` 去重、中途 snapshot 不清佇列。驗證：`swift test --filter HistoryTests`；fail-then-pass。
- [x] 3.3 REPLAY／LIVE 狀態機：啟動 snapshot 不觸發 LIVE、REPLAY 中新訊息接尾不打斷、LIVE 追加、LIVE 播完回 REPLAY 且從最新開始、多則由舊到新、已排入不改樣式、重播循環。驗證：`swift test --filter ReplayLiveStateTests`；每個情境一個測試；fail-then-pass。
- [x] 3.4 即時佇列上限 30：超過丟最舊、剛好 30 不丟、回報丟棄數量、被丟者仍在最新 10 則並出現在之後的重播。驗證：`swift test --filter LiveQueueLimitTests`；fail-then-pass。
- [x] 3.5 隱藏凍結與恢復：tape 時間凍結、恢復不跳動（隱藏 1 小時）、恢復後接著走、隱藏期間新訊息入佇列且不補料、重複隱藏冪等。驗證：`swift test --filter FreezeResumeTests`；fail-then-pass。
- [x] 3.6 rebase 純函數介面與閾值判斷：rebase 前後每則視覺位置相同、座標絕對值變小、之後補料間距仍為 `gap` 且與未 rebase 的對照排程器一致、凍結狀態下 rebase 不跳動。驗證：`swift test --filter RebaseTests`；fail-then-pass。

## 4. 綜合驗證與收尾

- [x] 4.1 決定性綜合測試：以固定種子產生長時間事件序列（snapshot、items、隱藏／恢復、rebase、tick），斷言不變量（tapeX 不變直到 rebase、相鄰間距恆為 `gap`、無重疊、LIVE 訊息皆為 `live`、每則即時只播一次），並對照「不 rebase」版本的視覺位置。驗證：`swift test --filter SchedulerInvariantTests`；重跑兩次輸出一致。
- [x] 4.2 收尾：`swift build && swift test` 全綠、`openspec validate show-engine-core --strict` 通過、核對 specs 中仍標【假設】的項目在回報中列出（2026-10-24 後已無【待確認】）。驗證：兩個指令的實際輸出貼入回報，並附測試檔路徑清單；未完成或未驗證之處照實說。
