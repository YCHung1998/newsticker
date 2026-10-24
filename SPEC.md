# FastBullTicker 需求規格書

> 狀態：草稿 v2（2026-10-24）。整合 `handoff_document.md`、`agent_guidelines.md` 與使用者提供的 SPEC 草稿與參考截圖。
> 標 **【待決策】** 的項目，三份來源互相矛盾或沒有定義，開工前要由 Eason 拍板（見第 6 節）。
> 本文件內所有程式碼都是示意，**尚未編譯或執行**。

---

## 1. STAR

### Situation（情況）
- 使用者需要即時掌握 FastBull 財經快訊（`https://www.fastbull.com/tw/express-news`），但開著網頁分頁會佔桌面空間、干擾主工作流。
- 以網頁包殼（Nativefier、Electron、Safari PWA）的做法維護成本高、記憶體大，也難以做到 macOS 原生視窗行為（跨桌面、不搶 Focus、動態切換視窗層級）。
  - 「Nativefier 已於 2023 年歸檔」與「Electron >200MB」是草稿中的說法，**未經本人查證**，不作為規格依據。

### Task（任務）
做一個 macOS 原生懸浮財經快訊跑馬燈：
- Swift（AppKit + SwiftUI）做 UI，Rust 做抓取與 SQLite。
- 本地 SQLite 快取，保留 3 天，其餘自動清除。
- 視窗可拖曳，可在「永遠置頂」與「一般層級」之間切換。

### Action（行動）
1. Rust 核心：Tokio + reqwest 定期抓取，解析後寫入 SQLite，啟動時與每次輪詢時執行 3 天清理。
2. Swift 前端：`NSPanel` 無邊框視窗，橫向捲動跑馬燈，從同一個 SQLite 檔讀資料。
3. 兩端的整合方式見第 6 節【待決策】#1。

### Result（結果／驗收）
見第 5 節。核心指標：低記憶體、閒置低 CPU、不搶 Focus、跨桌面、DB 不積壓舊資料。

---

## 2. 範圍

**範圍內**
- 抓取 FastBull 快訊並本地快取。
- 浮動跑馬燈視窗、釘選切換、拖曳。

**非目標（來源文件明確禁止或未要求）**
- 不使用 WebView：`WKWebView`、Electron、Tauri、Nativefier 一律不用（`agent_guidelines.md`）。
- 草稿與截圖都沒提到的功能不做，包括通知、搜尋、多來源、設定頁。若需要要另外提案。

---

## 3. 架構

```
Swift (AppKit/SwiftUI)  ── NSPanel HUD、TickerView
        │  讀
        ▼
   news.db (SQLite，Application Support) ◄── 寫 ── Rust fastbull_core (Tokio + reqwest + scraper + rusqlite)
```

- SQLite 是唯一的持久化事實來源。
- Swift 主執行緒不做網路與重度 DB 操作。輪詢由 Rust 或 `Task.detached` 負責。
- 建議目錄（`agent_guidelines.md` 與草稿的命名不一致，這裡統一）：

```
FastBullTicker/
├── FastBullTicker.xcodeproj
├── FastBullTicker/            # Swift：Views/FloatingPanel.swift、Views/TickerView.swift、Database/DatabaseBridge.swift
└── fastbull_core/             # Rust：src/lib.rs、db.rs、fetcher.rs
```

### 3.1 資料表
```sql
CREATE TABLE IF NOT EXISTS news (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    title TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```
- 寫入一律 `INSERT OR IGNORE`，以 `title` 去重。
- `timestamp`：FastBull 的發布時間文字，格式與時區**【待決策】#5**。
- `created_at`：寫入時間（SQLite `CURRENT_TIMESTAMP` 為 UTC）。

### 3.2 保留政策
```sql
DELETE FROM news WHERE created_at < datetime('now', '-3 days');
```
- 每次 DB 初始化與每次輪詢都要執行。
- **已知風險**：清理依 `created_at`（寫入時間），去重依 `title`。若 FastBull 頁面仍列著超過 3 天的舊快訊，清掉後下一輪輪詢會被重新 `INSERT`，`created_at` 變成現在，舊快訊會「復活」。需要擇一處理，見【待決策】#6。

### 3.3 視窗規格（`NSPanel`）
| 項目 | 值 |
|---|---|
| styleMask | `[.borderless, .nonactivatingPanel, .hudWindow]` |
| 預設 level | `.floating`，可切到 `.normal` |
| collectionBehavior | `[.canJoinAllSpaces, .fullScreenAuxiliary]` |
| 拖曳 | `isMovableByWindowBackground = true` |
| 背景 | 毛玻璃（見【待決策】#3） |
| 初始大小 | 約 620×42（草稿值） |

示意程式（未編譯）：
```swift
final class FloatingPanel: NSPanel {
    init(contentView: some View) {
        super.init(contentRect: NSRect(x: 100, y: 100, width: 620, height: 42),
                   styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        self.contentView = NSHostingView(rootView: contentView)
    }
    func setPinned(_ pinned: Bool) { level = pinned ? .floating : .normal }
}
```
注意：`.ultraThinMaterial` 是 SwiftUI 的 `Material`，不是 `NSVisualEffectView.Material`。草稿裡 `view.material = .ultraThinMaterial` 不會編譯。AppKit 側要用 `.hudWindow` 等，或在 SwiftUI 視圖用 `.background(.ultraThinMaterial)`。

### 3.4 UI 外觀
參考截圖：左側斜切的紅色標籤「即時財經快訊 - FastBull」，右側黑底白字橫向捲動標題。截圖是不透明黑底，草稿要求毛玻璃，兩者衝突，見【待決策】#3。

---

## 4. 環境與建置

**前置需求**（草稿值，未驗證）：macOS 13+、Xcode 15+（Swift 5.9+）、Rust 1.75+、系統內建 SQLite3。

**指令**
```bash
cd fastbull_core && cargo build --release
cargo test test_cleanup_old_data          # 單一測試（測試目前尚未存在）
xcodebuild -scheme FastBullTicker -configuration Release
```
- 若採靜態庫整合，`Cargo.toml` 需設 `crate-type = ["staticlib"]`，預設的 `cargo init --lib` 不會產出 `libfastbull_core.a`。

**實作順序**
1. Rust 核心：先做抓取可行性驗證，再做 SQLite 與 3 天清理（見【待決策】#4）。
2. Swift `NSPanel` 視窗與釘選切換。
3. 資料橋接與跑馬燈 UI。

---

## 5. 驗收標準（DoD）

| 編號 | 項目 | 預期 | 驗證方式 |
|---|---|---|---|
| TC-01 | 跨桌面 | 切換 Mission Control 桌面，視窗仍在 | 手動 |
| TC-02 | Focus | 點釘選按鈕時，正在輸入的 App 不失去鍵盤 Focus | 手動 |
| TC-03 | 釘選切換 | Unpinned：被其他視窗覆蓋；Pinned：維持最上層 | 手動 |
| TC-04 | 3 天清理 | 插入 4 天前的資料，啟動後該筆被刪除 | 自動（`cargo test`），應附 fail-then-pass |
| TC-05 | 資源 | 連續捲動 1 小時，記憶體低於門檻、無洩漏 | 手動（Activity Monitor／Instruments） |
| TC-06 | 去重 | 重複標題只存一筆 | 自動 |
| TC-07 | 舊資料不復活 | 清理後再次輪詢到舊快訊，不會重新出現 | 自動，對應【待決策】#6 |

資源門檻：記憶體 **<30MB（`handoff_document.md`）或 <35MB（草稿）**，【待決策】#2。

---

## 6. 待決策清單（開工前要拍板）

| # | 問題 | 衝突或缺口 | 建議 |
|---|---|---|---|
| 1 | Rust 與 Swift 怎麼整合 | `handoff` 寫共用 SQLite，草稿寫「C-ABI/FFI 或共用 SQLite」，建置步驟又連結 `libfastbull_core.a`。若只共用 SQLite，必須有人負責啟動 Rust 輪詢 | 只用共用 SQLite（開 WAL）；Rust 做成隨 App 啟動的獨立 helper 行程，不做 FFI |
| 2 | 記憶體門檻 | 30MB 對 35MB | 先定 35MB，量測後再收緊 |
| 3 | 背景是毛玻璃還是黑底 | 草稿要毛玻璃（「Syrtis 質感」，Syrtis 未定義）；截圖是不透明黑底加紅標籤 | 請確認以哪個為準；若兩者都要，需定義可讀性規則 |
| 4 | 抓取方式可行嗎 | **已解決（2026-10-24 實測）**：快訊已在伺服器回傳的 HTML 內，含 `data-id`、毫秒 `data-date`。細節與新 schema 見 `TASKS-feed-and-modes.md`。服務條款仍待確認 | 輪詢 HTML；WebSocket 暫不採用 |
| 5 | `timestamp` 格式與時區 | 文字欄位、無格式定義 | 存 ISO-8601 UTC，並註明來源頁的時區 |
| 6 | 舊資料復活 | 見 3.2 | 寫入時過濾掉發布時間超過 3 天的項目，或清理依發布時間而非 `created_at` |
| 7 | 「閒置 CPU 趨近 0%」 | 持續捲動動畫不可能 0% | 改為「捲動時 CPU < X%，暫停或被遮住時趨近 0」，X 由量測決定 |
| 8 | 互動與輪詢 | 輪詢間隔、斷網行為、點標題是否開啟連結、釘選按鈕位置，三份來源都未定義 | 需要時再補，現階段不實作 |
