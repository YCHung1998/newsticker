# FastBullTicker 設計文件（brainstorming 定案版）

日期：2026-10-24。本文件是後續所有 OpenSpec change 的**唯一設計輸入**。與舊文件衝突時以本文件為準：
- 取代 `SPEC.md` 的 SQLite 與 `.hudWindow` 設定。
- 取代 `TASKS-feed-and-modes.md` 第 3 節的資料表（v1 不用 SQLite）。
- `TASKS-feed-and-modes.md` 的第 4 節（即時／重播行為）與抓取可行性分析仍然有效。
- 非本文件拍板的項目一律標【假設】，**使用者尚未逐條確認**。

## 1. 目標

macOS 桌面浮動跑馬燈，自動取得帶時間的即時財經訊息，可調位置與透明度，永遠在最上層（含蓋過全螢幕 App）。來源連接（Connect engine）與顯示（Show engine）獨立，可日後接其他網頁來源；兩者之間以版本化 JSON Schema 定義 IO 規格。

## 2. 使用者已拍板的決定

| # | 決定 |
|---|---|
| D1 | Connect engine 為**獨立 Rust 行程**，與 Show engine（Swift App）以 **stdout JSON-lines 協定**溝通，單向 helper→App |
| D2 | 蓋過全螢幕 App；App 為 accessory（無 Dock 圖示，選單列控制） |
| D3 | 新來源 = 新增一個 **Rust Connector**（編譯進去）；輸出必須通過共用 JSON Schema 驗證 |
| D4 | helper **隨 App 啟動、隨 App 結束**；App 關閉期間漏掉的訊息一律當歷史 |
| D5 | 位置靠拖曳；透明度靠選單列滑桿，**整條帶子含文字一起透明**；位置與透明度要記住 |
| D6 | **v1 不用 SQLite**，去重與最新 10 則放 helper 記憶體 |
| D7 | 即時訊息白底黑字；無新訊息時循環播放最新 10 則（含時間）；重播中來新訊息則接在尾端已排入的最後一則後面並切即時 |
| D8 | 不使用 WebView／Electron |

## 3. 協定（`protocol/`，版本化 JSON Schema）

單向、每行一個 JSON，欄位 `v` 為協定版本。

| `type` | 內容 | 用途 |
|---|---|---|
| `snapshot` | `items[]`（新到舊） | 第一次成功輪詢，視為歷史，餵重播 |
| `items` | `items[]`（舊到新） | 之後輪詢的新訊息，進即時佇列 |
| `status` | `source`、`state`（ok／error）、`message` | 連線健康度；**至少每 30 秒發一次，兼作心跳** |

`item` 欄位：`source`、`id`（來源內唯一字串）、`published_at_ms`（UTC 毫秒）、`text`。FastBull 的「重要」旗標頁面有，但未要求顯示，v1 不入契約。

## 4. Connect engine（Rust，`ticker-connect`）

```rust
trait Connector {
    fn source_id(&self) -> &str;
    fn interval(&self) -> Duration;
    async fn fetch(&self) -> Result<RawPayload, ConnectError>;
    fn convert(&self, raw: RawPayload) -> Result<Vec<Item>, ConnectError>; // 純函式，用快照測
}
```

引擎行為（所有來源共用）：
- 第一次成功輪詢發 `snapshot`；之後以 `id` 與記憶體 seen-set（上限約 500）比對，只發新的 `items`（舊到新）。
- fetch 失敗、HTTP 非 200、convert 解析 0 則 → 發 `status: error`，退避重試（10→30→60 秒封頂），**不改變已見過的狀態**，不當成「沒新訊息」。
- 單次輪詢超過 10 則「新」訊息 → 不當即時，改發新的 `snapshot` 重設基準【假設，10 為暫定值】。
- 輪詢間隔預設 10 秒，實測連續請求會拿到新資料後再決定能否降到 5 秒。
- 監看 stdin，EOF 立即退出（獨立執行緒，不被阻塞的網路請求卡住）；可選加 `getppid` 檢查作保險。
- stdout 只輸出協定 JSON，日誌走 stderr；每個 item 輸出前過 schema 驗證，不合格丟棄並發 `status` 警告。

### FastBull 連接器（第一個來源）

已實測（2026-10-24，快照 `docs/fixtures/express-news-2026-10-24.html`）：
- `GET https://www.fastbull.com/tw/express-news` 回 200，快訊已在伺服器回傳的 HTML 內，預設為「推薦」分頁，共 20 則，與使用者截圖逐筆一致。
- `div.news-list[data-id]` → `id`；`div.news-list[data-date]`（毫秒 epoch）→ `published_at_ms`；`span.title_name` 文字 → `text`。畫面時間文字由 JS 填入，不可解析。
- robots.txt 只限制 Baiduspider／Googlebot，對此路徑無規則；**服務條款未逐條讀**【待使用者確認】。
- 站上另有 WebSocket 推播（STOMP over SockJS），需逆向，v1 不採用。

## 5. Show engine（Swift，macOS 14+，arm64）

### 5.1 純邏輯 `FastBullTickerCore`（無 AppKit）
- 協定型別（Codable，對應 JSON Schema）。
- `LineBuffer`：以 0x0A 切行，保留尾端半行，單行上限 1MB，超過丟棄並報錯；單行解析失敗不終止串流。
- `TickerScheduler`：注入時鐘；tape 座標；REPLAY／LIVE 狀態機；供料器在尾端有空位時補下一則；隱藏時**凍結 tape 時間**，回來接著走。
- 版面計算：寬度由注入的 measurer 提供。

行為規則（沿用 `TASKS-feed-and-modes.md` 第 4 節）：
1. `items` 抵達 → 進即時佇列，白底黑字。
2. REPLAY 中收到新訊息：帶子上已排入的訊息不中斷；新訊息接在尾端已排入的最後一則後面；供料器改切 LIVE。
3. LIVE 中再來新訊息 → 追加到佇列尾端。
4. 即時佇列播完 → 回 REPLAY，重新取最新 10 則，從最新一則開始循環。
5. 啟動時 `snapshot` 為歷史，直接 REPLAY。
6. 樣式跟著每一則訊息本身，已在帶子上的訊息不改樣式。

【假設】A1 多則即時訊息由舊到新播放；A2 每則即時訊息只播一次；A3 重播為黑底白字；A4 時間顯示本機時區 `HH:mm:ss`；A6 隱藏期間新訊息仍進佇列；A7 即時佇列上限 30，超過丟棄最舊（它們仍會出現在重播最新 10 則）；A8 單則文字以**量測後的寬度**截斷並加「…」，而非字元數。

### 5.2 App 殼層 `FastBullTicker`
- `FeedClient`：`Process`＋`Pipe` 啟動 helper；generation token 忽略過期事件；退避 1→60 秒加 jitter，穩定跑超過 60 秒才重置；stderr 一律讀走；`readabilityHandler` 收到 EOF 要清除 handler；卡死判定至少 3 倍心跳間隔、**任何輸出都算活著**、睡眠喚醒後給寬限期；不可恢復的錯誤不無限重啟。
- `TickerRenderer`（介面）：預設實作用 `NSView.displayLink`（macOS 14+）逐幀依 tape 時間設定 container layer 位置；每則訊息預渲染為 bitmap layer；定期 rebase 避免 Float32 精度劣化（60px/s 跑 24 小時約 5M px，精度約 0.5px）。候補實作：單一線性 `CABasicAnimation`。**兩案以 spike S4 的實測數字決定**。
- `PanelShell`：`NSPanel`，styleMask `[.borderless, .nonactivatingPanel]`（init 一次設定，**不用 `.hudWindow`**）；`hidesOnDeactivate = false`；`canBecomeKey/Main = false`；`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`，並將 `canJoinAllApplications` 列入實測；level 在 `.floating`／`.statusBar` 實測擇一（不用 `.screenSaver`）；`isOpaque=false`、`backgroundColor=.clear`、`hasShadow=false`；透明度用 window `alphaValue`，純色背景，不用毛玻璃；滑桿下限約 20–30%；拖曳用 `performDrag(with:)`，位置存檔改聽 `NSWindow.didMoveNotification`（debounce），因 mouse-up 可能不送達；程式內**永不呼叫 `NSApp.activate`**。
- `StatusMenu`：`NSStatusItem`＋`NSMenu`（透明度滑桿用 `NSMenuItem.view`、隱藏／顯示、點穿開關、結束）；面板右鍵提供同一份選單作後備入口；**點穿模式不跨重啟保存，啟動一律重置為關**。選單展開期間計時器必須用 `.common` mode 或 `DispatchSourceTimer`。
- `Persistence`：螢幕 UUID（`CGDisplayCreateUUIDFromDisplayID`）＋相對偏移＋透明度；找不到螢幕退回主螢幕並夾在可視區內；監聽 `didChangeScreenParametersNotification`。
- 預設【假設】：單一視窗，初始約 620×42，放上次所在螢幕；只給作者自用（ad-hoc 簽名、不 notarize、不沙盒）；不支援 Intel；不做全域快捷鍵；捲動速度為固定常數，目測調整；點擊帶子＝拖曳，v1 不做開啟詳情。

### 5.3 專案與建置
- SwiftPM：`FastBullTickerCore`（library）＋`FastBullTicker`（executable）；Makefile 目標：`helper`（cargo build）、`app`（組裝 bundle、放入 Info.plist 的 `LSUIElement=YES` 與 helper）、`sign`、`test`。
- helper 放 `Contents/MacOS/`（`Bundle.main.url(forAuxiliaryExecutable:)` 可找到）；**複製進 bundle 後一律重新 codesign（由內而外，不用 `--deep`）並驗證**，避免 arm64 上簽名失效被系統殺掉。
- Rust 獨立 cargo 建置後複製，不掛進 Xcode Run Script。開發時可用環境變數覆寫 helper 路徑。
- 純邏輯測試用 swift-testing；UI／效能測量用 XCTest；FeedClient 以假 helper 腳本做整合測試（正常輸出、崩潰、半行、卡死、stderr 灌滿）。
- 工具鏈（實測）：macOS 26.5.1、Xcode 26.6、Swift 6.3.3、已有 rustc／cargo、沒有 xcodegen／tuist。

## 6. 平台行為查證狀況（來自資深 macOS 工程師角色的審查）

**已查證（Apple 官方文件）**：`NSPanel.hidesOnDeactivate` 預設 true（必須設 false）；opaque view 的 `mouseDownCanMoveWindow` 預設 false；`performDrag(with:)` 的 mouse-up 可能不送達；`NSView.displayLink` 為 macOS 14.0；`CAAnimation.preferredFrameRateRange` 與 `CAFrameRateRange` 為 macOS 12.0（降幀實效未查）；選單追蹤使用 `NSEventTrackingRunLoopMode`，預設 mode 的 `Timer` 會停擺；`canJoinAllApplications` 為 macOS 13.0。

**官方查無，仍是經驗（必須由 spike 驗證）**：`.nonactivatingPanel` 必須在 init 設定；`.hudWindow` 在 borderless 下的表現；`stationary` 與 `canJoinAllSpaces`、`fullScreen*` 的互斥關係；`performDrag` 在非 key 的 nonactivating panel 上的行為；`MenuBarExtra(.window)` 是否搶 Focus；macOS 26 的行為。

**反例回報（未經本方核對）**：Apple 開發者論壇 2025-07「NSWindowCollectionBehavior in Full Screen Spaces」與 thread 759780 有人回報類似旗標組合在全螢幕 Space 看不到視窗。因此**「蓋過全螢幕」不得當成已知**，S1 不過關就先回頭改需求。若有部分全螢幕 App 蓋不過去，預設接受並寫進已知限制【使用者待確認，屬需求變更】。

## 7. 先行可行性實驗（spike，丟棄式，不進正式專案）

| # | 內容 | 通過標準 |
|---|---|---|
| S1 | 全螢幕可見性：level（`.floating`／`.statusBar`）× 有無 `canJoinAllApplications`；情境：全螢幕 Safari、Keynote／QuickTime、Split View、Stage Manager 開關、外接螢幕（獨立 Space 開關）、睡眠喚醒後、切換 Space 後 | 常用全螢幕 App 都看得到；失敗組合記入已知限制 |
| S2 | 不搶 Focus：在另一 App 持續打字，同時點擊／拖曳面板、操作選單列選單與滑桿；以 `NSWorkspace.didActivateApplicationNotification` 與 `frontmostApplication` 記錄 | frontmost 全程不變、打字不中斷、本 App 啟用通知為零 |
| S3 | 選單展開 60 秒以上，補料計時器（default mode／`.common`／`DispatchSourceTimer`）是否斷料；同時拖動滑桿 | 帶子無空白、滑桿即時生效、補料誤差 < 100ms |
| S4 | 渲染 A/B：displayLink vs 線性 `CABasicAnimation`，各以 10 則假訊息（含 400 字元 CJK 長句）跑 1 小時；量 CPU、記憶體、WindowServer 負載；驗證 `preferredFrameRateRange` 降到 30fps 的實效；驗證長句 bitmap 寬度是否超過紋理上限（約 16384px，記憶待實測，超過則切塊） | CPU 穩定偏低、記憶體曲線平坦、長時間文字不抖、凍結／恢復無可見跳動 |

另兩項併入實作驗收：helper 生命週期（`kill -9` App 後數秒內無孤兒；喚醒後心跳不誤判；stderr 灌滿不阻塞；複製進 bundle 後簽名仍有效）、螢幕參數變更（拔插、改解析度、鏡像後面板至少部分可見且下次啟動回到正確螢幕）。

## 8. 風險（依嚴重度）

1. 全螢幕可見性無保證（S1）。
2. 渲染方案狀態分散，凍結／rebase 邊界易跳動（S4 以數字決定）。
3. 心跳在睡眠喚醒、VPN 重連時誤判卡死。
4. 複製進 bundle 後簽名失效。
5. 點穿模式鎖住自己（故不跨重啟保存）。
6. 隱藏期間佇列積壓（A7 上限規則）。
7. VPN／Proxy 下 Rust TLS 與 proxy 行為未知，須在寫 helper 時以實際網路驗證。
8. 記憶體目標暫定 App ≤35MB、helper ≤15MB【假設】，先量基準再收緊；`macOS 14` 最低版本與 `記憶體` 門檻待使用者確認。

## 9. OpenSpec change 拆分（循序，非平行；每個 change 的 tasks ≤ 12）

| 順序 | change 名稱 | 內容 |
|---|---|---|
| 1 | `message-contract` | `protocol/` JSON Schema（snapshot／items／status）、驗證用 fixtures（合法與非法樣本）、兩端共用的契約測試 |
| 2 | `connect-engine-fastbull` | Rust `ticker-connect`：Connector trait、Scheduler／退避、seen-set／基準／洪水保護、stdin-EOF 退出、emitter＋schema 驗證、FastBull 連接器（用快照 fixture 測） |
| 3 | `panel-feasibility-spikes` | S1–S4 的步驟、通過標準、結果記錄格式；產出「已知限制」與渲染方案決定 |
| 4 | `show-engine-core` | SwiftPM 專案骨架、`LineBuffer`、`TickerScheduler`（假時鐘）、版面計算，全部以 swift-testing 做 fail-then-pass |
| 5 | `app-shell` | `PanelShell`、`StatusMenu`、`Persistence`、`TickerRenderer`（依 S4 結果）、`FeedClient`、Makefile 組裝與簽名；端到端驗收（假 helper → 真 helper） |

依賴：1 → 2 與 3（可由不同時間處理，但本流程循序）→ 4（依賴 1）→ 5（依賴 3、4）。

## 10. 非目標（v1）

通知、搜尋、歷史瀏覽、多來源同時顯示、設定頁、全域快捷鍵、Intel、App Store 發行、Developer ID／notarization、每螢幕一視窗、使用者調整寬度、點擊開啟詳情、可調捲動速度。
