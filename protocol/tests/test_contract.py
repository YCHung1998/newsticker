"""契約參考驗證測試。執行：python3 -m unittest discover -s protocol/tests -v"""
import copy
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import refcheck  # noqa: E402
from jsonschema.validators import Draft202012Validator  # noqa: E402

_MISSING = object()
FIXDIR = os.path.join(refcheck.HERE, "fixtures")

# 必要涵蓋類別（見 contract-fixtures spec「fixtures 涵蓋合法與非法樣本」）。
# 這是「涵蓋清單」而非「預期結果」，預期結果仍只來自 manifest。
REQUIRED_COVERAGE = {
    "valid_snapshot_multi", "valid_items_multi", "valid_status_ok", "valid_status_error",
    "valid_cjk", "valid_escapes", "typical_ms",
    "missing_v", "missing_type", "unknown_type", "unsupported_version",
    "item_missing_field", "wrong_type", "bad_state", "empty_items", "mixed_invalid_item",
    "not_json", "oversize", "at_limit",
    "order_snapshot", "order_items", "non_utf8", "extra_field", "empty_text",
    # url（ticker-navigation-link）
    "url_items", "url_snapshot", "url_mixed", "url_max_length",
    "url_js_scheme", "url_ftp_scheme", "url_empty", "url_too_long", "url_null",
    "url_number", "url_relative", "url_has_space", "url_trailing_newline",
}


def integrity_problems(manifest, fixdir=FIXDIR):
    """fixtures 目錄與 manifest 一一對應；回傳問題清單。"""
    problems = []
    listed = {s["file"] for s in manifest["samples"] if "file" in s}
    names = [s["name"] for s in manifest["samples"]]
    if len(names) != len(set(names)):
        problems.append("manifest 有重複 name")
    on_disk = set()
    for d in ("valid", "invalid"):
        for f in os.listdir(os.path.join(fixdir, d)):
            if f.endswith(".jsonl"):
                on_disk.add(d + "/" + f)
    for f in sorted(on_disk - listed):
        problems.append("目錄有但 manifest 未列：" + f)
    for f in sorted(listed - on_disk):
        problems.append("manifest 列了但不存在：" + f)
    return problems


def coverage_problems(manifest):
    have = {c for s in manifest["samples"] for c in s.get("covers", [])}
    return sorted("缺涵蓋類別：" + c for c in REQUIRED_COVERAGE - have)


class SchemaMeta(unittest.TestCase):
    def test_schemas_valid_against_2020_12_metaschema(self):
        for name, s in refcheck.load_schemas().items():
            with self.subTest(schema=name):
                self.assertEqual(s["$schema"], "https://json-schema.org/draft/2020-12/schema")
                Draft202012Validator.check_schema(s)


class ManifestShape(unittest.TestCase):
    def setUp(self):
        self.m = refcheck.load_manifest()

    def test_every_sample_has_expectation_and_reason(self):
        for s in self.m["samples"]:
            with self.subTest(sample=s["name"]):
                self.assertIn(s["expect"], ("accept", "reject"))
                if s["expect"] == "reject":
                    self.assertIn(s.get("reason"), self.m["reasons"])
                else:
                    self.assertNotIn("reason", s)

    def test_max_line_bytes_is_1_MiB(self):
        self.assertEqual(self.m["max_line_bytes"], 1048576)

    def test_fixtures_dir_matches_manifest(self):
        self.assertEqual(integrity_problems(self.m), [])

    def test_integrity_check_detects_deleted_entry(self):
        m = copy.deepcopy(self.m)
        m["samples"] = [s for s in m["samples"] if s["name"] != "status-ok"]
        self.assertTrue(any("status-ok" in p for p in integrity_problems(m)))

    def test_integrity_check_detects_phantom_entry(self):
        m = copy.deepcopy(self.m)
        m["samples"].append({"name": "ghost", "file": "valid/ghost.jsonl", "expect": "accept"})
        self.assertTrue(any("ghost" in p for p in integrity_problems(m)))

    def test_coverage_complete(self):
        self.assertEqual(coverage_problems(self.m), [])

    def test_coverage_check_detects_missing_category(self):
        m = copy.deepcopy(self.m)
        m["samples"] = [s for s in m["samples"] if "bad_state" not in s.get("covers", [])]
        self.assertEqual(coverage_problems(m), ["缺涵蓋類別：bad_state"])


class UrlRules(unittest.TestCase):
    """url 欄位規則（design 決定 1）：直接以參考驗證器逐條斷言，不經 manifest。"""

    def check(self, url):
        item = {"source": "fastbull", "id": "1", "published_at_ms": 1, "text": "x"}
        if url is not _MISSING:
            item["url"] = url
        raw = json.dumps({"v": 1, "type": "items", "items": [item]}).encode("utf-8")
        return refcheck.check_line(raw)[0]

    def test_rules(self):
        cases = [
            (_MISSING, True), ("https://a.example/x", True), ("http://a.example/x", True),
            ("http://[::1]:8080/x", True),
            ("HTTPS://a.example/x", False), ("javascript:alert(1)", False),
            ("ftp://a.example/x", False), ("", False), (None, False), (5, False),
            ("/relative", False), ("https://a b", False), ("https://a.example/\n", False),
            ("https://a.example/\u4e2d", False), ("https:///x", False),
            ("https://" + "a" * (2048 - 8), True), ("https://" + "a" * (2049 - 8), False),
        ]
        for url, want in cases:
            with self.subTest(url=url if not isinstance(url, str) else url[:40] + f"({len(url)})"):
                self.assertEqual(self.check(url), want)


class Samples(unittest.TestCase):
    """manifest 驅動：每個樣本的判定與原因類別必須與 manifest 一致。"""

    def test_all_samples_match_manifest(self):
        m = refcheck.load_manifest()
        validators = refcheck.build_validators()
        for s in m["samples"]:
            with self.subTest(sample=s["name"]):
                raw = refcheck.sample_bytes(s, m["max_line_bytes"])
                ok, reason = refcheck.check_line(raw, validators, m["max_line_bytes"])
                self.assertEqual("accept" if ok else "reject", s["expect"], f"reason={reason}")
                self.assertEqual(reason, s.get("reason"))

    def test_generated_lines_have_exact_sizes(self):
        m = refcheck.load_manifest()
        sizes = {s["name"]: len(refcheck.sample_bytes(s)) for s in m["samples"] if "generate" in s}
        self.assertEqual(sizes, {"generated-at-limit": 1048576, "generated-over-limit": 1048577})

    def test_stream_continues_after_bad_line(self):
        """接收端語意：壞行只影響該行（A、壞、B -> A 與 B 皆被接受）。"""
        v = refcheck.build_validators()
        lines = [refcheck.sample_bytes({"file": "valid/status-ok.jsonl"}),
                 b"garbage",
                 refcheck.sample_bytes({"file": "valid/items-single.jsonl"})]
        self.assertEqual([refcheck.check_line(l, v)[0] for l in lines], [True, False, True])


if __name__ == "__main__":
    unittest.main()
