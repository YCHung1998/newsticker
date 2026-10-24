#!/bin/sh
# app-shell task 1.1 的重現腳本：從專案根目錄執行 `sh Tests/app-packaging-check.sh`。
# 不連網、不需 sudo／任何系統權限。結束前會重建乾淨的 bundle。
set -u
cd "$(dirname "$0")/.." || exit 2
APP=build/FastBullTicker.app
H=$APP/Contents/MacOS/ticker-connect
fail=0
step() { printf '\n== %s\n' "$*"; }
expect_ok()   { desc=$1; shift; if "$@" >/dev/null 2>&1; then echo "PASS: $desc"; else echo "FAIL: $desc"; fail=1; fi; }
expect_fail() { desc=$1; shift; out=$("$@" 2>&1); if [ $? -eq 0 ]; then echo "FAIL: ${desc}（預期失敗卻成功）"; fail=1; else echo "PASS: ${desc}（如預期失敗）"; echo "  codesign 輸出: $(echo "$out" | head -2 | tr '\n' ' ')"; fi; }

step "make helper app sign"
make helper app sign >/dev/null 2>&1 && echo "PASS: make helper app sign" || { echo "FAIL: make helper app sign"; exit 1; }

step "bundle 內容"
find $APP -type f | sort
expect_ok "主執行檔存在" test -x $APP/Contents/MacOS/FastBullTicker
expect_ok "helper 存在且可執行" test -x $H

step "Info.plist"
plutil -p $APP/Contents/Info.plist | grep -E 'LSUIElement|LSMinimumSystemVersion|CFBundleExecutable'
plutil -p $APP/Contents/Info.plist | grep -q 'LSUIElement" => true' && echo "PASS: LSUIElement => true" || { echo "FAIL: LSUIElement"; fail=1; }

step "codesign 驗證（簽名後）"
expect_ok "codesign --verify --strict -vv bundle" codesign --verify --strict -vv $APP
expect_ok "codesign --verify --strict -vv helper" codesign --verify --strict -vv $H

step "Makefile 不得出現遞迴簽名旗標"
if grep -n -- "--deep" Makefile; then echo "FAIL: 發現"; fail=1; else echo "PASS: grep 無結果"; fi

step "fail-then-pass：改 helper 一個位元組"
printf '\377' | dd of=$H bs=1 seek=20000 count=1 conv=notrunc 2>/dev/null
expect_fail "改位元組後 codesign --verify 失敗（紅）" codesign --verify --strict -vv $H
make sign >/dev/null 2>&1
expect_ok "重新 make sign 後 verify 通過（綠）" codesign --verify --strict -vv $APP

step "還原乾淨 bundle"
make app sign >/dev/null 2>&1 && echo "PASS: 重建完成"

step "helper 在 bundle 內可啟動（不連網：stdin EOF 應立即結束）"
start=$(date +%s)
"$H" </dev/null >/dev/null 2>&1; rc=$?
end=$(date +%s)
echo "exit code=$rc elapsed=$((end-start))s"
[ $rc -eq 0 ] && [ $((end-start)) -le 3 ] && echo "PASS: EOF 後立即結束" || { echo "FAIL"; fail=1; }

step "主執行檔可啟動（空殼）"
$APP/Contents/MacOS/FastBullTicker && echo "PASS" || { echo "FAIL"; fail=1; }

echo; [ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
