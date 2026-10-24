#!/usr/bin/env python3
"""scripts/demo-helper.sh 的輸出必須符合協定 v1（含 `url` 規則）：以 protocol/refcheck.py 逐行驗證。
用法（專案根目錄）：python3 Tests/demo-helper-protocol-check.py
斷言：snapshot 12 則其中有帶 url 與沒帶 url 者；之後的 items 也混合；所有 url 為 https://example.com/demo/<id>。"""
import json, os, subprocess, sys, time, pathlib, select
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "protocol"))
import refcheck

env = dict(os.environ, DEMO_ITEM_INTERVAL="1", DEMO_STATUS_INTERVAL="30")
p = subprocess.Popen([str(ROOT / "scripts/demo-helper.sh")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
lines, deadline = [], time.time() + 6.5
buf = b""
while time.time() < deadline:
    r, _, _ = select.select([p.stdout], [], [], 0.2)
    if r:
        chunk = os.read(p.stdout.fileno(), 65536)
        if not chunk: break
        buf += chunk
        while b"\n" in buf:
            ln, buf = buf.split(b"\n", 1); lines.append(ln)
p.stdin.close()
try: p.wait(timeout=5)
except subprocess.TimeoutExpired: p.kill()
validators = refcheck.build_validators()
bad = [(ln[:80], refcheck.check_line(ln, validators)) for ln in lines if not refcheck.check_line(ln, validators)[0]]
msgs = [json.loads(ln) for ln in lines]
snap = [m for m in msgs if m["type"] == "snapshot"]
batches = [m for m in msgs if m["type"] == "items"]
snap_items = snap[0]["items"] if snap else []
later = [i for m in batches for i in m["items"]]
urls = [i["url"] for i in snap_items + later if "url" in i]
ok = (not bad and len(snap_items) == 12 and len(later) >= 4
      and 0 < sum("url" in i for i in snap_items) < 12 and 0 < sum("url" in i for i in later) < len(later)
      and all(u == "https://example.com/demo/" + i["id"] for i in snap_items + later for u in [i.get("url")] if u))
print(f"lines={len(lines)} invalid={len(bad)} snapshot_items={len(snap_items)} snapshot_with_url={sum('url' in i for i in snap_items)} "
      f"later_items={len(later)} later_with_url={sum('url' in i for i in later)} sample_url={urls[0] if urls else None}")
print("PASS" if ok else f"FAIL {bad}")
sys.exit(0 if ok else 1)
