## ADDED Requirements

### Requirement: Makefile 目標
Makefile MUST 提供 `helper`（`cargo build --release` 產生 arm64 的 `ticker-connect`）、`app`（組裝 `.app` bundle、放入 Info.plist 與 helper）、`sign`（簽名）、`test`（執行 `swift test` 與 App 層測試）。只支援 arm64；MUST NOT 提供 Intel 目標。

#### Scenario: 乾淨建置
- **WHEN** 在乾淨環境執行 `make helper app sign`
- **THEN** SHALL 產生可啟動的 `FastBullTicker.app`，且各目標獨立可重複執行

#### Scenario: 測試目標
- **WHEN** 執行 `make test`
- **THEN** SHALL 執行 Core 與 App 層測試並以非零 exit code 回報失敗

### Requirement: Bundle 結構與 Info.plist
Bundle MUST 含 `Contents/MacOS/FastBullTicker` 與 helper `Contents/MacOS/ticker-connect`，`Contents/Info.plist` MUST 含 `LSUIElement=YES` 與 `LSMinimumSystemVersion`（暫定 14.0，macOS 14 最低版本【待使用者確認】）。bundle identifier 與名稱【待確認】。

#### Scenario: helper 可被找到
- **WHEN** 組裝後從 bundle 內執行
- **THEN** `Bundle.main.url(forAuxiliaryExecutable: "ticker-connect")` SHALL 回傳 `Contents/MacOS/ticker-connect`

#### Scenario: plist 檢查
- **WHEN** 執行 `plutil -p FastBullTicker.app/Contents/Info.plist`
- **THEN** SHALL 顯示 `LSUIElement => 1`

### Requirement: 複製後一律重新簽名並驗證
helper 複製進 bundle 後 MUST 一律重新 `codesign`（ad-hoc），順序由內而外：先 helper、再主執行檔／bundle；MUST NOT 使用 `--deep`。`sign` 目標最後 MUST 執行 `codesign --verify --strict --verbose=2` 驗證 helper 與 bundle，驗證失敗 MUST 使 `make sign` 失敗。不 notarize、不沙盒。

#### Scenario: 簽名有效
- **WHEN** 執行 `make sign` 後 `codesign --verify --strict -vv FastBullTicker.app`
- **THEN** SHALL 通過，且從 bundle 啟動 helper 不被系統殺掉

#### Scenario: 簽名被破壞
- **WHEN** 在 sign 後修改 helper 一個位元組再執行 verify
- **THEN** verify SHALL 失敗（先失敗後通過：重新 `make sign` 後通過）

#### Scenario: 不使用 deep
- **WHEN** `grep -n -- "--deep" Makefile`
- **THEN** SHALL 無結果

### Requirement: 開發時覆寫 helper 路徑
開發時 MUST 可用環境變數覆寫 helper 路徑（與 `feed-client` 一致）；正式 bundle 不依賴環境變數。

#### Scenario: 預設行為
- **WHEN** 未設定環境變數
- **THEN** SHALL 使用 bundle 內 helper
