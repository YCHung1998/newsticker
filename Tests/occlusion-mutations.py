#!/usr/bin/env python3
"""遮蔽防抖的 mutation 證據：逐一破壞實作 → 跑 Occlusion 測試（應紅）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/occlusion-mutations.py"""
import subprocess, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
S = ROOT / "Sources/FastBullTickerApp"
OD, SC = S / "OcclusionDebouncer.swift", S / "ShellConfig.swift"
M = [
 ("O1 沒有防抖（延遲 0，等同立即凍結）", OD, "cancelPending = schedule(confirmDelay) {", "cancelPending = schedule(0) {"),
 ("O2 變回可見不取消等待中的凍結", OD, "cancelPending?(); cancelPending = nil; isPending = false; generation += 1\n", ""),
 ("O3 凍結後變回可見不解凍", OD, "                isOccluded = false\n                onDecision(.thawed)\n", ""),
 ("O4 重複不可見通知重設計時", OD, "} else if !isPending && !isOccluded {", "} else if !isOccluded {"),
 ("O5 集中設定延遲改 0", SC, "occludedConfirmDelay: 1.0", "occludedConfirmDelay: 0.0"),
]

def run():
    r = subprocess.run(["swift", "test", "--filter", "Occlusion"], cwd=ROOT, capture_output=True, text=True, timeout=300)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
    summ = [l for l in out.splitlines() if "Test run with" in l or "error:" in l][:2]
    return r.returncode, fails, summ

for name, path, old, new in M:
    orig = path.read_text(encoding="utf-8")
    assert old in orig, f"{name}: 找不到要破壞的程式碼"
    path.write_text(orig.replace(old, new, 1), encoding="utf-8")
    try:
        rc, fails, summ = run()
    finally:
        path.write_text(orig, encoding="utf-8")
    print(f"[{name}]\n  破壞後 rc={rc}（非 0 = 紅） 失敗測試={fails}\n  {summ}", flush=True)
rc, fails, summ = run()
print(f"[還原後] rc={rc} {summ}")
