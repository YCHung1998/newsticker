#!/usr/bin/env python3
"""spikes/RESULTS.md 格式與決定完整性檢查（由 check_results.sh 呼叫）。

格式（每格一個 `### <代號>` 區塊，位於 `## 實驗格` 章節內，欄位為 `- 欄位: 值`）：
  必填：實驗、清單條目、組合、情境、結果、原因類別、觀察
  結果 ∈ PASS / FAIL / 未執行
  PASS / FAIL：另需 日期(ISO 8601)、macOS(sw_vers 版本)、證據(相對於 spikes/ 的既存檔案，逗號分隔)
  FAIL：原因類別 ∈ 平台限制 / 實作錯誤，且需「佐證」（為何排除是我方錯誤）
        實作錯誤：不得記為已知限制；須有「重跑」欄指向已修正後重跑的格（結果為 PASS 或 平台限制 FAIL）
  未執行：原因類別 = "-"，觀察須寫明原因
`--require-decisions`：另檢查 `## 決定` 章節（D1 已知限制、D2 level+collectionBehavior、D3 渲染方案）。
"""
import argparse
import os
import re
import sys

RESULTS = ("PASS", "FAIL", "未執行")
CAUSES = ("平台限制", "實作錯誤")
REQUIRED = ["實驗", "清單條目", "組合", "情境", "結果", "原因類別", "觀察"]
ID_RE = re.compile(r"\b(S[1-5]-[A-Za-z0-9]+)\b")
EMPTY = ("", "-", "—")


def parse(text):
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    sections = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"^## (.+?)\s*$", line)
        if m:
            cur = m.group(1)
            sections[cur] = []
            continue
        if cur is not None:
            sections[cur].append(line)
    return sections


def blocks(lines):
    """`### ID` 區塊 -> {id: {field: value}}（保持順序，偵測重複）。"""
    out, dup, cur = {}, [], None
    for line in lines:
        m = re.match(r"^### (\S+)\s*$", line)
        if m:
            cur = m.group(1)
            if cur in out:
                dup.append(cur)
            out[cur] = {}
            continue
        m = re.match(r"^- ([^:：]+)[:：]\s*(.*?)\s*$", line)
        if m and cur is not None:
            out[cur][m.group(1).strip()] = m.group(2)
    return out, dup


def check_cells(cells, dups, root):
    errs = []
    for d in dups:
        errs.append("%s: 代號重複" % d)
    for cid, c in cells.items():
        def e(msg):
            errs.append("%s: %s" % (cid, msg))
        for k in REQUIRED:
            if k not in c:
                e("缺少欄位「%s」" % k)
            elif c[k] in EMPTY and k not in ("原因類別",):
                e("欄位「%s」為空" % k)
        r = c.get("結果", "")
        if r not in RESULTS:
            e("結果必須是 PASS／FAIL／未執行，實際為 %r" % r)
            continue
        cause = c.get("原因類別", "")
        if r == "未執行":
            if cause not in ("-",):
                e("未執行的格「原因類別」必須為 -")
            if not c.get("觀察", "").startswith("未執行"):
                e("未執行的格「觀察」必須以「未執行」開頭並寫明原因")
            continue
        # PASS / FAIL
        date = c.get("日期", "")
        if not re.match(r"^\d{4}-\d{2}-\d{2}(T[\d:.+\-Z]+)?$", date):
            e("日期必須為 ISO 8601（YYYY-MM-DD 或含時間），實際為 %r" % date)
        if not re.search(r"\d+\.\d+", c.get("macOS", "")):
            e("macOS 欄位必須含 sw_vers 版本號（如 26.5.1），實際為 %r" % c.get("macOS", ""))
        ev = c.get("證據", "")
        paths = [p.strip() for p in re.split(r"[,;]", ev) if p.strip() and p.strip() not in EMPTY]
        if not paths:
            e("缺少證據路徑")
        for p in paths:
            if os.path.isabs(p) or not os.path.exists(os.path.join(root, p)):
                e("證據路徑不存在（須為相對於 spikes/ 的既存檔案）: %s" % p)
        if r == "PASS":
            if cause not in ("-",):
                e("PASS 的「原因類別」必須為 -")
        else:  # FAIL
            if cause not in CAUSES:
                e("FAIL 的「原因類別」必須為 平台限制 或 實作錯誤，實際為 %r" % cause)
            if cause == "平台限制":
                ev2 = c.get("佐證", "")
                if ev2 in EMPTY:
                    e("平台限制 必須附「佐證」說明為何排除是我方錯誤（對照組格代號、日誌中系統回傳值…）")
                for ref in ID_RE.findall(ev2):
                    if ref not in cells:
                        e("佐證引用的格不存在: %s" % ref)
            if cause == "實作錯誤":
                rr = c.get("重跑", "")
                if rr in EMPTY or rr not in cells or rr == cid:
                    e("實作錯誤 不得記為已知限制：須修正實驗程式後重跑，並在「重跑」欄填入重跑格的代號（目前 %r）" % rr)
                else:
                    t = cells[rr]
                    ok = t.get("結果") == "PASS" or (t.get("結果") == "FAIL" and t.get("原因類別") == "平台限制")
                    if not ok:
                        e("重跑格 %s 必須是 PASS 或 FAIL(平台限制)" % rr)
    return errs


def check_decisions(sections, cells):
    errs = []
    if "決定" not in sections:
        return ["缺少「## 決定」章節"]
    d, dups = blocks(sections["決定"])
    for name in ("D1", "D2", "D3"):
        if name not in d:
            errs.append("決定章節缺少 ### %s" % name)
    for name, c in d.items():
        basis = c.get("依據", "")
        refs = [x.strip() for x in re.split(r"[,;]", basis) if x.strip()]
        if not refs:
            errs.append("%s: 缺少「依據」格代號" % name)
        for ref in refs:
            cell = cells.get(ref)
            if cell is None:
                errs.append("%s: 依據的格不存在: %s" % (name, ref))
            elif cell.get("結果") == "未執行":
                errs.append("%s: 依據的格 %s 結果為未執行" % (name, ref))
            elif cell.get("結果") == "FAIL" and cell.get("原因類別") == "實作錯誤":
                errs.append("%s: 實作錯誤 的格 %s 不得作為依據或記為已知限制" % (name, ref))
        if not c.get("內容", "") or c.get("內容") in EMPTY:
            errs.append("%s: 缺少「內容」" % name)
    if "D1" in d:
        if d["D1"].get("內容", "").strip() == "無":
            if not any(cells.get(r.strip(), {}).get("結果") == "PASS" for r in re.split(r"[,;]", d["D1"].get("依據", ""))):
                errs.append("D1: 內容為「無」時，依據必須含至少一個 PASS 格")
    if "D2" in d:
        body = d["D2"].get("內容", "")
        if "screenSaver" in body:
            errs.append("D2: 不得使用 .screenSaver level")
        if not re.search(r"floating|statusBar", body):
            errs.append("D2: 內容必須明列 level（floating 或 statusBar）")
        for r in re.split(r"[,;]", d["D2"].get("依據", "")):
            c = cells.get(r.strip())
            if c and c.get("結果") != "PASS":
                errs.append("D2: 依據格 %s 必須為 PASS（最終組合須是實測通過的組合）" % r.strip())
    if "D3" in d:
        for side in ("A", "B"):
            line = d["D3"].get(side, "")
            for key in ("CPU", "RSS", "WindowServer"):
                if not re.search(r"%s\s*=\s*[\d.]+" % key, line):
                    errs.append("D3: 方案 %s 缺少 %s 數字（格式 `- %s: CPU=1.2 RSS=34000 WindowServer=3.4`）" % (side, key, side))
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?", default="RESULTS.md")
    ap.add_argument("--root", default=None, help="證據路徑的基準目錄（預設為 RESULTS 檔所在目錄）")
    ap.add_argument("--require-decisions", action="store_true")
    a = ap.parse_args()
    if not os.path.isfile(a.file):
        print("RESULTS file not found: %s" % a.file, file=sys.stderr)
        return 2
    root = a.root or os.path.dirname(os.path.abspath(a.file))
    sections = parse(open(a.file, encoding="utf-8").read())
    if "實驗格" not in sections:
        print("ERROR: 缺少「## 實驗格」章節")
        return 1
    cells, dups = blocks(sections["實驗格"])
    errs = check_cells(cells, dups, root)
    if a.require_decisions:
        errs += check_decisions(sections, cells)
    counts = {r: sum(1 for c in cells.values() if c.get("結果") == r) for r in RESULTS}
    print("cells=%d PASS=%d FAIL=%d 未執行=%d%s" % (len(cells), counts["PASS"], counts["FAIL"], counts["未執行"],
                                                  " (含決定完整性檢查)" if a.require_decisions else ""))
    for e in errs:
        print("ERROR: " + e)
    print("RESULT: " + ("FAIL" if errs else "PASS"))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
