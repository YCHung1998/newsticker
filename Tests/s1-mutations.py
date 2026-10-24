#!/usr/bin/env python3
"""ticker-style-settings 第 S1 段（1.1、2.1、3.1）的 mutation 證據：
逐一破壞實作 → 跑 swift test（應紅，列出失敗的測試）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/s1-mutations.py [名稱前綴…]   完整輸出存於 Tests/evidence/s1-mutations.log"""
import subprocess, re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
A, C = ROOT / "Sources/FastBullTickerApp", ROOT / "Sources/FastBullTickerCore"
TS, SS, SW, SCH, LAY = A/"TickerStyle.swift", A/"StyleStore.swift", A/"StyleFileWatching.swift", C/"TickerScheduler.swift", C/"Layout.swift"
# (名稱, 檔案, 舊字串, 新字串, 預期出現次數)
M = [
 # --- 1.1 TickerStyle／StyleParser ---
 ("T1 預設 fontSize 被改成 17", TS, "cornerRadius: 0, fontSize: 16, scrollSpeed: 90", "cornerRadius: 0, fontSize: 17, scrollSpeed: 90", 1),
 ("T2 放寬 fontSize 上限到 40", TS, "fontSize: ClosedRange<Double> = 10...26", "fontSize: ClosedRange<Double> = 10...40", 1),
 ("T3 色碼接受 8 位數（含 alpha）", TS, "guard u.count == 7, u[0] == 0x23", "guard u.count >= 7, u[0] == 0x23", 1),
 ("T4 非法色碼不取預設而取洋紅", TS, "非法色碼 \\(str)，改用預設值 \\(def.hex)\"); return def", "非法色碼 \\(str)，改用預設值 \\(def.hex)\"); return RGBColor(hex: \"#FF00FF\")!", 1),
 ("T5 相對亮度係數 R／B 對調", TS, "0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)", "0.2126 * lin(b) + 0.7152 * lin(g) + 0.0722 * lin(r)", 1),
 ("T6 低對比度時不照用（重設為預設）", TS, "            if ratio < ContrastRatio.threshold {\n", "            if ratio < ContrastRatio.threshold {\n                s = TickerStyle.default\n", 1),
 ("T7 未知鍵不警告", TS, "for k in obj.keys.sorted() where !TickerStyle.keys.contains(k) {", "for k in obj.keys.sorted() where false {", 1),
 ("T8 replayCount 接受小數（取整）", TS, "if case .number(let n) = v, n == n.rounded() {", "if case .number(let n) = v {", 1),
 ("T9 version 大於 1 也接受", TS, "n == Double(StyleRanges.supportedVersion) else { return .failure(.unsupportedVersion", "n >= 1 else { return .failure(.unsupportedVersion", 1),
 ("T10 檔案大小上限放寬 10 倍", TS, "guard data.count <= StyleRanges.maxFileBytes else", "guard data.count <= 10 * StyleRanges.maxFileBytes else", 1),
 ("T11 labelText 超長不截斷", TS, "s.labelText = String(t.prefix(StyleRanges.labelTextLength.upperBound))\n                    warn", "s.labelText = t\n                    warn", 1),
 ("T12 正規化輸出鍵不排序", TS, "[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]", "[.prettyPrinted, .withoutEscapingSlashes]", 1),
 ("T13 寫出小寫色碼", TS, "\"#%02X%02X%02X\"", "\"#%02x%02x%02x\"", 1),
 # --- 2.1 Core ---
 ("C1 改速度不調整 baseOffset（視覺跳動）", SCH, "baseOffset += (config.speed - t.speed) * tapeTime", "", 1),
 ("C2 reconfigure 前不結算舊速度的流逝時間", SCH, "        advance()                                             // 呼叫之前流逝的時間屬於舊速度（隱藏／停留時不推進）\n", "", 1),
 ("C3 reconfigure 重新量測已排入訊息", SCH, "        measurer = newMeasurer\n", "        measurer = newMeasurer\n        for i in placed.indices { placed[i].width = newMeasurer(placed[i].text) }\n", 1),
 ("C4 排入時沒帶 showTime", SCH, "linkSlotWidth: config.linkSlotWidth, showTime: config.showTime, measurer: measurer)", "linkSlotWidth: config.linkSlotWidth, measurer: measurer)", 1),
 ("C5 layoutItem 的 showTime=false 仍含時間", LAY, "let time = showTime ? TimeFormatter(timeZone: timeZone).string(forMs: item.publishedAtMs) : \"\"", "let time = TimeFormatter(timeZone: timeZone).string(forMs: item.publishedAtMs)", 1),
 ("C6 replayCount 不更新", SCH, "        config.replayCount = t.replayCount\n", "", 1),
 ("C7 viewportWidth 不更新", SCH, "        config.viewportWidth = t.viewportWidth\n", "", 1),
 ("C8 reconfigure 解除隱藏凍結", SCH, "        measurer = newMeasurer\n", "        measurer = newMeasurer\n        isHidden = false\n", 1),
 ("C9 displayString 恆含空白前綴", LAY, "timeString.isEmpty ? text : timeString + \" \" + text", "timeString + \" \" + text", 1),
 # --- 3.1 StyleStore ---
 ("S1 移除自寫入辨識（寫完不記住內容）", SS, "lock.withLock { _lastBytes = data; _configProblem = nil; _writeCount += 1; _lastWriteError = nil }", "lock.withLock { _configProblem = nil; _writeCount += 1; _lastWriteError = nil }", 1),
 ("S2 載入時改寫檔案", SS, "write(\"style: 已載入樣式檔\")", "write(\"style: 已載入樣式檔\"); _ = performWrite()", 1),
 ("S3 熱重載失敗時覆蓋舊值（重設為預設）", SS, "lock.withLock { _configProblem = e }\n                write(\"style: error 樣式檔無法解讀：\\(e)；保留目前樣式\")", "lock.withLock { _configProblem = e; _style = .default }\n                write(\"style: error 樣式檔無法解讀：\\(e)；保留目前樣式\")", 1),
 ("S4 熱重載沒有 debounce", SS, "_reloadTimer = clock.schedule(after: Self.reloadDebounce", "_reloadTimer = clock.schedule(after: 0", 1),
 ("S5 寫回前不備份", SS, "if needsBackup(onDisk) {", "if false {", 1),
 ("S6 寫回沒有 debounce", SS, "_writeTimer = clock.schedule(after: Self.writeDebounce", "_writeTimer = clock.schedule(after: 0", 1),
 ("S7 檔案被刪除時重設為預設", SS, "let had = lock.withLock { () -> Bool in let h = _lastBytes != nil;", "let had = lock.withLock { () -> Bool in _style = .default; let h = _lastBytes != nil;", 1),
 ("S8 檔案較新時不丟棄待寫的選單變更", SS, "_writeTimer?.cancel(); _writeTimer = nil; _writePending = false      // 檔案較新：丟棄尚未寫出的選單變更", "", 1),
 ("S9 update 不夾制", SS, "apply(s.clamped())", "apply(s)", 1),
 ("S10 重設為預設不備份", SS, "ioLock.withLock { backupExistingFile() }", "", 1),
 ("S11 忽略環境變數 FASTBULL_TICKER_STYLE", SS, "if let p = environment[environmentKey], !p.isEmpty { return URL(fileURLWithPath: p) }", "", 1),
 ("S12 無檔案時自動建立", SS, "write(\"style: 無樣式檔，使用預設樣式（不自動建立）\")", "write(\"style: 無樣式檔，使用預設樣式（不自動建立）\"); _ = performWrite()", 1),
 ("S13 DispatchSource 不訂閱任何事件", SW, "eventMask: [.write, .rename, .delete, .extend, .attrib, .link, .revoke]", "eventMask: []", 1),
 ("S14 損壞檔案不設「設定檔有誤」", SS, "lock.withLock { _style = .default; _configProblem = e; _lastWarnings = [] }", "lock.withLock { _style = .default; _lastWarnings = [] }", 1),
]

def run():
    r = subprocess.run(["swift", "test"], cwd=ROOT, capture_output=True, text=True, timeout=1200)
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
    print(f"[{name}]\n  破壞後 rc={rc} {verdict}\n  失敗測試={fails[:8]}\n  {summ}", flush=True)
rc, fails, summ = run()
print(f"\n還原後 rc={rc} {summ}  存活的 mutation 數={survived}", flush=True)
