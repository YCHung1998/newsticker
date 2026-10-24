#!/bin/bash
# S4 取樣：只用 ps（不需 sudo、不用 powermetrics）。每 INTERVAL 秒寫一列 CSV：
#   epoch,iso,app_cpu_pct,app_rss_kb,ws_cpu_pct
# CPU% = 區間內 CPU time 增量 / 實際經過秒數 * 100（由 ps 的累計 CPU time 差算出，避免 ps %cpu 的衰減平均）。
# 用法：sample_proc.sh --pid PID --out FILE [--interval 10] [--duration 3660]
set -u
PID=""; OUT=""; INTERVAL=10; DURATION=3660
while [ $# -gt 0 ]; do
  case "$1" in
    --pid) PID="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --interval) INTERVAL="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done
[ -n "$PID" ] && [ -n "$OUT" ] || { echo "usage: $0 --pid PID --out FILE [--interval S] [--duration S]" >&2; exit 2; }
WS=$(pgrep -x WindowServer | head -1)
[ -n "$WS" ] || { echo "WindowServer pid not found" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
echo "epoch,iso,app_cpu_pct,app_rss_kb,ws_cpu_pct" > "$OUT"

# ps time 欄位 "[H:]MM:SS.cc" 或 "MMMM:SS.cc" -> 秒
snap() { # pid -> "cpuSeconds rssKB"
  ps -o time=,rss= -p "$1" 2>/dev/null | awk '{n=split($1,a,":"); s=0; for(i=1;i<=n;i++) s=s*60+a[i]; printf "%.2f %d", s, $2}'
}
now_s() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
prev_app=$(snap "$PID"); prev_ws=$(snap "$WS"); prev_t=$(now_s)
[ -n "$prev_app" ] || { echo "pid $PID not found" >&2; exit 1; }
rows=$((DURATION / INTERVAL)); i=0
while [ "$i" -lt "$rows" ]; do
  sleep "$INTERVAL"
  now=$(now_s); app=$(snap "$PID"); ws=$(snap "$WS")
  [ -n "$app" ] || { echo "target pid $PID exited after $i rows" >&2; exit 0; }
  echo "$prev_app $app $prev_ws $ws $prev_t $now" | awk -v iso="$(date +%Y-%m-%dT%H:%M:%S%z)" '{
      dt=$10-$9; if (dt<=0) dt=1
      printf "%.3f,%s,%.2f,%d,%.2f\n", $10, iso, ($3-$1)/dt*100, $4, ($7-$5)/dt*100 }' >> "$OUT"
  prev_app=$app; prev_ws=$ws; prev_t=$now; i=$((i+1))
done
