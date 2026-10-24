#!/usr/bin/env python3
"""ticker-navigation-link 第 N3 段（7.1、8.1）的 mutation 證據：
逐一破壞實作 → 跑 swift test（應紅，列出失敗的測試）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/n3-mutations.py [名稱前綴…]（可只重跑指定的 mutation，例如 A1）   完整輸出存於 Tests/evidence/n3-mutations.log"""
import subprocess, re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
A = ROOT / "Sources/FastBullTickerApp"
NI, TD, TV, IB, SC, PI = A/"NavigationInput.swift", A/"TickerDriver.swift", A/"TickerView.swift", A/"ItemBitmap.swift", A/"ShellConfig.swift", A/"PositionIndicator.swift"
NA, WO = A/"NavigationActions.swift", A/"WorkspaceURLOpener.swift"
# (名稱, 檔案, 舊字串, 新字串, 預期出現次數)
M = [
 ("N1 按鈕改在 mouse-down 觸發", NI, "else { pressed = target }", "else { pressed = target; if target == .previousButton { onPrevious() } }", 1),
 ("N2 mouse-up 不核對與按下時的目標相同", NI, "guard target == down else { return false }", "", 1),
 ("N3 右鍵也被當成左鍵處理", NI, "button == .left", "true", 2),
 ("N4 .drag 不呼叫 performDrag", NI, "if target == .drag { performDrag() }", "if target == .drag { }", 1),
 ("N5 按鈕／迴紋針也呼叫 performDrag", NI, "else { pressed = target }", "else { pressed = target; performDrag() }", 1),
 ("N6 點穿（isEnabled=false）仍處理事件", NI, "guard isEnabled, button == .left else { return nil }", "guard button == .left else { return nil }", 1),
 ("R1 TrackModel.add 不冪等", TD, "guard !contains(seq: seq) else { return false }", "", 1),
 ("R2 向後 seek 不重建圖層", TD, "for p in scheduler.placed where p.tapeX + p.width > off && p.tapeX < right { renderer.add(p) }", "", 1),
 ("R3 seek 後不同步捲動位移", TD, "            renderer.setScrollOffset(off)\n            refreshControlStrip()", "            refreshControlStrip()", 1),
 ("R4 控制列狀態每次都推送", TD, "if s != controlState {", "if true {", 1),
 ("R5 TickerView.add 不冪等（留下孤兒圖層）", TV, "guard track.add(seq: item.seq, tapeX: item.tapeX, width: item.width) else { return }    // 冪等", "_ = track.add(seq: item.seq, tapeX: item.tapeX, width: item.width)", 1),
 ("B1 時間不再粗體", IB, "return 8\n", "return 0\n", 1),
 ("B2 迴紋針不繪製", IB, "if item.hasLinkSlot, linkSlotWidth > 0 {", "if false {", 1),
 ("V1 帶子可視寬度寫死 470", SC, "strip.tapeViewportWidth(panelWidth: Double(panelSize.width), labelWidth: Double(labelWidth))", "470", 1),
 ("V2 帶子裁切區蓋到控制列", TV, "width: CGFloat(config.tapeViewportWidth) + slant", "width: CGFloat(config.panelSize.width - config.labelWidth) + slant", 1),
 ("V3 `<` 在清單第一則也啟用", PI, "previousEnabled: p.index > 1", "previousEnabled: true", 1),
 ("H1 核對不採用 mouseLocation（exit 遺失就卡住）", TD, "        scheduler.setPointerInside(inside)\n", "        _ = inside\n", 1),
 ("H2 指標進出事件不轉給 Core", TD, "public func setPointerInside(_ inside: Bool) { scheduler.setPointerInside(inside) }", "public func setPointerInside(_ inside: Bool) { }", 1),
 ("A1 迴紋針開啟了別則的連結", NA, "driver.placedItem(seq: seq)", "driver.scheduler.placed.first", 1),
 ("A2 迴紋針動作沒接上", NA, "router.onLink = { [weak self] seq in self?.openLink(seq: seq) }", "", 1),
 ("A3 `>` 動作沒接上", NA, "router.onNext = { [weak self] in self?.next() }", "", 1),
 ("O1 opener 啟用本 App（違反不啟用）", WO, "let config = NSWorkspace.OpenConfiguration()", "NSApp.activate(ignoringOtherApps: true)\n        let config = NSWorkspace.OpenConfiguration()", 1),
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
