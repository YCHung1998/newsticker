前置：`message-contract`、`connect-engine-fastbull`、`show-engine-core` 已 archive；app-shell 第 A、B 段已實作（程式在 `Sources/FastBullTickerApp/`）。使用者尚未確認本 change 的 proposal 前 **不得 apply**（見倉庫 `CLAUDE.md`）；apply 前先跑 `openspec validate ticker-navigation-link --strict`。

通則：每個改邏輯的 task 先寫測試並記錄「失敗」輸出，再實作並記錄「通過」輸出（fail-then-pass），回報附實際指令與測試檔路徑。每項標【自動】或【需人工】。**自動測試不得開啟真實視窗、不得真的開瀏覽器、不得連正式網站**。本 change 的 apply 順序為 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10（1 是 2、3 的前提；4、5 是 7 的前提）。總計 10 項（≤ 12）。

## 1. 協定契約

- [x] 1.1 【自動】協定與 fixtures：`protocol/schema/item.schema.json` 新增 `url`（含 `not: {pattern: "[^!-~]"}`）；新增 4 個合法與 9 個非法 fixtures（見 design.md 決定 1）；更新 `manifest.json`（`covers` 標籤）；`protocol/refcheck.py` 與 `protocol/tests/test_contract.py` 納入 `url`（缺任一類 `covers` 則測試失敗）；`protocol/README.md` 補 `url` 規則與三端接入說明。驗證方式（fail-then-pass）：先只加 fixtures 與 manifest，`python3 -m unittest discover -s protocol/tests -v` **失敗**（合法樣本被 `additionalProperties: false` 拒絕），再改 schema 後通過；另故意移除 schema 的 `not` 子句，`item-url-trailing-newline` 必須使測試失敗，還原後通過；既有 11 個測試仍全過。依賴：無。

## 2. Rust 連接器

- [x] 2.1 【自動】`ticker-connect/src/model.rs` 的 `Item` 增加 `url: Option<String>`（`skip_serializing_if = "Option::is_none"`，不輸出 `null`）；`fastbull.rs` 的 `parse_html` 取每個 `div.news-list` 後代第一個 `[data-href]`，以常數 origin `https://www.fastbull.com` 串接，不合法時降級為無 `url` 並寫 stderr；新增測試：快照第一則 `url` 為 `https://www.fastbull.com/tw/fastshort/4334051_1_2`、20 則皆等於 origin 加 `/tw/fastshort/` 加 `id`、缺 `data-href`／壞值（空、`javascript:`、`//evil.example/x`、超長）降級、輸出組成 snapshot 通過 schema、emitter 對 manifest 全部 `accept`／`reject` 樣本判定正確（含新增 13 個）、引擎原樣輸出 `url` 且不含 `url` 的 item 不出現 `url` 鍵。測試原始碼不得含正式主機字面值（用 `tests/common` 輔助函式拼出）。驗證方式：`cd ticker-connect && cargo test`（fail-then-pass：先寫測試與 fixtures 使 `fastbull_parse`、`emitter_contract` 失敗，再實作）；`cargo test no_external_network` 仍通過；`make helper` 成功。依賴：1.1。

## 3. Swift 協定解碼

- [x] 3.1 【自動】`Sources/FastBullTickerCore/ProtocolTypes.swift`：`Item.url`、`ProtocolRules.maxURLBytes`／`isValidURL`（逐位元組檢查，與 schema 完全一致）、`Item.init(from:)` 區分「缺少」與 `null`（`null` 拒絕）；新增單元測試涵蓋 design.md 的每個 `url` 規則（含結尾換行、2048／2049、`null`）。驗證方式：先使 `swift test --filter ContractFixturesTests`（讀取已更新的 manifest）與 `swift test --filter ProtocolDecodingTests` **失敗**（新樣本被誤判），再實作後通過；`swift test --filter PackageSkeletonTests` 仍通過（Core 無 AppKit import）。依賴：1.1。

## 4. Core 版面與識別

- [ ] 4.1 【自動】`Layout.swift`：`layoutItem` 增加 `linkSlotWidth` 參數（預設 0）與 `ItemLayout.hasLinkSlot`，有 `url` 時截斷預算扣除欄位、`width` 加欄位；`TickerScheduler` 排入時填 `PlacedItem` 的 `url`／`seq`／`listID`／`listIndex`／`hasLinkSlot`、維護各 `listID` 的總數（重播一輪、即時批次，含 LIVE 追加使總數增加）；`SchedulerConfig` 增加四個新欄位（預設值使既有測試不變）。驗證方式：`swift test --filter TickerLayoutTests`、`swift test --filter TapeModelTests`、`swift test --filter ReplayLiveStateTests`、`swift test --filter ListIdentityTests`（新增 `Tests/FastBullTickerCoreTests/ListIdentityTests.swift`）；fail-then-pass；`swift test` 既有 101 個測試仍全過。依賴：3.1。

## 5. Core 閱讀位置與 seek

- [ ] 5.1 【自動】`TickerScheduler`：`readingItem`／`readingPosition`、`seek(.previous/.next)`（含強制排入、邊界結果）、捲動保持（hold，由注入時鐘消耗）、`setPointerInside`、隱藏與指標停留各自獨立、rebase 保留最近 `retainPlacedCount` 則。新增 `Tests/FastBullTickerCoreTests/ReadingPositionTests.swift`、`SeekHoldTests.swift`，並擴充 `SchedulerInvariantTests`（固定種子長序列含 seek／指標進出／hide／rebase，斷言 design.md 決定 4 的八條不變量）與 `RebaseTests`（rebase 後仍可回溯）。驗證方式：`swift test --filter ReadingPositionTests`、`--filter SeekHoldTests`、`--filter SchedulerInvariantTests`、`--filter RebaseTests`、`--filter FreezeResumeTests`；fail-then-pass（先對缺實作版本失敗）；對 `seek` 做 mutation 驗證（例如讓 seek 改動某個 `tapeX`、讓 hold 不被指標凍結而消耗，測試必須變紅）；重跑兩次輸出一致。依賴：4.1。

## 6. App 純函式

- [ ] 6.1 【自動】`Sources/FastBullTickerApp/` 新增純邏輯：`HitTesting`（`HitTarget`、優先序按鈕 > 迴紋針 > 拖曳、`hitSlop`、被標籤與控制列遮住者無效）、`ControlStripLayout`（`controlStripWidth`、可視寬度計算）、`PositionIndicator.text(for:)`（`(n/N)` 格式化）、`PointerHover.isInside`、`LinkPolicy`／`OpenableURL`／`URLOpener` 協定與記錄用假 opener、守衛測試（掃描 `Tests/` 不得出現 `NSWorkspace.shared.open`，`Sources/` 只能在 `Workspace*Opener.swift`〔本 change 僅 `WorkspaceURLOpener.swift`〕出現）。驗證方式：`swift test --filter HitTesting`、`--filter PositionIndicator`、`--filter PointerHover`、`--filter LinkPolicy`、`--filter LinkOpenerGuard`；fail-then-pass；`LinkPolicy` 必須拒絕 `javascript:`、`file:`、`ftp:`、含 userinfo、無 host、超長；mutation：讓 `LinkPolicy` 放行 `javascript:` 時測試變紅。依賴：5.1（型別）。

## 7. 渲染與視圖

- [ ] 7.1 【自動＋需人工目視】`ItemBitmap.swift`：共用的屬性字串建構函式（時間 8 字元粗體、其餘一般）同時供 measurer 與繪製使用，迴紋針圖示繪入連結欄位（有 `url` 才畫，顏色同文字）；`TickerDriver.swift`／`TickerView.swift`：`TrackModel` 改以 Core 的 `seq` 為鍵、`TickerRenderer.add` 冪等、控制列圖層（`<`、`(n/N)`、`>`、停用淡化）、帶子裁切在控制列之外、`mouseDown`／`mouseUp`／tracking area 改為依 `HitTarget` 分派（`.drag` 才 `performDrag`；按鈕與迴紋針在 mouse-up 且命中區未變才觸發）、`TickerDriver.seek`／`setPointerInside`／seek 後補建圖層、`ShellConfig` 新增 `controlStripWidth`／`linkSlotWidth`／`hitSlop` 並以新公式計算 `tapeViewportWidth`。驗證方式：`swift test --filter TickerRenderer`（呼叫序列、`add` 冪等、向後 seek 後重建圖層、量測寬度等於 bitmap 寬度、時間粗體屬性區段、有無迴紋針的像素取樣、控制列不被訊息蓋住的版面斷言）、`swift test --filter NavigationView`（新增，不開視窗，直接呼叫處理方法：按鈕 mouse-up 觸發、移出後放開不觸發、右鍵不觸發、`.drag` 才呼叫 drag 注入點）；fail-then-pass 與 mutation（改成 mouse-down 觸發、讓迴紋針命中區忽略優先序，測試須變紅）。**需人工目視**（併入 9.1）：粗體字重觀感、迴紋針與箭頭外觀、控制列配色。依賴：5.1、6.1。

## 8. 組裝與煙霧測試

- [ ] 8.1 【自動】`AppDelegate.swift`／`AppCoordinator.swift`：組裝 `WorkspaceURLOpener`（唯一真實 opener）、tracking area 與補料計時器的 `PointerHover` 核對、按鈕與迴紋針動作串接 `TickerDriver`；headless 煙霧測試（假 helper 或直接餵 `Message`，不顯示 UI）：含 `url` 的 snapshot／items → 模擬 `.link` 動作時假 opener 收到的 URL 皆為 http(s) 且恰一次；模擬 `<` `>` 使 `(n/N)` 與保持計時符合預期；指標進出與保持期間 `scrollOffset` 行為；點穿模式下無動作。驗證方式：`swift test --filter AppSmoke`、`make test`；`grep -rn "activate(" Sources/` 無對 `NSApp`／`NSApplication` 的啟用呼叫；`swift build` 無警告；擴充既有 `Tests/FastBullTickerAppTests/AppSmokeTests.swift`。依賴：7.1、2.1（假 helper 輸出含 `url`）。

## 9. 人工驗收

- [ ] 9.1 【需人工】使用者在機器前操作並回報（每項 PASS／FAIL／未執行〔含原因〕與截圖或日誌）：(a) 粗體時間、`(n/N)` 與 `<` `>` 外觀與位置是否可接受（控制列右端、帶子縮為 370pt 的觀感，對應待確認 1）；(b) 迴紋針外觀與點擊手感，點擊開啟預設瀏覽器的正確頁面（`https://www.fastbull.com/tw/fastshort/<id>`，由使用者手動點擊，這是使用者操作而非自動請求）；(c) mouse-up 觸發在非啟用面板上是否可靠（失敗則改 mouse-down，屬我方實作修正）；(d) 在 TextEdit 持續打字時操作 `<` `>`、拖曳、滑鼠進出面板，`frontmostApplication` 不變、本 App 啟用通知為零，點擊迴紋針後前景為瀏覽器而非本 App；(e) 滑鼠停在面板上暫停、移出恢復、拖曳視窗期間與結束後無永久凍結；(f) 切換後 8 秒保持、第 8 秒後平順恢復、邊界（第一則按 `<`、最後一則按 `>`）；(g) 點穿模式下不可點擊；(h) 以真 helper 連續執行 ≥10 分鐘，確認 `url` 真實出現且迴紋針可用（需網路；使用者在 VPN／Proxy 下的行為仍照 app-shell 5.4）。結果寫入 `ACCEPTANCE.md`（路徑沿用 app-shell 5.x 的約定，待確認）。依賴：8.1。

## 10. 收尾

- [ ] 10.1 【自動】整體驗證與文件：`make helper app sign` 成功；`cd ticker-connect && cargo test`、`python3 -m unittest discover -s protocol/tests`、`swift test`（或 `make test`）全綠；更新 `README.md` 與 `Tests/README.md` 的測試清單與證據路徑；`openspec validate ticker-navigation-link --strict` 與 `openspec validate --all --strict` 通過；核對 specs 中仍標【假設】／【待確認】的項目並在回報中列出（含 design.md 待釐清 1–12）；app-shell archive 後補 `panel-shell` 拖曳 requirement 的 MODIFIED（見 design.md「待處理」）。驗證方式：以上指令的實際輸出貼入回報並附測試檔路徑清單；未完成或未驗證之處照實說。依賴：1–9。
