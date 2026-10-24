#!/usr/bin/env python3
"""single-instance-guard 的 mutation 證據：逐一破壞實作 → 跑 SingleInstance/守衛測試（應紅）→ 還原 → 最後確認回綠。
用法（專案根目錄）：python3 Tests/g1-mutations.py [編號前綴...]"""
import subprocess, sys, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources/FastBullTickerApp"
G, AD = SRC / "SingleInstanceGuard.swift", SRC / "AppDelegate.swift"
FILTER = "SingleInstanceGuardTests|LinkOpenerGuardTests|PanelShellTests|StyleMenuGuardTests"

M = [
 ("G1 不排除自己", G, ".filter { $0.pid != selfPid }", ".filter { _ in true }"),
 ("G2 取消仍繼續啟動", G, "guard alert.confirmReplace() == .closeOld else { return .quitSelf }", "guard alert.confirmReplace() == .closeOld else { return .proceed }"),
 ("G3 不等舊實例消失就繼續", G, "while !alive.isEmpty, waited < limit - 1e-9 {", "while false {"),
 ("G4 逾時不 forceTerminate", G, "remaining.forEach { terminator.forceTerminate(pid: $0) }", ""),
 ("G5 競態兩邊都詢問", G, "isLater(selfPid, selfLaunchDate, than: $0) }) else { return .proceed }", "isLater(selfPid, selfLaunchDate, than: $0) || true }) else { return .proceed }"),
 ("G6 launchDate 相同不以 pid 判斷", G, "return pid > other.pid", "return false"),
 ("G7 環境變數不跳過", G, 'if environment[Self.allowMultipleVariable] == "1" { return .proceed }', ""),
 ("G8 force 後仍在卻繼續", G, "alert.showCannotClose()\n        return .quitSelf", "return .proceed"),
 ("G9 對自己也 terminate", G, "pids.forEach { terminator.terminate(pid: $0) }", "(pids + [selfPid]).forEach { terminator.terminate(pid: $0) }"),
 ("G10 無法關閉時不跳第二提示", G, "alert.showCannotClose()\n", ""),
 ("G11 對話框外的檔案呼叫 activate", AD, "NSApp.terminate(nil)\n            return", "NSApp.activate(); NSApp.terminate(nil)\n            return"),
 ("G12 例外檔內 activate 變兩處", G, "NSApp.activate() }", "NSApp.activate(); NSApp.activate() }"),
 ("G13 檢查改到面板之後（不再早於 PanelShell）", AD, "if !instanceCheck(environment) {", "let _ = PanelShell(config: config, frame: .zero)\n        if !instanceCheck(environment) {"),
 ("G14 結束新實例後不 return", AD, "NSApp.terminate(nil)\n            return\n", "NSApp.terminate(nil)\n"),
]

def run():
    r = subprocess.run(["swift", "test", "--filter", FILTER], cwd=ROOT, capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\)", out)))
    errs = [l for l in out.splitlines() if "error:" in l][:1]
    return r.returncode, fails, errs

def main():
    only = sys.argv[1:]
    survivors = []
    for name, path, old, new in M:
        if only and not any(name.startswith(p) for p in only): continue
        orig = path.read_text()
        if old not in orig:
            print(f"{name}: 找不到原文，mutation 失效"); survivors.append(name); continue
        path.write_text(orig.replace(old, new, 1))
        try: rc, fails, errs = run()
        finally: path.write_text(orig)
        status = "KILLED" if rc != 0 else "SURVIVED"
        if rc == 0: survivors.append(name)
        print(f"{name}: {status} {', '.join(fails[:4]) or errs}")
    rc, fails, _ = run()
    print(f"還原後: {'GREEN' if rc == 0 else 'RED ' + str(fails)}; 存活 {len(survivors)}: {survivors}")

main()
