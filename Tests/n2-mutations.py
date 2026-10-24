#!/usr/bin/env python3
"""ticker-navigation-link 第 N2 段（4.1、5.1、6.1）的 mutation 證據：
逐一破壞實作 → 跑 swift test（應紅，列出失敗的測試）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/n2-mutations.py"""
import subprocess, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
C = ROOT / "Sources/FastBullTickerCore"
A = ROOT / "Sources/FastBullTickerApp"
TS, LY = C / "TickerScheduler.swift", C / "Layout.swift"
LP, HT, PI, PH = A / "LinkPolicy.swift", A / "HitTesting.swift", A / "PositionIndicator.swift", A / "PointerHover.swift"
GUARD = ROOT / "Tests/FastBullTickerAppTests/LinkOpenerGuardTests.swift"
M = [
 ("S1 seek 改動某個 tapeX", TS, "baseOffset = target.tapeX - config.speed * tapeTime\n",
  "baseOffset = target.tapeX - config.speed * tapeTime\n        if !placed.isEmpty { placed[placed.count - 1].tapeX += 1 }\n"),
 ("S2 seek 對齊偏 1pt", TS, "baseOffset = target.tapeX - config.speed * tapeTime\n", "baseOffset = target.tapeX - config.speed * tapeTime + 1\n"),
 ("S3 指標停留不再凍結時間", TS, "guard !isHidden, !isPointerInside else { return }", "guard !isHidden else { return }"),
 ("S4 凍結（隱藏／指標）期間仍消耗保持", TS, "guard !isHidden, !isPointerInside else { return }",
  "if isHidden || isPointerInside { holdRemaining = max(0, holdRemaining - delta); return }"),
 ("S5 再次 seek 累加保持而非重設", TS, "holdRemaining = config.seekHoldSeconds", "holdRemaining += config.seekHoldSeconds"),
 ("S6 強制排入少了 gap", TS, "(tailEnd ?? 0) + config.gap", "(tailEnd ?? 0)"),
 ("S7 rebase 不保留最近 N 則", TS, "            keepFrom = min(keepFrom, max(0, placed.count - config.retainPlacedCount))   // 另外保留最近 N 則供 `<` 回溯\n", ""),
 ("S8 閱讀位置右緣改成 >= inset", TS, "> config.readingInset {", ">= config.readingInset {"),
 ("S9 即時批次總數不含佇列中尚未排入者", TS, "return openLivePlaced + liveQueue.count", "return openLivePlaced"),
 ("S10 清單第一則按 < 不停住", TS, "if r.listIndex <= 1 { return .atListStart }", ""),
 ("S11 隱藏中 seek 仍動作", TS, "guard !isHidden else { return .hidden }", ""),
 ("S12 setPointerInside 不先推進時鐘", TS, "        advance()\n        isPointerInside = inside", "        isPointerInside = inside"),
 ("S13 強制排入的訊息不算新序號（seq 重複）", TS, "        nextSeq += 1\n        placed.append(p)", "        placed.append(p)"),
 ("L1 連結欄位未從截斷預算扣除", LY, "let budget = maxWidth - slot", "let budget = maxWidth"),
 ("L2 沒有 url 也保留欄位", LY, "let slot = (item.url != nil && linkSlotWidth > 0) ? linkSlotWidth : 0", "let slot = linkSlotWidth"),
 ("P1 LinkPolicy 放行任何 scheme（含 javascript:）", LP, 'scheme == "http" || scheme == "https",', "true,"),
 ("P2 LinkPolicy 放行 userinfo", LP, "c.user == nil, c.password == nil", "true"),
 ("P3 LinkPolicy 不限制長度", LP, "bytes.count <= maxBytes, ", ""),
 ("P4 命中測試：按鈕不再優先", HT, "if g.strip.stripRange(panelWidth: w).contains(x) {", "if false {"),
 ("P5 命中測試：忽略 hitSlop", HT, "(right - g.linkSlotWidth - g.hitSlop)..<(right + g.hitSlop)", "(right - g.linkSlotWidth)..<right"),
 ("P6 命中測試：標籤內的迴紋針仍有效", HT, "guard x >= g.labelWidth else { return .drag }", ""),
 ("P7 (n/N) 格式錯誤", PI, '"(" + String(index)', '"[" + String(index)'),
 ("P8 PointerHover：隱藏面板仍算在內", PH, "guard panelVisible, !clickThrough else", "guard !clickThrough else"),
 ("P9 開啟失敗時重試", LP, "return opener.open(openable) ? .opened : .openerFailed",
  "return (opener.open(openable) || opener.open(openable)) ? .opened : .openerFailed"),
 ("P10 守衛放寬：任何 Workspace* 檔皆允許", GUARD, 'n.hasPrefix("Workspace") && n.hasSuffix("Opener.swift")', 'n.hasPrefix("Workspace")'),
]

def run():
    r = subprocess.run(["swift", "test"], cwd=ROOT, capture_output=True, text=True, timeout=900)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
    summ = [l.strip() for l in out.splitlines() if "Test run with" in l or "error:" in l][:2]
    return r.returncode, fails, summ

for name, path, old, new in M:
    orig = path.read_text(encoding="utf-8")
    assert orig.count(old) == 1, f"{name}: 要破壞的程式碼出現 {orig.count(old)} 次"
    path.write_text(orig.replace(old, new, 1), encoding="utf-8")
    try:
        rc, fails, summ = run()
    finally:
        path.write_text(orig, encoding="utf-8")
    verdict = "紅（偵測到）" if rc != 0 else "!!! 仍然綠（測試沒抓到）"
    print(f"[{name}]\n  破壞後 rc={rc} {verdict}\n  失敗測試={fails}\n  {summ}", flush=True)
rc, fails, summ = run()
print(f"[還原後] rc={rc} {summ}")
