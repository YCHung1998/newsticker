#!/usr/bin/env python3
"""ticker-style-settings 第 S2 段（4.1、5.1、6.1）的 mutation 證據：
逐一破壞實作 → 跑 swift test（應紅，列出失敗的測試）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/s2-mutations.py [名稱前綴…]   完整輸出存於 Tests/evidence/s2-mutations.log
只跑與樣式相關的 suite 以縮短時間（--filter）；最後的「還原後」那一輪跑完整 `swift test`。"""
import subprocess, re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
A = ROOT / "Sources/FastBullTickerApp"
BM, TV, AP, SH, MM, MC, WO, SM, SD, TS = (A/"ItemBitmap.swift", A/"TickerView.swift", A/"StyleApplier.swift", A/"ShellConfig.swift",
    A/"StyleMenuModel.swift", A/"StyleMenuController.swift", A/"WorkspaceFileOpener.swift", A/"StatusMenu.swift", A/"AppDelegate.swift", A/"TickerStyle.swift")
FILTER = "StyleApply|DefaultStyleRenders|StyleMenu|StyleAction|StatusMenu|AppSmoke|StyleSnapshot|TickerRenderer|PanelShell|NavigationView|LinkOpenerGuard|TickerStyleTests|StyleParser|StyleStore"
# (名稱, 檔案, 舊字串, 新字串, 預期出現次數)
M = [
 # --- 4.1 ItemBitmap／TickerView／StyleApplier ---
 ("B1 showTime=false 仍偵測時間粗體（量測端）", BM, "func measuredBoldLength(of s: String) -> Int { showTime ? ItemText.boldPrefixLength(of: s) : 0 }", "func measuredBoldLength(of s: String) -> Int { ItemText.boldPrefixLength(of: s) }", 1),
 ("B2 繪製端回到偵測字串內容（不用 timeString）", BM, "item.timeString.isEmpty ? (item.text, 0) : (item.timeString + \" \" + item.text, item.timeString.utf16.count)", "(item.timeString + \" \" + item.text, ItemText.boldPrefixLength(of: item.timeString + \" \" + item.text))", 1),
 ("B3 showTime=false 時仍多一個前導空白", BM, "item.timeString.isEmpty ? (item.text, 0) :", "item.timeString.isEmpty ? (\" \" + item.text, 0) :", 1),
 ("B4 bitmap 配色寫死（忽略 colors）", BM, "let bg = live ? colors.liveBackground : colors.replayBackground", "let bg = live ? RGBColor(r: 1, g: 1, b: 1) : RGBColor(r: 0, g: 0, b: 0)", 1),
 ("B5 色碼改用 sRGB 建構（與原型的 Generic RGB 不同）", BM, "var cgColor: CGColor { CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }", "var cgColor: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }", 1),
 ("V1 顏色變更時不重繪已排入訊息", TV, "        if report.colorsChanged {\n            let t0", "        if false {\n            let t0", 1),
 ("V2 重繪一律用目前字級（不分世代）", TV, "private func renderer(for seq: Int) -> ItemBitmapRenderer { eras.first { seq <= $0.upToSeq }?.renderer ?? bitmap }", "private func renderer(for seq: Int) -> ItemBitmapRenderer { bitmap }", 1),
 ("V3 字級改變時不記錄舊世代", TV, "if report.fontChanged { eras.append((upToSeq: maxSeqAdded, renderer: bitmap)) }", "", 1),
 ("V4 圓角不夾制", TV, "layer?.cornerRadius = CGFloat(min(max(style.cornerRadius, 0), Double(config.panelSize.height) / 2))", "layer?.cornerRadius = CGFloat(style.cornerRadius)", 1),
 ("V5 圓角不裁切（masksToBounds 關）", TV, "layer?.masksToBounds = true                                                  // 圓角裁切標籤、訊息與控制列", "layer?.masksToBounds = false", 1),
 ("V6 showLabel 改變時不更新命中幾何", TV, "            router.geometry = config.makeHitGeometry(showLabel: new.showLabel)\n", "", 1),
 ("V7 帶子裁切範圍不隨 showLabel 改變", TV, "clipLayer.frame = CGRect(x: lw - slant, y: 0, width: CGFloat(config.tapeViewport(showLabel: showLabel)) + slant, height: h)", "clipLayer.frame = CGRect(x: config.labelWidth - labelSlant, y: 0, width: CGFloat(config.tapeViewport(showLabel: true)) + labelSlant, height: h)", 1),
 ("V8 空隙底色不套用", TV, "layer?.backgroundColor = style.tapeBackground.cgColor", "", 1),
 ("V9 標籤文字不套用", TV, "        labelText.string = style.labelText\n", "", 1),
 ("V10 showLabel=false 不隱藏標籤", TV, "        labelLayer.isHidden = !showLabel\n        labelText.isHidden = !showLabel\n", "", 1),
 ("V11 顏色變更時改動 tapeX（位置跳動）", TV, "            for (seq, container) in layers { if let item = placedBySeq[seq] { redraw(container, item: item) } }", "            for (seq, container) in layers { if let item = placedBySeq[seq] { redraw(container, item: item); container.frame.origin.x += 1 } }", 1),
 ("A1 套用時不呼叫 Core reconfigure", AP, "        driver.reconfigure(tunables, measurer: view.itemMeasurer)\n", "", 1),
 ("A2 可視寬度不隨 showLabel", AP, "let viewport = config.tapeViewport(showLabel: style.showLabel)", "let viewport = config.tapeViewport(showLabel: true)", 1),
 ("A3 相同樣式也重套", AP, "        guard style != current else { return false }\n", "", 1),
 ("A4 replayCount 沒傳給排程器", AP, "replayCount: style.replayCount, showTime: style.showTime, timeZone: timeZone)", "replayCount: 10, showTime: style.showTime, timeZone: timeZone)", 1),
 ("A5 reconfigure 用舊 measurer（字級不更新）", AP, "driver.reconfigure(tunables, measurer: view.itemMeasurer)", "driver.reconfigure(tunables, measurer: { Double($0.count) * 10 })", 1),
 ("A6 scrollSpeed 沒傳給排程器", AP, "SchedulerTunables(speed: style.scrollSpeed,", "SchedulerTunables(speed: 90,", 1),
 ("D1 ShellConfig 排程設定忽略 style.scrollSpeed", SH, "c.speed = style.scrollSpeed", "c.speed = 90", 1),
 # --- 5.1 選單 ---
 ("M1 字級檔位 20 改為 21", MM, "(\"大\", 20)", "(\"大\", 21)", 1),
 ("M2 字級勾選永遠不勾", MM, "checked: style.fontSize == s.value, action: .setFontSize(s.value)", "checked: false, action: .setFontSize(s.value)", 1),
 ("M3 即時配色預設連重播配色一起改", MM, "style.liveText = LiveColorPreset.all[i].text            // 只動這兩個欄位，不動重播配色", "style.liveText = LiveColorPreset.all[i].text; style.replayBackground = LiveColorPreset.all[i].background", 1),
 ("M4 速度滑桿範圍放寬到 0…300", MM, "slider: Slider(kind: .scrollSpeed, range: StyleRanges.scrollSpeed, value: style.scrollSpeed)", "slider: Slider(kind: .scrollSpeed, range: 0...300, value: style.scrollSpeed)", 1),
 ("M5 設定檔有誤的提示行可點選", MM, "title: configProblemNotice, enabled: false))", "title: configProblemNotice, enabled: true))", 1),
 ("M6 訊息量檔位 20 改為 40（超出範圍）", MM, "replayCountSteps: [Int] = [5, 10, 20]", "replayCountSteps: [Int] = [5, 10, 40]", 1),
 ("M7 開啟設定檔不先建立檔案", MC, "            guard store.ensureFileExists() else {", "            guard true else {", 1),
 ("M8 開啟設定檔呼叫 opener 兩次", MC, "            let ok = opener.open(store.fileURL)\n", "            _ = opener.open(store.fileURL); let ok = opener.open(store.fileURL)\n", 1),
 ("M9 重設為預設改成只 update（不備份）", MC, "            store.resetToDefault()\n", "            store.update { $0 = .default }\n", 1),
 ("M10 選單不在展開前重建", MC, "    public func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }", "    public func menuNeedsUpdate(_ menu: NSMenu) { }", 1),
 ("M11 StatusMenu 少了樣式項目", SM, "        menu.addItem(styleItem)\n", "", 1),
 ("M12 熱重載／選單變更沒有接到套用端", AP, "        store.onChange = { [weak applier] style, src in", "        store.onChange = { [weak applier] style, src in return;", 1),
 ("M13 滑桿動作不寫回（onAction 被略過）", MC, "        onAction(StyleMenuModel.sliderAction(kind, s.doubleValue))", "", 1),
]

# 工作樹中有一個不屬於本 change 的未提交修改（ShellConfig.itemPadding 10，原型值為 14）使這個測試在基準線上就是紅的；
# 判定 mutation 是否被抓到時，以「除此之外還有別的測試變紅」為準。
KNOWN_BASELINE_FAILURES = {"defaultsAgreeWithShellConfigPrototypeConstants"}

def run(full=False):
    cmd = ["swift", "test"] + ([] if full else ["--filter", FILTER])
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=1800)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)) - KNOWN_BASELINE_FAILURES)
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
    caught = rc != 0 and (bool(fails) or any("error:" in x for x in summ))
    verdict = "紅（偵測到）" if caught else "!!! 仍然綠（測試沒抓到）"
    survived += not caught
    print(f"[{name}]\n  破壞後 rc={rc} {verdict}\n  失敗測試={fails[:8]}\n  {summ}", flush=True)
rc, fails, summ = run(full=True)
print(f"\n還原後（完整 swift test）rc={rc} 除基準線已知失敗外的失敗測試={fails} {summ}  存活的 mutation 數={survived}", flush=True)
