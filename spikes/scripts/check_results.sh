#!/bin/bash
# RESULTS.md 格式與決定完整性檢查。用法：
#   spikes/check_results.sh [RESULTS.md] [--root DIR] [--require-decisions]
# 退出碼：0 通過、1 檢查失敗、2 用法錯誤。
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ $# -eq 0 ] || [[ "$1" == --* ]]; then set -- "$DIR/../RESULTS.md" "$@"; fi
exec python3 -I "$DIR/check_results.py" "$@"
