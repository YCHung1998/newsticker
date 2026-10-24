## ADDED Requirements

### Requirement: 實驗為丟棄式且與正式專案隔離
所有實驗程式 MUST 放在專案根目錄 `spikes/` 下，以 SwiftPM 命令列建置（`swift build`），MUST NOT 依賴 Xcode GUI、xcodegen 或 tuist。`spikes/` 的程式 MUST NOT 被正式專案（`FastBullTickerCore`、`FastBullTicker`）import 或複製；實驗結論 SHALL 只以 `spikes/RESULTS.md` 的文字決定傳遞給下游。實驗程式 MUST NOT 使用 `message-contract` 的協定、不連網路、不啟動 `ticker-connect`；訊息一律為內建假訊息。

#### Scenario: 以命令列建置實驗
- **WHEN** 在 `spikes/` 執行 `swift build`
- **THEN** 建置 SHALL 成功，且過程不需開啟 Xcode

#### Scenario: 正式專案不引用實驗
- **WHEN** 於正式專案目錄 grep `spikes`
- **THEN** SHALL 無任何 import 或路徑引用【驗收於 `app-shell`】

### Requirement: 結果紀錄格式
每一格實驗結果 MUST 記錄在 `spikes/RESULTS.md`，每格至少包含：實驗代號（如 `S1-03`）、日期（ISO 8601）、macOS 版本（`sw_vers` 輸出）、組合參數（level、`canJoinAllApplications`、`collectionBehavior` 完整清單等）、情境、結果（PASS／FAIL／未執行）、觀察文字、證據路徑（截圖或日誌，相對於 `spikes/`）。FAIL 與未執行 MUST 保留，不得刪除；未執行的格 MUST 寫明原因。【`RESULTS.md` 為建議檔名，設計文件未指定。】

#### Scenario: 格式完整性檢查
- **WHEN** 執行 `spikes/` 內的結果檢查腳本
- **THEN** 腳本 SHALL 對缺少日期、macOS 版本、組合、結果或證據路徑的格回報錯誤，並確認每個證據路徑指向存在的檔案

#### Scenario: 失敗結果保留
- **WHEN** 某格結果為 FAIL
- **THEN** 該格 SHALL 留在 `RESULTS.md`，並附觀察與證據

### Requirement: 每項任務標明自動或需人工
凡需要使用者在場操作或目視（全螢幕、睡眠喚醒、外接螢幕、拖曳、選單操作、連續一小時實測）的實驗步驟，在 `tasks.md` MUST 標「需人工」並寫明使用者要做什麼、所需硬體與前提；可由命令列或腳本完成並自動判定者標「自動」。MUST NOT 把需人工的步驟寫成自動驗收。

#### Scenario: tasks 標註檢查
- **WHEN** 審閱 `tasks.md`
- **THEN** 每一項 SHALL 含「自動」或「需人工」其中之一，且需人工項 SHALL 寫明硬體與前提

### Requirement: S1 全螢幕可見性矩陣
S1 MUST 建立測試面板，styleMask `[.borderless, .nonactivatingPanel]`（於 init 設定）、`hidesOnDeactivate = false`、`canBecomeKey/Main = false`、`isOpaque = false`、`backgroundColor` 為高對比純色（便於目視）；基底 `collectionBehavior` 為 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`。矩陣維度 MUST 為：level（`.floating`、`.statusBar`）× 有無 `canJoinAllApplications`，共 4 種組合；另 MUST 針對**通過全部必要情境的組合**（若無則針對任一組合）再各跑一次「移除 `.stationary`」的對照，以驗證 `stationary` 與 `canJoinAllSpaces`／`fullScreen*` 的互斥或相互影響。不使用 `.screenSaver` level。組合 MUST 可由命令列參數切換，不需重新編譯。

情境 MUST 包含：全螢幕 Safari；全螢幕 Keynote 或 QuickTime（擇一以上，擇用者記錄於 RESULTS）；Split View；Stage Manager 開／關；外接螢幕（系統設定「螢幕有獨立 Space」開與關各一次）；睡眠喚醒後；切換 Space 後。每一格 MUST 以截圖或螢幕錄影作為證據。

#### Scenario: 組合以參數切換
- **WHEN** 以 `--level statusBar --join-all-apps on` 之類參數啟動 S1 實驗
- **THEN** 面板 SHALL 以該組合顯示，並將實際生效的 level 與 `collectionBehavior` 寫入日誌

#### Scenario: 單格判定
- **WHEN** 某組合在某情境下面板於螢幕上可見（截圖可辨識）
- **THEN** 該格 SHALL 記為 PASS；不可見或僅部分可見 SHALL 記為 FAIL 並附截圖

#### Scenario: S1 通過標準
- **WHEN** 某組合在「全螢幕 Safari」與「全螢幕 Keynote 或 QuickTime」下，於各必要情境（Split View、切換 Space、睡眠喚醒後、外接螢幕）皆可見
- **THEN** 該組合 SHALL 被視為通過 S1；「常用全螢幕 App」的範圍除上述兩者外，是否含更多 App【待確認】

#### Scenario: 論壇反例回報
- **WHEN** 規劃或回報 S1 結果
- **THEN** 文件 SHALL 註明：論壇有類似旗標組合在全螢幕 Space 看不到視窗的反例回報（未經核對），故「蓋過全螢幕」MUST NOT 在 S1 完成前被當成已知事實

### Requirement: S2 不搶 Focus
S2 MUST 在另一個 App（建議 TextEdit，擇用者記錄）持續打字的同時，依序操作：點擊面板、拖曳面板、操作選單列選單、拖動選單內滑桿。實驗程式 MUST 監聽 `NSWorkspace.didActivateApplicationNotification` 並以固定間隔（不超過 1 秒）取樣 `NSWorkspace.shared.frontmostApplication`，將時間戳、前景 App bundle id、啟用通知內容寫入日誌。打字內容 MUST 為已知重複字串（如 `abcdefghij` 重複），事後比對無缺漏。選單列入口 MUST 做兩種對照：`NSStatusItem`＋`NSMenu`（正式設計方案），以及 `MenuBarExtra(.window)`（驗證其是否搶 Focus）。另 MUST 做一組對照：`.nonactivatingPanel` 於 init 設定 vs 建立後才設定，以驗證「必須在 init 設定」的經驗說法。

通過標準：`frontmostApplication` 全程不變、打字不中斷且無缺漏、日誌中本 App 的啟用通知為零。

#### Scenario: 正式方案通過
- **WHEN** 使用 `NSStatusItem`＋`NSMenu` 與 init 設定的 `.nonactivatingPanel`，完成上述全部操作
- **THEN** 日誌 SHALL 顯示 frontmost 全程為打字目標 App、本 App 啟用通知為 0、打字字串比對無缺漏，否則該格記 FAIL

#### Scenario: MenuBarExtra 對照
- **WHEN** 使用 `MenuBarExtra(.window)` 重複同樣操作
- **THEN** 結果 SHALL 如實記錄（無論搶 Focus 與否）；此對照不影響正式方案採用 `NSStatusItem`，僅作為設計文件第 6 節的查證

#### Scenario: init 與事後設定 styleMask 對照
- **WHEN** 分別以 init 設定與建立後才設定 `.nonactivatingPanel` 進行點擊面板操作
- **THEN** 兩者的 frontmost 變化 SHALL 並列記錄於 RESULTS

### Requirement: S3 選單展開期間補料計時器
S3 MUST 實作一條簡易假帶子與補料計時器：帶子以固定速度捲動，計時器在尾端有空位時補下一則假訊息。MUST 比較三種計時器：預設 run loop mode 的 `Timer`、加入 `.common` mode 的 `Timer`、`DispatchSourceTimer`。每種 MUST 在選單展開（`NSStatusItem` 選單，含內嵌滑桿的 `NSMenuItem.view`）不少於 60 秒期間量測，同時拖動滑桿改變 `alphaValue`。日誌 MUST 記錄每次補料的預定時間與實際觸發時間，以及補料當下帶子尾端空位寬度。

通過標準：帶子無空白（尾端空位未出現使可見區出現空白的情況）、滑桿即時生效（`alphaValue` 變更於操作當下可見）、補料誤差（實際減預定）< 100ms。

#### Scenario: 預設 mode 的 Timer
- **WHEN** 選單展開超過 60 秒期間，預設 mode 的 `Timer` 被使用
- **THEN** 其補料次數與誤差 SHALL 如實記錄；若出現停擺（連續漏補或誤差 ≥ 100ms）則該格記 FAIL（預期結果依設計文件為停擺，但以實測為準）

#### Scenario: 候選計時器通過
- **WHEN** `.common` mode 的 `Timer` 或 `DispatchSourceTimer` 於選單展開 60 秒以上
- **THEN** 若每次補料誤差皆 < 100ms 且帶子無空白，該格 SHALL 記 PASS，並計算最大與 p99 誤差

#### Scenario: 滑桿同時操作
- **WHEN** 選單展開期間持續拖動滑桿
- **THEN** 日誌 SHALL 記錄滑桿回呼時間戳，且 `alphaValue` 變更 SHALL 於目視可見，否則記 FAIL

### Requirement: S4 渲染方案 A/B 實測
S4 MUST 實作兩個渲染方案並以相同條件各跑 1 小時：A = `NSView.displayLink`（macOS 14+）逐幀設定 container layer 位置；B = 單一線性 `CABasicAnimation`。內容為 10 則假訊息，其中至少一則為 400 字元 CJK 長句；每則預渲染為 bitmap layer。兩方案 MUST 在同一台機器、同一螢幕、插電、無其他重負載、相同面板尺寸（約 620×42【假設】）下執行。量測 MUST 以固定間隔（不超過 10 秒）取樣並寫入 CSV：App 的 CPU%、常駐記憶體（RSS）、`WindowServer` 行程的 CPU%。額外 MUST 驗證：(1) `preferredFrameRateRange` 設為 30fps 的實效（以實測幀間隔分佈判定，記錄實際落在 30 或其他值）；(2) 長句 bitmap 寬度是否超過紋理上限（約 16384px，記憶待實測），超過則驗證切塊方案是否消除問題；(3) 凍結／恢復（隱藏再顯示）時是否有可見跳動。

通過標準（設計文件）：CPU 穩定偏低、記憶體曲線平坦、長時間文字不抖、凍結／恢復無可見跳動。上述形容詞的數字門檻【待確認】；在使用者確認前，本規格暫定以「記錄全部數字並以相對比較決定」處理，不設絕對門檻。

#### Scenario: 取樣資料
- **WHEN** 一個方案跑滿 1 小時
- **THEN** SHALL 產生含 CPU%、RSS、WindowServer CPU% 的 CSV，取樣點數不少於 360 筆（以 10 秒間隔計），並於 RESULTS 記錄平均、最大、p95 與 RSS 起訖差

#### Scenario: 長句紋理上限
- **WHEN** 400 字元 CJK 長句預渲染的 bitmap 像素寬度超過 16384
- **THEN** 實驗 SHALL 記錄該寬度、是否出現空白或截斷，及切塊後的結果；若未超過，SHALL 記錄實測寬度與使用的字型大小與縮放倍率

#### Scenario: 30fps 實效
- **WHEN** 對方案設定 `preferredFrameRateRange` 為 30fps
- **THEN** SHALL 記錄實測幀間隔分佈與 CPU 變化；若實效不成立，MUST 如實記錄而非假設成立

#### Scenario: 凍結與恢復
- **WHEN** 隱藏面板 10 秒後再顯示
- **THEN** 人工目視並錄影，SHALL 記錄文字位置是否有可見跳動

### Requirement: S5 面板行為補充實驗
S5 涵蓋設計文件第 6 節「官方查無」中未被 S1–S4 完整涵蓋者，MUST 包含：(a) 同一面板分別以 `[.borderless, .nonactivatingPanel]` 與加上 `.hudWindow` 建立，記錄外觀（陰影、圓角、背景、透明度表現）、`alphaValue` 是否生效、是否影響不搶 Focus；(b) 在非 key 的 nonactivating panel 上以 `performDrag(with:)` 拖曳：是否能拖動、拖動期間 frontmost 是否變化、mouse-up 是否送達；(c) 以 `NSWindow.didMoveNotification`（含 debounce）儲存位置，驗證在 mouse-up 未送達時位置仍被存下，並於重啟後還原；(d) opaque view 的 `mouseDownCanMoveWindow` 預設 false 與拖曳方式的關係（已查證項目，僅確認一致）。

#### Scenario: hudWindow 對照
- **WHEN** 以兩種 styleMask 建立面板並顯示
- **THEN** 兩者外觀與行為差異 SHALL 並列記錄，並附截圖

#### Scenario: performDrag 於非 key 面板
- **WHEN** 在不可成為 key 的 nonactivating panel 上 mouseDown 後呼叫 `performDrag(with:)`
- **THEN** SHALL 記錄是否拖動成功、frontmost 是否不變、mouse-up 是否送達

#### Scenario: didMove 存位置
- **WHEN** 拖曳結束後結束 App 再重啟
- **THEN** 面板 SHALL 還原到 `didMoveNotification` 最後記下的位置；若不一致記 FAIL 並附日誌

### Requirement: 設計文件第 6 節完整涵蓋
設計文件第 6 節「官方查無」清單的每一條 MUST 對應至少一項實驗；對照表 SHALL 維持於 `design.md`，且 `RESULTS.md` 的每項結果 MUST 標明其回應的清單條目。

#### Scenario: 對照表無遺漏
- **WHEN** 比對 `design.md` 對照表與設計文件第 6 節「官方查無」清單
- **THEN** 清單中每一條 SHALL 在對照表中有對應實驗代號
