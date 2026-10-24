#!/usr/bin/env python3
"""nav-layout-tweaks 的 mutation 證據：逐一破壞實作 → 跑 swift test（應紅，列出失敗的測試）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/t1-mutations.py [名稱前綴…]    完整輸出存於 Tests/evidence/t1-mutations.log"""
import subprocess, re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
A = ROOT / "Sources/FastBullTickerApp"
CS, HT, TV, GL = A/"ControlStripLayout.swift", A/"HitTesting.swift", A/"TickerView.swift", A/"ControlStripGlyphs.swift"
SCH = ROOT / "Sources/FastBullTickerCore/TickerScheduler.swift"
# (名稱, 檔案, 舊字串, 新字串, 預期出現次數)
M = [
 ("T1 seek 停留預設值退回 8 秒", SCH, "public var seekHoldSeconds: Double = 1", "public var seekHoldSeconds: Double = 8", 1),
 ("T2 可視寬度公式忘了扣控制列左側占用寬", CS, "max(0, panelWidth - leftInset - controlStripWidth)", "max(0, panelWidth - controlStripWidth)", 1),
 ("T3 控制列範圍不隨標籤寬（退回貼面板左緣）", CS, "public func stripRange(leftInset: Double) -> Range<Double> { leftInset..<(leftInset + controlStripWidth) }", "public func stripRange(leftInset: Double) -> Range<Double> { 0..<controlStripWidth }", 1),
 ("T4 `>` 命中範圍少 4pt", CS, "(leftInset + buttonWidth + indicatorWidth)..<(leftInset + controlStripWidth)", "(leftInset + buttonWidth + indicatorWidth)..<(leftInset + controlStripWidth - 4)", 1),
 ("T5 迴紋針命中區忘了加控制列寬（沿用舊的標籤右緣）", HT, "let right = tapeLeft + item.visualLeft + item.width", "let right = g.labelWidth + item.visualLeft + item.width", 1),
 ("T6 `showLabel` 切換不更新命中幾何", TV, "router.geometry = config.makeHitGeometry(showLabel: new.showLabel)", "", 1),
 ("T7 帶子 clip 左緣寫死標籤寬（showLabel=false 座標錯）", TV, "x: st.tapeLeft(leftInset: left), y: 0, width: CGFloat(config.tapeViewport(showLabel: showLabel))", "x: st.tapeLeft(leftInset: 150), y: 0, width: CGFloat(config.tapeViewport(showLabel: showLabel))", 1),
 ("T8 控制列底不延伸到標籤斜切下方", TV, "x: lw - slant, y: 0, width: CGFloat(st.controlStripWidth) + slant", "x: lw, y: 0, width: CGFloat(st.controlStripWidth)", 1),
 ("T9 chevron 垂直偏離中心 3pt（對齊量測要咬到）", GL, "let cx = bounds.midX, cy = bounds.midY", "let cx = bounds.midX, cy = bounds.midY - 3", 1),
 ("T10 位置指示不依墨跡外框置中（以基線置於中線）", GL, "y: size.height / 2 - ink.midY", "y: size.height / 2", 1),
]

def run():
    r = subprocess.run(["swift", "test"], cwd=ROOT, capture_output=True, text=True, timeout=900)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
    summ = [l.strip() for l in out.splitlines() if "Test run with" in l or "error:" in l][:2]
    return r.returncode, fails, summ

survived = 0
for name, path, old, new, cnt in M:
    if sys.argv[1:] and not any(name.startswith(a) for a in sys.argv[1:]): continue
    orig = path.read_text(encoding="utf-8")
    assert orig.count(old) == cnt, f"{name}: 要破壞的程式碼出現 {orig.count(old)} 次（預期 {cnt}）"
    path.write_text(orig.replace(old, new), encoding="utf-8")
    try:
        rc, fails, summ = run()
    finally:
        path.write_text(orig, encoding="utf-8")
    verdict = "紅（偵測到）" if rc != 0 else "!!! 仍然綠（測試沒抓到）"
    survived += rc == 0
    print(f"[{name}]\n  破壞後 rc={rc} {verdict}\n  失敗測試={fails}\n  {summ}", flush=True)
rc, fails, summ = run()
print(f"\n還原後 rc={rc} {summ}  存活的 mutation 數={survived}", flush=True)
