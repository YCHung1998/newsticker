## 1. 契約檔案與樣本

- [x] 1.1 建立 `protocol/` 目錄，撰寫 `item`、`snapshot`、`items`、`status` 的 JSON Schema（含 `$schema`、`v`、`type`）。驗收：`python3 -m unittest discover -s protocol/tests -v` 中 `SchemaMeta` 測試通過（參考驗證器為本機已有的 Python `jsonschema`，已決定 2026-10-24）。
- [x] 1.2 先寫合法樣本 fixtures（snapshot、items、status ok／error、CJK、跳脫字元）與 `fixtures/manifest.json`。驗收：測試列出每個合法樣本且全部 accept。
- [x] 1.3 撰寫非法樣本 fixtures（缺 `v`／`type`、未知 `type`、`v` 不支援、item 缺欄位、型別錯誤、`state` 非法、空 `items`、混有非法 item、非 JSON）。驗收：測試中每個樣本皆 reject 且原因類別與 manifest 相符。
- [x] 1.4 實作超大行（上限加一）與恰為上限的行之程式產生邏輯，加入 manifest。驗收：上限加一 reject（`oversize`）、恰為上限 accept。
- [x] 1.5 補上 schema 無法表達的額外檢查（順序、UTF-8、大小）於參考驗證測試。驗收：snapshot 升冪樣本與 items 降冪樣本各自被判 reject。

## 2. 參考驗證與 fail-then-pass 證據

- [x] 2.1 實作參考驗證測試，讀取 manifest 對所有 fixtures 驗證，並檢查 fixtures 目錄與 manifest 一一對應。驗收：`python3 -m unittest discover -s protocol/tests`全綠；故意刪一個 manifest 條目時測試失敗。
- [x] 2.2 對每條規則記錄 fail-then-pass：先放入樣本使測試失敗，再修 schema 使其通過，將兩次指令與輸出摘要寫入 `protocol/README.md`。驗收：README 含至少三條規則（缺欄位、空 items、`state` 非法）的失敗與通過輸出。
- [x] 2.3 撰寫覆蓋清單測試：manifest 缺少任一必要類別時失敗。驗收：移除某類別樣本後測試失敗，補回後通過。

## 3. 兩端接入文件與收尾

- [x] 3.1 在 `protocol/README.md` 寫明 Rust（發送端驗證輸出）與 Swift（接收端 Codable＋手寫檢查）如何載入 manifest、對應原因類別、處理單行失敗。驗收：文件逐條對應 `message-protocol` spec 的非法訊息處理期望，供下游 change 引用。
- [x] 3.2 為每個【待確認】項目在 README 列出「目前採用的暫定值」與其影響的 fixture 名稱，使使用者確認後可快速翻轉。驗收：README 的待確認清單與 spec／design 的標記逐項一致。
- [x] 3.3 執行 `openspec validate message-contract --strict` 與參考測試全套，將結果貼入變更說明。驗收：兩者皆通過，指令與輸出可重現。
