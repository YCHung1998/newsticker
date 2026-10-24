#!/bin/bash
# 離線示範用假 helper：輸出符合協定 v1 的 JSON-lines，不連網。
#   export FASTBULL_TICKER_HELPER="$PWD/scripts/demo-helper.sh"; open/執行 build/FastBullTicker.app
# 行為：啟動立即輸出 snapshot（12 則，新到舊）；之後每 8 秒一則 items；每 25 秒一則 status；stdin EOF 即結束。
# 連結：多數訊息帶 `url`（https://example.com/demo/<id>，不屬於任何正式站）；每三則故意有一則不帶，
# 用來驗證「無連結不顯示迴紋針」。
# 可用環境變數調整（測試用）：DEMO_ITEM_INTERVAL（預設 8）、DEMO_STATUS_INTERVAL（預設 25）。
ITEM_EVERY=${DEMO_ITEM_INTERVAL:-8}
STATUS_EVERY=${DEMO_STATUS_INTERVAL:-25}

TEXTS=(
  "美股盤前：道指期貨小幅上揚，納指期貨持平"
  "Fed 官員表示仍需觀察通膨數據，不排除年內再度降息"
  "黃金突破 4,000 美元/盎司，創歷史新高"
  "日經指數收盤上漲，半導體類股領漲"
  "歐元區 PMI 優於預期，歐元兌美元走高"
  "WTI 原油上漲 1.2%，報每桶 78.4 美元"
  "人民幣中間價調升 35 點，報 7.1022"
  "比特幣站上 11 萬美元，24 小時內上漲 3.5%"
  "央行公開市場操作淨投放 1,500 億元"
  "美國 10 年期公債殖利率降至 4.05%"
  "台股加權指數收盤上漲 0.8%，成交量放大"
  "英國 9 月 CPI 年增 3.8%，符合市場預期"
)
N=${#TEXTS[@]}
now_ms() { echo $(( $(date +%s) * 1000 )); }

emit_item() { # id published_at_ms text [with_url=1]
  local url=""
  [ "${4:-1}" = "1" ] && url=",\"url\":\"https://example.com/demo/$1\""
  printf '{"source":"demo","id":"%s","published_at_ms":%s,"text":"%s"%s}' "$1" "$2" "$3" "$url"
}

# snapshot：新到舊，每則相隔 3 分鐘。
NOW=$(now_ms)
SNAP=""
for ((i = 0; i < N; i++)); do
  [ -n "$SNAP" ] && SNAP="$SNAP,"
  SNAP="$SNAP$(emit_item "$((9000 - i))" "$((NOW - 180000 * (i + 1)))" "${TEXTS[$i]}" "$((i % 3 == 2 ? 0 : 1))")"
done
printf '{"v":1,"type":"snapshot","items":[%s]}\n' "$SNAP"
printf '{"v":1,"type":"status","source":"demo","state":"ok","message":"demo helper started"}\n'

# stdin EOF（App 結束或 shutdown 關閉 stdin）→ 背景讀取者通知主迴圈離開，不留孤兒。
# （bash 3.2 的 read -t 逾時與 EOF 回傳碼相同，所以改用背景讀取者。）
trap 'exit 0' TERM
{ cat > /dev/null; kill -TERM $$ 2>/dev/null; } <&0 &

seq=0; t=0
while true; do
  sleep 1
  t=$((t + 1))
  if [ $((t % ITEM_EVERY)) -eq 0 ]; then
    seq=$((seq + 1))
    printf '{"v":1,"type":"items","items":[%s]}\n' "$(emit_item "$((9100 + seq))" "$(now_ms)" "最新快訊 #${seq}：${TEXTS[$((seq % N))]}" "$((seq % 3 == 0 ? 0 : 1))")"
  fi
  if [ $((t % STATUS_EVERY)) -eq 0 ]; then
    printf '{"v":1,"type":"status","source":"demo","state":"ok","message":"demo heartbeat"}\n'
  fi
done
