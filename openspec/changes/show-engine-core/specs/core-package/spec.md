## ADDED Requirements

### Requirement: SwiftPM 專案結構
專案 SHALL 以 SwiftPM 組成，至少含：`FastBullTickerCore`（library）、`FastBullTickerCoreTests`（測試 target）、`FastBullTicker`（executable）。`FastBullTicker` 在本 change 僅為可編譯的空殼，其正式內容屬 `app-shell`，本 change MUST NOT 實作視窗、選單、渲染、`FeedClient` 或 Makefile。最低部署目標 SHALL 為 macOS 14【假設：設計文件第 8 節標明 macOS 14 最低版本；使用者 2026-10-24 維持暫定，仍標假設】；`FastBullTickerCore` SHALL 使用 Swift 6 語言模式，AppKit 部分日後再議。`Package.swift` 的位置（倉庫根目錄）供 `app-shell` 的 Makefile 引用【假設：設計文件未指定位置，暫放倉庫根目錄；使用者 2026-10-24 維持暫定，仍標假設】。

#### Scenario: 命令列可建置
- **WHEN** 在倉庫根目錄執行 `swift build`
- **THEN** 三個 target SHALL 皆編譯成功，無錯誤

#### Scenario: 命令列可測試
- **WHEN** 在倉庫根目錄執行 `swift test`
- **THEN** SHALL 執行 `FastBullTickerCoreTests` 並回報全數通過

### Requirement: Core 不依賴 UI 或渲染框架
`FastBullTickerCore` 的原始碼 MUST NOT `import` AppKit、SwiftUI、QuartzCore（含 CoreAnimation）、Cocoa、UIKit。允許使用 Foundation。此限制 MUST 由自動化檢查強制，而非僅靠口頭約定。

#### Scenario: 出現被禁的 import
- **WHEN** `Sources/FastBullTickerCore/` 內任一檔案含 `import AppKit`（或其他被禁框架）
- **THEN** 自動化檢查 SHALL 失敗並指出檔案

### Requirement: 測試框架與決定性
Core 的邏輯測試 SHALL 使用 swift-testing（`import Testing`）。測試 MUST NOT 依賴真實時間、真實時區、真實字型或網路；時鐘、時區、measurer 一律由測試注入。

#### Scenario: 測試不依賴系統時鐘
- **WHEN** 在不同的系統時區與不同時間重複執行 `swift test`
- **THEN** 結果 SHALL 相同

### Requirement: 改邏輯須有 fail-then-pass 證據
本 change 中任何邏輯項目 SHALL 先有失敗的測試，再有使其通過的實作，並記錄兩次的指令與輸出摘要。沒有證據時只能宣稱「已修改、未驗證」。完成階段回報 MUST 附實際指令與測試檔路徑。

#### Scenario: 缺少失敗證據
- **WHEN** 一個邏輯 task 被標記完成但沒有先失敗的紀錄
- **THEN** 該 task SHALL 不被視為完成
