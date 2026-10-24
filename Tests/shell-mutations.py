#!/usr/bin/env python3
"""app-shell 3.1–4.2 的 mutation 證據：逐一破壞實作 → 跑對應測試（應紅）→ 還原 → 最後整體確認回綠。
用法（專案根目錄）：python3 Tests/shell-mutations.py [mutation 名稱片段...]"""
import subprocess, sys, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
S = ROOT / "Sources/FastBullTickerApp"
P, C, TV, SM, TD, AC, AD = (S / n for n in ["Persistence.swift", "ShellConfig.swift", "TickerView.swift", "StatusMenu.swift",
                                            "TickerDriver.swift", "AppCoordinator.swift", "AppDelegate.swift"])

M = [
 ("S1 夾制函式不夾制 (3.1)", P, "f.origin.x = frame.width <= visible.width ? min(max(frame.minX, visible.minX), visible.maxX - frame.width) : visible.minX", "f.origin.x = frame.minX", "PersistenceClamp"),
 ("S2 debounce 不合併 (3.1)", P, "        timer?.cancel()\n        timer = clock.schedule(after: delay", "        timer = clock.schedule(after: delay", "PersistenceDebounce"),
 ("S3 透明度下限改 0 (3.2/3.3)", C, "alphaRange: 0.3...1.0", "alphaRange: 0.0...1.0", "shellConfigClampsAlphaToFloor|StatusMenuTests|alphaValueDrives"),
 ("S4 styleMask 加 hudWindow (3.2)", TV, "styleMask: [.borderless, .nonactivatingPanel]", "styleMask: [.borderless, .nonactivatingPanel, .hudWindow]", "PanelShellTests"),
 ("S5 canBecomeKey 回 true (3.2)", TV, "public override var canBecomeKey: Bool { false }", "public override var canBecomeKey: Bool { true }", "PanelShellTests"),
 ("S6 level 改 .screenSaver (3.2)", C, "level: .statusBar,", "level: .screenSaver,", "levelAndBehavior"),
 ("S7 隱藏不改選單標題 (3.3)", SM, "        hideItem.title = Self.hideTitle(hidden: h)\n", "", "hideTogglesTitle"),
 ("S8 點穿狀態不記錄 (3.3)", SM, "        clickThrough = c\n", "", "clickThroughIsNeverPersisted"),
 ("S9 隱藏時 Scheduler 不凍結 (4.1)", TD, "            scheduler.hide(); renderer.setPaused(true)", "            renderer.setPaused(true)", "hiddenFreezesAndResumes"),
 ("S10 rebase 不通知 renderer (4.1)", TD, "            renderer.applyRebase(delta: delta)\n", "", "rebaseKeepsEveryScreenPosition"),
 ("S11 TrackModel.rebase 空實作 (4.1)", TD, "for i in entries.indices { entries[i].tapeX -= delta }", "", "TrackModelTests|rebaseKeepsEveryScreenPosition"),
 ("S12 紋理不切塊 (4.1)", TD, "let w = min(limit, rest)", "let w = rest", "TilingTests"),
 ("S13 不清除已捲出的 layer (4.1)", TD, "let gone = entries.filter { $0.tapeX + $0.width < offset - margin }.map(\\.seq)", "let gone: [Int] = []", "prunesScrolledOut|TrackModelTests"),
 ("S14 Coordinator 不轉給 driver (4.2)", AC, "            driver.receive(m)\n", "", "AppSmoke"),
 ("S15 呼叫 App 啟用 API (3.2)", AD, "        log.write(\"terminate\")", "        NSApp.activate(ignoringOtherApps: true); log.write(\"terminate\")", "sourcesNeverCallApplicationActivation"),
]

def run(filter_):
    r = subprocess.run(["swift", "test", "--filter", filter_], cwd=ROOT, capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\)", out)))
    summary = [l for l in out.splitlines() if "Test run with" in l or "error:" in l][:2]
    return r.returncode, fails, summary

sel = sys.argv[1:]
for name, path, old, new, flt in M:
    if sel and not any(s in name for s in sel): continue
    orig = path.read_text(encoding="utf-8")
    assert old in orig, f"{name}: 找不到要破壞的程式碼"
    path.write_text(orig.replace(old, new, 1), encoding="utf-8")
    try:
        rc, fails, summ = run(flt)
    finally:
        path.write_text(orig, encoding="utf-8")
    print(f"[{name}] filter={flt!r}\n  破壞後 rc={rc}（非 0 = 紅） 失敗測試={fails}\n  {summ}", flush=True)
rc, fails, summ = run("FastBullTickerAppTests")
print(f"[還原後] rc={rc} {summ}")
