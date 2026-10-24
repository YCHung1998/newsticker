#!/usr/bin/env python3
"""app-shell 2.1／2.2 的 mutation 證據：逐一破壞 FeedClient 實作 → 跑對應測試（應紅）→ 還原 → 跑一次確認回綠。
用法（專案根目錄）：python3 Tests/app-mutations.py [mutation 名稱...]   輸出摘要到 stdout。"""
import subprocess, sys, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources/FastBullTickerApp"
FC, BO, PR = SRC / "FeedClient.swift", SRC / "Backoff.swift", SRC / "PipeReader.swift"

M = [
 ("M1 退避不設上限", BO, "min(base * pow(2, Double(exponent)), maxDelay)", "base * pow(2, Double(exponent))", "BackoffPolicyTests"),
 ("M2 退避永不重置", BO, "if ranFor > policy.stableAfter { attempt = 0 }", "if ranFor < 0 { attempt = 0 }", "FeedClientTests|BackoffPolicyTests"),
 ("M3 EOF 不清除 handler 也不關 fd", PR, "h.readabilityHandler = nil          // 關鍵：不清除會對 EOF 空轉\n                try? h.close()\n", "", "PipeReaderTests"),
 ("M4 忽略 generation token", FC, "guard gen == generation else { return }   // 舊世代的終止事件：不改狀態、不觸發額外重啟", "_ = gen", "staleGenerationEventsAreIgnored"),
 ("M5 輸出不重置卡死計時", FC, "lastActivity = clock.now()                              // 任何 stdout 位元組（含半行）都算活著", "", "FeedClientResilience"),
 ("M6 忽略喚醒寬限", FC, "if let wakeMark { deadline = max(deadline, wakeMark + config.wakeGrace) }", "", "wake"),
 ("M7 不可恢復錯誤也進退避重啟", FC, "        onEvent(.fatal(error))\n    }", "        onEvent(.fatal(error))\n        restartTimer = clock.schedule(after: 1, on: queue) { [self] in launch() }\n    }", "missingExecutableIsFatalWithSingleAttempt|nonExecutableIsFatalWithoutBackoffLoop"),
 ("M8 逾時後不送 SIGTERM", FC, "p.terminate()                                      // SIGTERM", "_ = p", "shutdownSendsSigtermAfterTimeoutWhenHelperIgnoresEof"),
 ("M9 stderr 不讀走", FC, "stderrReader = PipeReader(handle: errPipe.fileHandleForReading, onData: { _ in }, onEOF: {})", "stderrReader = nil", "stderrFloodDoesNotBlockHelper"),
 ("M10 不處理 pid file 遺留的舊 helper", FC, "        reclaimStaleHelper()\n", "", "staleOrphanHelperIsKilledBeforeNewOneStarts"),
 ("M11 結束時不關 stdin", FC, "                try? stdinHandle?.close()\n                let gen = generation", "                let gen = generation", "shutdownClosesStdinAndCooperativeHelperIsNotSigtermed"),
]

def run(filter_):
    r = subprocess.run(["swift", "test", "--filter", filter_], cwd=ROOT, capture_output=True, text=True, timeout=300)
    out = r.stdout + r.stderr
    fails = sorted(set(re.findall(r"✘ Test (\w+)\(\) failed", out)))
    summary = [l for l in out.splitlines() if "Test run with" in l or "error:" in l][:3]
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
    print(f"[{name}] filter={flt!r}\n  破壞後 rc={rc}（非 0 = 紅） 失敗測試={fails}\n  {summ}")
rc, fails, summ = run("FastBullTickerAppTests|BackoffPolicyTests|PipeReaderTests|FeedClient")
print(f"[還原後] rc={rc} {summ}")
