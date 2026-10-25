#!/bin/sh
# build 前呼叫：確保沒有舊的 FastBullTicker／ticker-connect 還在跑，並清掉可能過期的 helper.pid。
# 先 SIGTERM（App 會優雅結束並帶走 helper），最多等 15 秒；仍在的才 SIGKILL。
# 會停掉本機上「所有」FastBullTicker（不分哪個資料夾 build 的）：這正是目的，避免新舊實例互搶 helper.pid。
pids() { pgrep -x FastBullTicker; pgrep -x ticker-connect; }
[ -z "$(pids)" ] && { rm -f "$HOME/Library/Application Support/FastBullTicker/helper.pid"; echo "stop-old: 沒有舊的實例"; exit 0; }
echo "stop-old: 停止舊實例：$(pids | tr '\n' ' ')"
pkill -x FastBullTicker; pkill -x ticker-connect
i=0; while [ $i -lt 15 ] && [ -n "$(pids)" ]; do sleep 1; i=$((i+1)); done
if [ -n "$(pids)" ]; then echo "stop-old: 仍在，強制結束：$(pids | tr '\n' ' ')"; pkill -9 -x FastBullTicker; pkill -9 -x ticker-connect; sleep 1; fi
rm -f "$HOME/Library/Application Support/FastBullTicker/helper.pid"
[ -z "$(pids)" ] && echo "stop-old: 已清乾淨" || { echo "stop-old: 失敗，仍有殘留"; exit 1; }
