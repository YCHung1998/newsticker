#!/usr/bin/env python3
"""spikes 的日誌／CSV 分析與判定器。退出碼：0 通過、1 判定失敗、2 用法錯誤。

子指令：
  s1config   --dry-run-all [--bin PATH]   |  --log FILE   驗證 S1 的生效值與參數相符
  focus      --log FILE --target-bundle B  S2 判定：frontmost 不變、本 App 啟用通知為 0
  typing     --file FILE [--pattern abcdefghij]  打字字串比對（無缺字）
  s3         --log FILE                    S3 補料誤差統計與判定
  csv        --file FILE                   S4 取樣 CSV 統計（平均、最大、p95、RSS 起訖差）
  frames     --log FILE                    S4 幀間隔分佈
  position   --before LOG --after LOG      S5 位置還原（誤差 <= tol px）
"""
import argparse
import csv
import math
import os
import subprocess
import sys


def read_events(path):
    ev = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            if len(parts) < 2:
                continue
            kv = {}
            if len(parts) > 2:
                for tok in parts[2].split(" "):
                    if "=" in tok:
                        k, v = tok.split("=", 1)
                        kv[k] = v
            ev.append((parts[0], parts[1], kv))
    return ev


def percentile(values, p):
    """nearest-rank 百分位數（p 為 0-100）。"""
    if not values:
        return float("nan")
    s = sorted(values)
    k = max(1, int(math.ceil(p / 100.0 * len(s))))
    return s[k - 1]


def verdict(ok, problems):
    if ok:
        print("RESULT: PASS")
        return 0
    for p in problems:
        print("  problem: " + p)
    print("RESULT: FAIL")
    return 1


# ---------------------------------------------------------------- s1config
RAW = {"floating": "3", "statusBar": "25"}  # NSWindow.Level.floating=3, .statusBar=25（獨立於 Swift 實作的期望值）


def expected_behavior(level, join, stationary):
    s = {"canJoinAllSpaces", "fullScreenAuxiliary", "ignoresCycle"}
    if stationary:
        s.add("stationary")
    if join:
        s.add("canJoinAllApplications")
    return s


def check_s1_events(events, level, join, stationary):
    problems = []
    exp = [kv for _, e, kv in events if e == "config.expected"]
    eff = [kv for _, e, kv in events if e == "config.effective"]
    if not exp:
        return ["no config.expected event"]
    for label, kv in [("expected", exp[-1])] + ([("effective", eff[-1])] if eff else []):
        raw = kv.get("level.raw")
        if raw != RAW[level]:
            problems.append("%s level.raw=%s, want %s (%s)" % (label, raw, RAW[level], level))
        got = set(filter(None, kv.get("behavior", "").split(",")))
        want = expected_behavior(level, join, stationary)
        if got != want:
            problems.append("%s behavior=%s, want %s" % (label, sorted(got), sorted(want)))
        if kv.get("hidesOnDeactivate") != "false":
            problems.append("%s hidesOnDeactivate=%s, want false" % (label, kv.get("hidesOnDeactivate")))
        if kv.get("canBecomeKey") != "false" or kv.get("canBecomeMain") != "false":
            problems.append("%s canBecomeKey/Main must be false" % label)
    return problems


def cmd_s1config(a):
    if a.log:
        ev = read_events(a.log)
        req = [kv for _, e, kv in ev if e == "config.requested"]
        if not req:
            return verdict(False, ["no config.requested event"])
        r = req[-1]
        probs = check_s1_events(ev, r["level"], r["join-all-apps"] == "on", r["stationary"] == "on")
        if not any(e == "config.effective" for _, e, _ in ev):
            probs.append("no config.effective event (window never created; dry-run logs only prove expected values)")
        return verdict(not probs, probs)
    if a.dry_run_all:
        import itertools
        import tempfile
        allprobs = []
        for level, join, stat in itertools.product(["floating", "statusBar"], [False, True], [True, False]):
            with tempfile.TemporaryDirectory() as td:
                lf = os.path.join(td, "d.log")
                cmd = [a.bin, "--dry-run", "--level", level, "--join-all-apps", "on" if join else "off",
                       "--stationary", "on" if stat else "off", "--log-file", lf]
                r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                if r.returncode != 0:
                    allprobs.append("%s: exit %d %s" % (cmd[3:], r.returncode, r.stderr.decode()))
                    continue
                ev = read_events(lf)
                probs = check_s1_events(ev, level, join, stat)
                wc = [kv.get("window-created") for _, e, kv in ev if e == "dryrun.done"]
                if wc != ["false"]:
                    probs.append("dry-run must report window-created=false")
                print("%-9s joinAllApps=%-3s stationary=%-3s -> %s" % (level, "on" if join else "off", "on" if stat else "off",
                                                                      "ok" if not probs else "MISMATCH"))
                allprobs += ["%s/%s/%s: %s" % (level, join, stat, p) for p in probs]
        return verdict(not allprobs, allprobs)
    print("need --log or --dry-run-all", file=sys.stderr)
    return 2


# ---------------------------------------------------------------- focus / typing
def cmd_focus(a):
    ev = read_events(a.log)
    self_pids = {kv.get("pid") for _, e, kv in ev if e == "self"}
    samples = [kv for _, e, kv in ev if e == "frontmost"]
    acts = [kv for _, e, kv in ev if e == "didActivate"]
    problems = []
    if len(samples) < a.min_samples:
        problems.append("only %d frontmost samples (< %d): run too short or logger not running" % (len(samples), a.min_samples))
    bad = [s for s in samples if s.get("bundle") != a.target_bundle]
    if bad:
        problems.append("frontmost changed away from %s in %d samples (first: %s)" % (a.target_bundle, len(bad), bad[0].get("bundle")))
    self_acts = [x for x in acts if x.get("pid") in self_pids]
    if self_acts:
        problems.append("%d didActivate notifications for this app (pid %s)" % (len(self_acts), ",".join(sorted(self_pids))))
    if not self_pids:
        problems.append("log has no 'self' event (cannot attribute activations)")
    print("samples=%d didActivate=%d (self=%d) frontmost_changes=%d" % (len(samples), len(acts), len(self_acts), len(bad)))
    rc = verdict(not problems, problems)
    if a.typed_file and rc == 0:
        rc = cmd_typing(argparse.Namespace(file=a.typed_file, pattern=a.pattern))
    return rc


def cmd_typing(a):
    with open(a.file, encoding="utf-8") as f:
        text = f.read().replace("\n", "").replace("\r", "")
    pat = a.pattern
    problems = []
    if not text:
        problems.append("typed file is empty")
    elif text[0] not in pat:
        problems.append("first char %r not in pattern" % text[0])
    else:
        off = pat.index(text[0])
        for i, ch in enumerate(text):
            want = pat[(off + i) % len(pat)]
            if ch != want:
                problems.append("mismatch at index %d: got %r, want %r (missing/extra/garbled char; context %r)" % (
                    i, ch, want, text[max(0, i - 5): i + 5]))
                break
    print("typed_chars=%d" % len(text))
    return verdict(not problems, problems)


# ---------------------------------------------------------------- s3
def cmd_s3(a):
    ev = read_events(a.log)
    refills = [kv for _, e, kv in ev if e == "refill"]
    problems = []
    if not refills:
        return verdict(False, ["no refill events"])
    errs = [(float(r["actual"]) - float(r["scheduled"])) * 1000.0 for r in refills]
    slots = sorted({int(r["slot"]) for r in refills})
    missed = (slots[-1] - slots[0] + 1) - len(slots) + (slots[0] - 1)
    blank = sum(1 for r in refills if float(r["gap_before"]) < 0)
    opens = [float(kv["t"]) for _, e, kv in ev if e == "menu.open" and "t" in kv]
    closes = [float(kv["t"]) for _, e, kv in ev if e == "menu.close" and "t" in kv]
    sliders = [kv for _, e, kv in ev if e == "slider"]
    menu_s = (closes[-1] - opens[0]) if opens and closes else 0.0
    print("timer=%s refills=%d max_error_ms=%.1f p99_error_ms=%.1f missed=%d blank_events=%d menu_open_s=%.1f slider_callbacks=%d" % (
        refills[0].get("timer"), len(refills), max(errs), percentile(errs, 99), missed, blank, menu_s, len(sliders)))
    if max(errs) >= a.max_error_ms:
        problems.append("max error %.1f ms >= %.0f ms" % (max(errs), a.max_error_ms))
    if missed > 0:
        problems.append("%d refill slot(s) missed" % missed)
    if blank > 0:
        problems.append("%d refill(s) saw negative tail gap (visible blank)" % blank)
    if menu_s < a.min_menu_seconds:
        problems.append("menu open %.1f s < required %.0f s (menu.open/menu.close events)" % (menu_s, a.min_menu_seconds))
    if a.require_slider and len(sliders) == 0:
        problems.append("no slider callbacks logged")
    return verdict(not problems, problems)


# ---------------------------------------------------------------- csv
def cmd_csv(a):
    rows = []
    with open(a.file, newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        need = ["epoch", "app_cpu_pct", "app_rss_kb", "ws_cpu_pct"]
        if rd.fieldnames is None or any(n not in rd.fieldnames for n in need):
            return verdict(False, ["CSV header must contain %s, got %s" % (need, rd.fieldnames)])
        for i, r in enumerate(rd, start=2):
            try:
                rows.append({k: float(r[k]) for k in need})
            except (ValueError, TypeError):
                return verdict(False, ["line %d: non-numeric value %r" % (i, r)])
    problems = []
    n = len(rows)
    if n < a.min_rows:
        problems.append("rows=%d < min-rows %d" % (n, a.min_rows))
    if n >= 2:
        gaps = [rows[i + 1]["epoch"] - rows[i]["epoch"] for i in range(n - 1)]
        med = sorted(gaps)[len(gaps) // 2]
        if abs(med - a.interval) > a.interval * 0.2:
            problems.append("median sample spacing %.2fs differs from --interval %.2fs by > 20%%" % (med, a.interval))
        big = [g for g in gaps if g > a.interval * 2.5]
        if big:
            problems.append("%d sampling gap(s) > 2.5x interval (max %.1fs): sampler stalled or machine slept" % (len(big), max(big)))
    if n:
        for col, label in [("app_cpu_pct", "App CPU%"), ("ws_cpu_pct", "WindowServer CPU%")]:
            v = [r[col] for r in rows]
            print("%-18s mean=%.2f max=%.2f p95=%.2f" % (label, sum(v) / n, max(v), percentile(v, 95)))
        rss = [r["app_rss_kb"] for r in rows]
        print("%-18s first=%.0f KB last=%.0f KB delta=%+.0f KB max=%.0f KB" % ("App RSS", rss[0], rss[-1], rss[-1] - rss[0], max(rss)))
    print("rows=%d" % n)
    return verdict(not problems, problems)


# ---------------------------------------------------------------- frames
def cmd_frames(a):
    ev = read_events(a.log)
    fr = [kv for _, e, kv in ev if e == "frames"]
    if not fr:
        return verdict(False, ["no frames events (run with --frame-observer on for scheme B)"])
    keys = ["lt12", "b12_20", "b20_28", "b28_40", "gt40"]
    tot = {k: sum(int(f[k]) for f in fr) for k in keys}
    n = sum(tot.values())
    print("frames=%d  max_dt_ms=%.1f" % (n, max(float(f["max_ms"]) for f in fr)))
    for k, lab in zip(keys, ["<12ms(>83fps)", "12-20ms(~60fps)", "20-28ms", "28-40ms(~30fps)", ">40ms"]):
        print("  %-16s %6d  %5.1f%%" % (lab, tot[k], 100.0 * tot[k] / max(n, 1)))
    return 0


# ---------------------------------------------------------------- position
def cmd_position(a):
    def last(path, name):
        xs = [kv for _, e, kv in read_events(path) if e == name]
        return xs[-1] if xs else None
    saved, restored = last(a.before, "position.saved"), last(a.after, "position.restored")
    problems = []
    if not saved:
        problems.append("no position.saved in %s (drag + wait >= 0.3s before quitting)" % a.before)
    if not restored:
        problems.append("no position.restored in %s (start with --restore on)" % a.after)
    if saved and restored:
        dx = abs(float(saved["x"]) - float(restored["x"]))
        dy = abs(float(saved["y"]) - float(restored["y"]))
        print("saved=(%s,%s) restored=(%s,%s) dx=%.2f dy=%.2f" % (saved["x"], saved["y"], restored["x"], restored["y"], dx, dy))
        if dx > a.tol or dy > a.tol:
            problems.append("restore error exceeds %.1f px" % a.tol)
    return verdict(not problems, problems)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("s1config")
    s.add_argument("--log"); s.add_argument("--dry-run-all", action="store_true")
    s.add_argument("--bin", default=".build/debug/spike-s1"); s.set_defaults(fn=cmd_s1config)
    s = sp.add_parser("focus")
    s.add_argument("--log", required=True); s.add_argument("--target-bundle", required=True)
    s.add_argument("--min-samples", type=int, default=20); s.add_argument("--typed-file")
    s.add_argument("--pattern", default="abcdefghij"); s.set_defaults(fn=cmd_focus)
    s = sp.add_parser("typing")
    s.add_argument("--file", required=True); s.add_argument("--pattern", default="abcdefghij"); s.set_defaults(fn=cmd_typing)
    s = sp.add_parser("s3")
    s.add_argument("--log", required=True); s.add_argument("--max-error-ms", type=float, default=100.0)
    s.add_argument("--min-menu-seconds", type=float, default=60.0); s.add_argument("--require-slider", action="store_true")
    s.set_defaults(fn=cmd_s3)
    s = sp.add_parser("csv")
    s.add_argument("--file", required=True); s.add_argument("--interval", type=float, default=10.0)
    s.add_argument("--min-rows", type=int, default=360); s.set_defaults(fn=cmd_csv)
    s = sp.add_parser("frames")
    s.add_argument("--log", required=True); s.set_defaults(fn=cmd_frames)
    s = sp.add_parser("position")
    s.add_argument("--before", required=True); s.add_argument("--after", required=True)
    s.add_argument("--tol", type=float, default=1.0); s.set_defaults(fn=cmd_position)
    a = p.parse_args()
    sys.exit(a.fn(a))


if __name__ == "__main__":
    main()
