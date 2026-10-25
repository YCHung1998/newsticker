#!/usr/bin/env python3
"""settings-gear 第 A 段的 mutation 證據：逐一破壞實作 → 跑 swift test（應紅，列出失敗的測試）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/ga-mutations.py [名稱前綴…]   例：python3 Tests/ga-mutations.py G1 G2
完整輸出由呼叫端導向 Tests/evidence/ga-mutations.log。每組只跑相關 suite（--filter）；最後那輪跑完整 `swift test`。
Core 與 App 的測試目標都在同一個 `swift test`，所以 filter 以測試名稱的 regex 表示。"""
import subprocess, re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
A = ROOT / "Sources/FastBullTickerApp"
C = ROOT / "Sources/FastBullTickerCore"
SH, HT, TV, NI, GG, TS, SM_, AP, MM, FC, LA, CORE = (A/"ShellConfig.swift", A/"HitTesting.swift", A/"TickerView.swift", A/"NavigationInput.swift",
    A/"GearGlyph.swift", A/"TickerStyle.swift", A/"StyleStore.swift", A/"StyleApplier.swift", A/"StyleMenuModel.swift",
    A/"FeedClient.swift", A/"LaunchAtLoginService.swift", C/"TickerScheduler.swift")
SYS = A/"SystemLaunchAtLoginService.swift"
LV = "LaunchAtLogin"
SV = "SettingsValues|TickerStyleTests|StyleParser|StyleStore|StyleMenu|StyleApply"
KV = "Reconfigure|SchedulerInvariant|StyleApply|SeekHold|FreezeResume"
PV = "FeedClient|PollInterval|SnapshotResend|HelperArguments|StyleApply|AppSmoke|ReplayLive|Rebase"
LAYOUT = "GearLayout|GearHit|GearSnapshot|HitTesting|NavigationView|StyleApply|TickerRenderer|StripAlignment|TickerStyleTests|AppSmoke|StyleSnapshot"
# (名稱, 檔案, 舊字串, 新字串, 預期出現次數, filter)
M = [
 # --- task 1：版面槽寬與面板寬度推導 ---
 ("G1 面板寬寫死 620", SH, "panelSize: CGSize(width: panelWidth(gearSlotWidth: 28, labelWidth: 150, strip: ControlStripLayout(), tapeViewport: designTapeViewport), height: 42),",
  "panelSize: CGSize(width: 620, height: 42),", 1, LAYOUT),
 ("G2 標籤不右移齒輪槽寬", TV, "labelLayer.frame = CGRect(x: gw, y: 0, width: lw, height: h)", "labelLayer.frame = CGRect(x: 0, y: 0, width: lw, height: h)", 1, LAYOUT),
 ("G3 可視寬度漏加齒輪槽（leftInset 不含槽寬）", SH, "labelWidth: leftInset(showLabel: showLabel))", "labelWidth: showLabel ? Double(labelWidth) : 0)", 1, LAYOUT),
 ("G4 命中測試漏加齒輪槽（inset 只含標籤）", HT, "let inset = g.leftInset", "let inset = g.labelWidth", 1, LAYOUT),
 ("G5 控制列圖層漏加槽寬", TV, "let st = config.strip, left = Double(gw + lw)", "let st = config.strip, left = Double(lw)", 1, LAYOUT),
 ("G6 makeHitGeometry 不帶齒輪槽寬", SH, "labelWidth: showLabel ? Double(labelWidth) : 0, gearSlotWidth: gearSlotWidth, strip: strip,", "labelWidth: showLabel ? Double(labelWidth) : 0, gearSlotWidth: 0, strip: strip,", 1, LAYOUT),
 # --- task 2：齒輪命中、觸發、hover、圖示 ---
 ("G7 齒輪槽不命中 .gear", HT, "if x < g.gearSlotWidth { return .gear }", "if false { return .gear }", 1, LAYOUT),
 ("G8 齒輪 mouse-down 就觸發", NI, "if target == .drag { performDrag() } else { pressed = target }", "if target == .gear { onGear() }; if target == .drag { performDrag() } else { pressed = target }", 1, LAYOUT),
 ("G9 離開面板不復原 hover", TV, "        if !inside { setGearHover(false) }                       // 離開面板復原齒輪高亮\n", "", 1, LAYOUT),
 ("G10 hover 判斷恆為真", TV, "setGearHover(HitTesting.target(at: p, in: router.geometry, items: []) == .gear)", "setGearHover(true)", 1, LAYOUT),
 ("G11 齒輪路徑偏離中心 3pt", GG, "let c = CGPoint(x: bounds.midX, y: bounds.midY)", "let c = CGPoint(x: bounds.midX + 3, y: bounds.midY)", 1, LAYOUT),
 ("G12 mouse-up 不檢查放開位置", NI, "guard target == down else { return false }", "", 1, LAYOUT),
 ("G13 點穿模式仍觸發齒輪", NI, "guard isEnabled, button == .left, let down = pressed else { return false }", "guard button == .left, let down = pressed else { return false }", 1, LAYOUT),
 # --- task 3：TickerStyle 新欄位 ---
 ("S1 seekHold 範圍下限放寬到 0", TS, "public static let seekHoldSeconds: ClosedRange<Double> = 0.5...10", "public static let seekHoldSeconds: ClosedRange<Double> = 0...10", 1, SV),
 ("S2 最近檔位平手取較小者", TS, "where abs(Double(step) - v) <= abs(Double(best) - v) { best = step }", "where abs(Double(step) - v) < abs(Double(best) - v) { best = step }", 1, SV),
 ("S3 解析不夾制輪詢間隔", TS, "let step = TickerStyle.nearestPollStep(n)", "let step = Int(n)", 1, SV),
 ("S4 clamped() 不夾制輪詢間隔", TS, "s.pollIntervalSeconds = TickerStyle.nearestPollStep(Double(pollIntervalSeconds))", "s.pollIntervalSeconds = pollIntervalSeconds", 1, SV),
 ("S5 預設停留秒數改 2", TS, "seekHoldSeconds: 1, pollIntervalSeconds: 10)", "seekHoldSeconds: 2, pollIntervalSeconds: 10)", 1, SV),
 ("S6 輪詢動作寫到別的欄位", MM, "case .setPollIntervalSeconds(let n): style.pollIntervalSeconds = n", "case .setPollIntervalSeconds(let n): style.replayCount = n", 1, SV),
 # --- task 4：seekHoldSeconds 經 Core reconfigure ---
 ("K1 reconfigure 不更新 seekHoldSeconds", CORE, "        config.seekHoldSeconds = t.seekHoldSeconds\n", "", 1, KV),
 ("K2 reconfigure 清掉進行中的保持", CORE, "        config.seekHoldSeconds = t.seekHoldSeconds\n", "        config.seekHoldSeconds = t.seekHoldSeconds; holdRemaining = 0\n", 1, KV),
 ("K3 StyleApplier 漏傳 seekHoldSeconds", AP, "seekHoldSeconds: style.seekHoldSeconds)", "seekHoldSeconds: 1)", 1, KV),
 ("K4 Tunables.init(config:) 不帶現值", CORE, "seekHoldSeconds: config.seekHoldSeconds)", "seekHoldSeconds: 1)", 1, KV),
 # --- task 5：輪詢間隔與 helper 計畫性重啟 ---
 ("P1 計畫性重啟進入退避流程", FC, "        if restartPending {                        // 計畫性重啟：不進退避、不碰退避狀態\n            restartPending = false\n            onEvent(.exited(generation: gen, status: status, restartIn: 0))\n            return launch()\n        }\n", "", 1, PV),
 ("P2 相同參數也重啟", FC, "guard !stopping, arguments != config.arguments else { return }", "guard !stopping else { return }", 1, PV),
 ("P3 重啟進行中不合併（再次關 stdin 並重排計時）", FC, ", let p = process, p.isRunning, !restartPending else { return }", ", let p = process, p.isRunning else { return }", 1, PV),
 ("P4 reconfigure 不更新儲存的參數", FC, "            config.arguments = arguments\n", "", 1, PV),
 ("P5 啟動套用也回呼輪詢間隔", AP, "if pollChanged && source != \"startup\" {", "if pollChanged {", 1, PV),
 ("P6 預設間隔也帶 --interval-ms", FC, "pollIntervalSeconds == TickerStyle.default.pollIntervalSeconds ? [] :", "false ? [] :", 1, PV),
 ("P7 Core：中途 snapshot 清掉即時佇列", CORE, "            hasBaseline = true\n            return []", "            hasBaseline = true; liveQueue = []\n            return []", 1, PV),
 ("P8 Core：中途 snapshot 把模式設回 replay", CORE, "            hasBaseline = true\n            return []", "            hasBaseline = true; mode = .replay\n            return []", 1, PV),
 ("P9 重啟不升級 SIGTERM（忽略 EOF 的 helper 卡死）", FC, "            try? stdinHandle?.close()\n            armTerminationTimers(generation: generation)\n        }\n    }", "            try? stdinHandle?.close()\n        }\n    }", 1, PV),
 # --- task 6：開機自動啟動服務 ---
 ("L1 需核准時開關也顯示為開", LA, "let isOn = status == .enabled                       // 開關位置只由實際狀態決定\n", "let isOn = status == .enabled || status == .requiresApproval\n", 1, LV),
 ("L2 註冊失敗時吞掉錯誤", LA, "lastError = (error as NSError).localizedDescription", "lastError = nil", 1, LV),
 ("L3 需核准被對應成已啟用", SYS, "case .requiresApproval: return .requiresApproval", "case .requiresApproval: return .enabled", 1, LV),
 ("L4 已啟用時仍重複註冊", LA, "if service.status != .enabled { try service.enable() }", "try service.enable()", 1, LV),
 ("L5 refresh 不清除舊錯誤", LA, "        lastError = nil\n        viewState = Self.makeState(status: service.status, error: nil)", "        viewState = Self.makeState(status: service.status, error: lastError)", 1, LV),
]

def run(flt=None):
    cmd = ["swift", "test"] + (["--filter", flt] if flt else [])
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=1800)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
    summ = [l.strip() for l in out.splitlines() if "Test run with" in l or "error:" in l][:2]
    return r.returncode, fails, summ

survived = 0
for name, path, old, new, cnt, flt in M:
    if sys.argv[1:] and not any(name.startswith(a) for a in sys.argv[1:]): continue
    orig = path.read_text(encoding="utf-8")
    assert orig.count(old) == cnt, f"{name}: 要破壞的程式碼出現 {orig.count(old)} 次（預期 {cnt}）"
    path.write_text(orig.replace(old, new), encoding="utf-8")
    try:
        rc, fails, summ = run(flt)
    finally:
        path.write_text(orig, encoding="utf-8")
    caught = rc != 0 and (bool(fails) or any("error:" in x for x in summ))
    verdict = "紅（偵測到）" if caught else "!!! 仍然綠（測試沒抓到）"
    survived += not caught
    print(f"[{name}]\n  破壞後 rc={rc} {verdict}\n  失敗測試={fails[:8]}\n  {summ}", flush=True)
rc, fails, summ = run()
print(f"\n還原後（完整 swift test）rc={rc} 失敗測試={fails} {summ}  存活的 mutation 數={survived}", flush=True)
