#!/bin/bash
# 腳本的 fail-then-pass 驗證：對人為構造的壞資料必須回報失敗(紅)，對正常資料必須通過(綠)。
# 用法：cd spikes && tests/run_script_tests.sh      （不啟動任何實驗程式、不建立視窗）
cd "$(dirname "$0")/.." || exit 2
FX=tests/fixtures; A="python3 -I scripts/analyze.py"; CR=scripts/check_results.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; failn=0
expect() { # expect <red|green> <label> <cmd...>
  want=$1; label=$2; shift 2
  out=$("$@" 2>&1); rc=$?
  if [ "$want" = green ] && [ $rc -eq 0 ]; then r="GREEN ok"; pass=$((pass+1))
  elif [ "$want" = red ] && [ $rc -eq 1 ]; then r="RED   ok (rc=1 as expected: $(echo "$out" | grep -E 'problem:|ERROR:' | head -1 | cut -c1-110))"; pass=$((pass+1))
  else r="UNEXPECTED rc=$rc (wanted $want)"; failn=$((failn+1)); echo "$out" | tail -5; fi
  printf '%-48s %s\n' "$label" "$r"
}
mut() { # mut <name> <python-regex-old> <new>  : 由 RESULTS_good.md 產生壞樣本
  python3 -I - "$FX/RESULTS_good.md" "$TMP/$1.md" "$2" "$3" <<'PY'
import re,sys
s=open(sys.argv[1],encoding="utf-8").read()
n=re.sub(sys.argv[3],sys.argv[4],s,count=1,flags=re.S)
assert n!=s,"mutation did not apply: "+sys.argv[3]
open(sys.argv[2],"w",encoding="utf-8").write(n)
PY
}

echo "== check_results.sh =="
expect green "results: good sample (+decisions)" $CR $FX/RESULTS_good.md --root $FX --require-decisions
mut no_date  '(### S1-01.*?)- 日期: 2026-10-24' '\1- 日期: '                ; expect red "results: missing date"            $CR $TMP/no_date.md --root $FX
mut no_macos '(### S1-01.*?)- macOS: 26.5.1' '\1- macOS: '                   ; expect red "results: missing macOS"           $CR $TMP/no_macos.md --root $FX
mut no_ev    '(### S1-01.*?)- 證據: evidence/a.png' '\1- 證據: evidence/nope.png'; expect red "results: evidence path missing"  $CR $TMP/no_ev.md --root $FX
mut no_cause '(### S1-02.*?)- 原因類別: 平台限制' '\1- 原因類別: -'           ; expect red "results: FAIL without cause"      $CR $TMP/no_cause.md --root $FX
mut no_basis '(### S1-02.*?)- 佐證: [^\n]*' '\1- 佐證: -'                    ; expect red "results: 平台限制 without 佐證"    $CR $TMP/no_basis.md --root $FX
mut no_rerun '(### S1-03.*?)- 重跑: S1-04' '\1- 重跑: -'                      ; expect red "results: 實作錯誤 without rerun"   $CR $TMP/no_rerun.md --root $FX
mut bad_res  '(### S1-01.*?)- 結果: PASS' '\1- 結果: 通過'                   ; expect red "results: invalid 結果 value"       $CR $TMP/bad_res.md --root $FX
mut skip_why '(### S1-05.*?)- 觀察: 未執行：無外接螢幕' '\1- 觀察: 沒做'         ; expect red "results: 未執行 without reason"    $CR $TMP/skip_why.md --root $FX
mut d1_impl  '(### D1\n- 依據: )S1-02' '\1S1-03'                              ; expect red "decisions: D1 cites 實作錯誤 cell" $CR $TMP/d1_impl.md --root $FX --require-decisions
mut d1_miss  '(### D1\n- 依據: )S1-02' '\1S1-99'                              ; expect red "decisions: D1 cites missing cell"  $CR $TMP/d1_miss.md --root $FX --require-decisions
mut d1_skip  '(### D1\n- 依據: )S1-02' '\1S1-05'                              ; expect red "decisions: D1 cites 未執行 cell"   $CR $TMP/d1_skip.md --root $FX --require-decisions
mut d3_nums  '- B: CPU=2.0 RSS=39000 WindowServer=3.9' '- B: CPU=2.0'           ; expect red "decisions: D3 B missing numbers"   $CR $TMP/d3_nums.md --root $FX --require-decisions
mut d2_ss    'level=floating; canJoinAllApplications=off' 'level=screenSaver; x=1'; expect red "decisions: D2 uses screenSaver"    $CR $TMP/d2_ss.md --root $FX --require-decisions
mut d2_fail  '(### D2\n- 依據: )S1-01' '\1S1-02'                              ; expect red "decisions: D2 cites FAIL cell"     $CR $TMP/d2_fail.md --root $FX --require-decisions
expect red   "results: shipped template + decisions" $CR scripts/../RESULTS.md --require-decisions
expect green "results: shipped template (cells only)" $CR scripts/../RESULTS.md

echo "== analyze.py s1config =="
expect green "s1config --log good"            $A s1config --log $FX/s1_good.events
expect red   "s1config --log wrong level.raw" $A s1config --log $FX/s1_bad_level.events
expect red   "s1config --log wrong behavior"  $A s1config --log $FX/s1_bad_behavior.events

echo "== analyze.py focus / typing (S2 judge) =="
expect green "focus: normal"                 $A focus --log $FX/focus_good.events --target-bundle com.apple.TextEdit --typed-file $FX/typing_good.txt
expect red   "focus: frontmost changed"      $A focus --log $FX/focus_bad_frontmost.events --target-bundle com.apple.TextEdit
expect red   "focus: self didActivate"       $A focus --log $FX/focus_bad_selfactivate.events --target-bundle com.apple.TextEdit
expect red   "typing: missing char"          $A typing --file $FX/typing_bad.txt
expect red   "focus: normal log + bad typing" $A focus --log $FX/focus_good.events --target-bundle com.apple.TextEdit --typed-file $FX/typing_bad.txt

echo "== analyze.py s3 =="
expect green "s3: normal (max 15ms)"          $A s3 --log $FX/s3_good.events --require-slider
expect red   "s3: 150ms error"                $A s3 --log $FX/s3_bad_error150.events
expect red   "s3: missed refills"             $A s3 --log $FX/s3_bad_missed.events
expect red   "s3: negative tail gap (blank)"  $A s3 --log $FX/s3_bad_blank.events
expect red   "s3: menu open < 60s"            $A s3 --log $FX/s3_bad_shortmenu.events

echo "== analyze.py csv =="
gen() { awk -v n="$2" -v step="$3" -v bad="$4" 'BEGIN{print "epoch,iso,app_cpu_pct,app_rss_kb,ws_cpu_pct"; for(i=0;i<n;i++){ c=(bad=="nan"&&i==3)?"x":sprintf("%.2f",2+(i%5)*0.1); printf "%.3f,t,%s,%d,%.2f\n",1000+i*step,c,40000+i*10,3+(i%3)*0.2}}' > "$1"; }
gen $TMP/good.csv 360 10 ok;  expect green "csv: 360 rows @10s"            $A csv --file $TMP/good.csv
gen $TMP/few.csv 100 10 ok;   expect red   "csv: too few rows (100<360)"   $A csv --file $TMP/few.csv
gen $TMP/slow.csv 360 25 ok;  expect red   "csv: spacing 25s vs 10s"       $A csv --file $TMP/slow.csv
gen $TMP/nan.csv 360 10 nan;  expect red   "csv: non-numeric cell"         $A csv --file $TMP/nan.csv
echo "== analyze.py frames / position =="
expect green "frames: has data"               $A frames --log $FX/frames_good.events
expect red   "frames: no frames events"       $A frames --log $FX/frames_bad.events
expect green "position: restored == saved"    $A position --before $FX/pos_before.events --after $FX/pos_after_good.events
expect red   "position: off by 59.5px"        $A position --before $FX/pos_before.events --after $FX/pos_after_bad.events

echo "== arg validation (no window) =="
if [ -x .build/debug/spike-s1 ]; then
  expect green "s1 dry-run x8 combos match expected" $A s1config --dry-run-all --bin .build/debug/spike-s1
  # 紅：假的 dry-run 程式永遠回報 level.raw=3（statusBar 應為 25），判定器必須抓到
  cat > $TMP/fake-s1 <<'FAKE'
#!/bin/bash
while [ $# -gt 0 ]; do [ "$1" = "--log-file" ] && LF="$2"; shift; done
printf '2026-10-24T10:00:00.000+08:00\tconfig.expected\tlevel.raw=3 behavior=canJoinAllSpaces,fullScreenAuxiliary,ignoresCycle,stationary hidesOnDeactivate=false canBecomeKey=false canBecomeMain=false\n2026-10-24T10:00:00.001+08:00\tdryrun.done\twindow-created=false\n' > "$LF"
FAKE
  chmod +x $TMP/fake-s1
  expect red "s1 dry-run-all vs a wrong fake binary" $A s1config --dry-run-all --bin $TMP/fake-s1
  out=$(.build/debug/spike-s1 --dry-run --level screenSaver 2>&1); rc=$?
  [ $rc -eq 2 ] && { echo "RED   ok  spike-s1 rejects --level screenSaver (rc=2)"; pass=$((pass+1)); } || { echo "UNEXPECTED rc=$rc"; failn=$((failn+1)); }
else echo "(skip: run 'swift build' first for dry-run checks)"; fi
echo; echo "passed=$pass unexpected=$failn"; [ $failn -eq 0 ]
