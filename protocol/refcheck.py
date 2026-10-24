"""參考驗證器：以 JSON Schema 2020-12（Python jsonschema）加上 schema 無法表達的額外檢查，
判定「一行」輸入是否合法。manifest 是預期結果的唯一來源，本檔只負責判定。

check_line(raw) -> (accept: bool, reason: str | None)
reason 類別：not_json、schema、version、oversize、order。
判定順序：大小 -> UTF-8 -> JSON -> 版本 -> schema -> 順序。
"""
import json
import os

from jsonschema.validators import Draft202012Validator
from referencing import Registry, Resource

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_DIR = os.path.join(HERE, "schema")
SCHEMA_NAMES = ["item", "snapshot", "items", "status"]
SUPPORTED_VERSION = 1


def load_schemas():
    out = {}
    for n in SCHEMA_NAMES:
        with open(os.path.join(SCHEMA_DIR, n + ".schema.json"), encoding="utf-8") as f:
            out[n] = json.load(f)
    return out


def build_validators(schemas=None):
    schemas = schemas or load_schemas()
    registry = Registry().with_resources(
        [(s["$id"], Resource.from_contents(s)) for s in schemas.values()]
    )
    return {n: Draft202012Validator(s, registry=registry) for n, s in schemas.items()}


def load_manifest():
    with open(os.path.join(HERE, "fixtures", "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def _reject_constant(name):
    raise ValueError("non-standard JSON constant " + name)


def _order_ok(msg):
    ms = [i["published_at_ms"] for i in msg["items"]]
    pairs = list(zip(ms, ms[1:]))
    if msg["type"] == "snapshot":  # 新到舊：非遞增（同毫秒允許）
        return all(a >= b for a, b in pairs)
    return all(a <= b for a, b in pairs)  # items：舊到新：非遞減


def check_line(raw, validators=None, max_bytes=1048576, order_check=True):
    """raw 為不含結尾換行的位元組。"""
    validators = validators or build_validators()
    if len(raw) > max_bytes:
        return False, "oversize"
    try:
        text = raw.decode("utf-8")
        msg = json.loads(text, parse_constant=_reject_constant)
    except (UnicodeDecodeError, ValueError):
        return False, "not_json"
    if isinstance(msg, dict):
        v = msg.get("v")
        if type(v) is int and v != SUPPORTED_VERSION:
            return False, "version"
    t = msg.get("type") if isinstance(msg, dict) else None
    if t not in ("snapshot", "items", "status"):
        return False, "schema"
    if next(validators[t].iter_errors(msg), None) is not None:
        return False, "schema"
    if order_check and t in ("snapshot", "items") and not _order_ok(msg):
        return False, "order"
    return True, None


def generate_line(spec, max_bytes=1048576):
    """程式產生超大行：合法的 items 訊息，以 ASCII 補長 text，使整行恰為指定位元組數。"""
    total = {"limit": max_bytes, "limit+1": max_bytes + 1}[spec["total_bytes"]]
    base = {"v": 1, "type": "items", "items": [{"source": "fastbull", "id": "1", "published_at_ms": 1761292800000, "text": ""}]}
    def enc(pad):
        base["items"][0]["text"] = "a" * pad
        return json.dumps(base, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    pad = total - len(enc(0))
    out = enc(pad)
    assert len(out) == total
    return out


def sample_bytes(sample, max_bytes=1048576):
    """取得樣本的原始一行（不含結尾換行）。"""
    if "generate" in sample:
        return generate_line(sample["generate"], max_bytes)
    with open(os.path.join(HERE, "fixtures", sample["file"]), "rb") as f:
        data = f.read()
    assert data.endswith(b"\n") and data.count(b"\n") == 1, sample["file"] + " 必須恰為一行"
    return data[:-1]
