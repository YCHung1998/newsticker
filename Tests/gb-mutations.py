#!/usr/bin/env python3
"""settings-gear (B) tasks 7-10 的 mutation 證據：逐一破壞實作 → 跑對應測試（應紅）→ 還原 → 結尾跑一次確認回綠。
用法（專案根目錄）：python3 Tests/gb-mutations.py [名稱子字串...]   輸出摘要到 stdout（建議 tee Tests/evidence/gb-mutations.log）。"""
import subprocess, sys, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources/FastBullTickerApp"
PL, MD, CV, PN = SRC/"SettingsPanelPlacement.swift", SRC/"SettingsPanelModel.swift", SRC/"SettingsPanelContentView.swift", SRC/"SettingsPanel.swift"
CO, CT, WI, MO, TV = SRC/"SettingsPanelCoordinator.swift", SRC/"SettingsPanelController.swift", SRC/"SettingsPanelWiring.swift", SRC/"GlobalMouseDownMonitor.swift", SRC/"TickerView.swift"

M = [
 ("G1 下方放不下也放下方", PL, "if spaceBelow >= h { y = below }", "if true { y = below }", "SettingsPanelShell"),
 ("G2 間距未套用", PL, "let below = t.minY - gap - h", "let below = t.minY - h", "SettingsPanelShell"),
 ("G3 水平不夾制", PL, "let x = clamp(t.minX, vis.minX, vis.maxX - w)", "let x = t.minX", "SettingsPanelShell"),
 ("G4 面板外判斷忽略跑馬燈", PL, "!panelFrame.contains(point) && !tickerFrame.contains(point)", "!panelFrame.contains(point)", "SettingsPanelShell|SettingsPanelDismiss"),
 ("G5 面板可成為 key", PN, "public override var canBecomeKey: Bool { false }", "public override var canBecomeKey: Bool { true }", "SettingsPanelShell"),
 ("G6 面板層級同跑馬燈", PN, "config.level.rawValue + 1", "config.level.rawValue", "SettingsPanelShell"),
 ("G7 關閉時不移除監看器", CO, "        monitor.remove()\n        window.hide()", "        window.hide()", "SettingsPanelDismiss|SettingsPanelSmoke"),
 ("G8 齒輪按下也關閉（關了又重開）", CO, "if !onGear { close() }", "close()", "SettingsPanelDismiss"),
 ("G9 全域遮罩加入鍵盤", MO, "[.leftMouseDown, .rightMouseDown]", "[.leftMouseDown, .rightMouseDown, .keyDown]", "SettingsPanelDismiss"),
 ("G10 跑馬燈按下不回報", TV, "onTickerPointerDown?(HitTesting.target(at: p, in: router.geometry, items: router.hitItems()) == .gear)", "_ = p", "SettingsPanelDismiss|SettingsPanelSmoke"),
 ("G11 onGear 未接", WI, "view.router.onGear = { [weak coordinator] in coordinator?.toggle() }", "view.router.onGear = { }", "SettingsPanelDismiss|SettingsPanelSmoke"),
 ("G12 輪詢檔位與選單不一致", MD, "let polls = StyleRanges.pollIntervalSteps", "let polls = [10, 20, 60]", "SettingsPanelModel|SettingsPanelControls"),
 ("G13 字級檔位少一檔", MD, "let fonts = StyleMenuModel.fontSizeSteps", "let fonts = Array(StyleMenuModel.fontSizeSteps.dropLast())", "SettingsPanelModel|SettingsPanelControls"),
 ("G14 停留步進 1", MD, "step: 0.5, value: style.seekHoldSeconds", "step: 1, value: style.seekHoldSeconds", "SettingsPanelModel|SettingsPanelControls"),
 ("G15 值變也重建控制項", CV, "if sig != signature {", "if true {", "SettingsPanelControls"),
 ("G16 拖動中旋鈕回彈", CV, "abs(s.doubleValue - sl.value) >= sl.step / 2", "true", "SettingsPanelControls"),
 ("G17 開啟時不重讀開機啟動狀態", CT, "        launch.refresh()\n        refresh()", "        refresh()", "SettingsPanelControls"),
 ("G18 開機啟動寫進樣式", CT, "            launch.setEnabled(on)\n", "            launch.setEnabled(on)\n            onStyleAction(.toggleShowTime)\n", "SettingsPanelControls|SettingsPanelSmoke"),
 ("G19 樣式變更不重新整理面板", WI, "if coordinator.isOpen { controller.refresh() }", "_ = controller", "SettingsPanelControls|SettingsPanelSmoke"),
 ("G20 控制項不隨熱重載更新（segmented）", CV, "case .segmented(let id, _, _, let selected): segmentedById[id]?.selectedSegment = selected ?? -1", "case .segmented: break", "SettingsPanelControls|SettingsPanelSmoke"),
]

def run(filter_):
    r = subprocess.run(["swift", "test", "--filter", filter_], cwd=ROOT, capture_output=True, text=True, timeout=900)
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
rc, fails, summ = run("SettingsPanel")
print(f"[還原後] filter='SettingsPanel' rc={rc} {summ}")
