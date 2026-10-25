## 1. 協定（先 fail 後 pass）

- [x] 1.1 `protocol/schema/item.schema.json` 加選填 `title`（非空字串）、`important`（布林）；新增合法／非法 fixtures 與 manifest（含 `title:""`、`important:null`），把 `item-extra-field` 改用 `priority` 之類未定義欄位
- [x] 1.2 參考驗證器 `python3 -m unittest discover -s protocol/tests` 先紅後綠，附輸出

## 2. Rust helper

- [x] 2.1 `model.rs`／`protocol.rs`／emitter 支援 `title`、`important`（缺少時不輸出），fastbull 輸出逐位元組不變（以既有測試證明）
- [x] 2.2 審查並整合 `exp/jin10-cold-start` 的 `jin10.rs`、`sources.rs`、`lib.rs`、fixture、測試；先確認其測試是否真的綠
- [x] 2.3 加入 `【標題】` 拆分、`important` 轉換，並補測試（有標題、只有標題、重要、廣告、鎖定、壞時間）
- [x] 2.4 `cargo test`、`cargo build` 0 warning、`--list-sources` 含 `jin10`
- [x] 2.5 實測真站一次（低頻）：stdout 有 snapshot、每行通過協定驗證、時間與網站畫面對得上

## 3. Swift

- [x] 3.1 Core 解碼 `title`／`important`（含非法值），共用 fixtures 契約測試
- [x] 3.2 佈局加標題粗體區段與重要色區段，無 `title` 時字串逐字不變
- [x] 3.3 `ItemBitmap` 繪製與量測一致、離屏 PNG 證據
- [x] 3.4 `swift test` 全綠（已知偶發失敗如實記錄）

## 4. 整合與文件

- [x] 4.1 以 `NEWSTICKER_SOURCE=jin10` 啟動 App，看日誌 `feed: snapshot`、離屏截圖
- [x] 4.2 更新 README 快速開始（如何切到金十）與 `docs/ADDING_A_SOURCE.md` 的 item 欄位表
- [x] 4.3 `openspec validate --all --strict` 通過
