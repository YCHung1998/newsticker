//! 跨語言契約測試：直接讀 protocol/fixtures/manifest.json（不複製副本、不另寫預期），
//! 與 Python 參考驗證器（protocol/refcheck.py）結論一致。
mod common;
use common::*;
use serde_json::Value;
use ticker_connect::emitter::Emitter;
use ticker_connect::model::Message;
use ticker_connect::protocol::{Protocol, Reason};

fn manifest() -> Value {
    let s = std::fs::read_to_string(format!("{ROOT}/../protocol/fixtures/manifest.json")).unwrap();
    serde_json::from_str(&s).unwrap()
}

/// 與 refcheck.generate_line 相同：合法 items，ASCII text 補到恰好指定位元組數。
fn generate(spec: &Value, max: usize) -> Vec<u8> {
    assert_eq!(spec["kind"], "padded_items");
    let total = match spec["total_bytes"].as_str().unwrap() {
        "limit" => max,
        "limit+1" => max + 1,
        other => panic!("unknown total_bytes {other}"),
    };
    let enc = |pad: usize| {
        format!(
            r#"{{"v":1,"type":"items","items":[{{"source":"fastbull","id":"1","published_at_ms":1761292800000,"text":"{}"}}]}}"#,
            "a".repeat(pad)
        )
        .into_bytes()
    };
    let out = enc(total - enc(0).len());
    assert_eq!(out.len(), total);
    out
}

fn sample_bytes(s: &Value, max: usize) -> Vec<u8> {
    if let Some(g) = s.get("generate") {
        return generate(g, max);
    }
    let data = std::fs::read(format!("{ROOT}/../protocol/fixtures/{}", s["file"].as_str().unwrap())).unwrap();
    assert!(data.ends_with(b"\n") && data.iter().filter(|b| **b == b'\n').count() == 1, "must be exactly one line");
    data[..data.len() - 1].to_vec()
}

fn reason_of(name: &str) -> Reason {
    match name {
        "not_json" => Reason::NotJson,
        "schema" => Reason::Schema,
        "version" => Reason::Version,
        "oversize" => Reason::Oversize,
        "order" => Reason::Order,
        other => panic!("unknown reason {other}"),
    }
}

#[test]
fn emitter_contract_all_manifest_samples_match_reference_verdict() {
    let m = manifest();
    let max = m["max_line_bytes"].as_u64().unwrap() as usize;
    assert_eq!(max, ticker_connect::protocol::MAX_LINE_BYTES);
    let p = Protocol::new();
    let samples = m["samples"].as_array().unwrap();
    assert!(samples.len() >= 40, "manifest unexpectedly small: {}", samples.len());
    let (mut accepts, mut rejects) = (0, 0);
    for s in samples {
        let name = s["name"].as_str().unwrap();
        let bytes = sample_bytes(s, max);
        let got = p.check_line(&bytes);
        match s["expect"].as_str().unwrap() {
            "accept" => {
                accepts += 1;
                assert_eq!(got, Ok(()), "sample {name} should be accepted");
            }
            "reject" => {
                rejects += 1;
                let want = reason_of(s["reason"].as_str().unwrap());
                assert_eq!(got, Err(want), "sample {name} should be rejected as {want:?}");
            }
            other => panic!("bad expect {other}"),
        }
    }
    assert!(accepts > 0 && rejects > 0);
}

#[test]
fn emitter_contract_accept_samples_roundtrip_through_types_and_emitter() {
    let m = manifest();
    let max = m["max_line_bytes"].as_u64().unwrap() as usize;
    let p = Protocol::new();
    for s in m["samples"].as_array().unwrap().iter().filter(|s| s["expect"] == "accept") {
        let name = s["name"].as_str().unwrap();
        let bytes = sample_bytes(s, max);
        let msg: Message = serde_json::from_slice(&bytes).unwrap_or_else(|e| panic!("{name}: {e}"));
        let again = serde_json::to_vec(&msg).unwrap();
        assert_eq!(p.check_line(&again), Ok(()), "{name}: re-serialized message must still pass");
        // 經 emitter 輸出：應恰好輸出一行、且內容語意不變。
        let buf = SharedBuf::default();
        let mut em = Emitter::new(buf.clone(), "fastbull");
        em.emit(msg.clone()).unwrap();
        let lines = buf.lines();
        assert_eq!(lines.len(), 1, "{name}");
        let back: Message = serde_json::from_value(lines[0].clone()).unwrap();
        assert_eq!(back, msg, "{name}");
    }
}

#[test]
fn emitter_contract_every_line_written_is_valid_even_for_reject_samples() {
    // 對可反序列化成型別的 reject 樣本（例如混有非法 item、順序錯），emitter 不得輸出任何不合格的行。
    let m = manifest();
    let max = m["max_line_bytes"].as_u64().unwrap() as usize;
    let p = Protocol::new();
    let mut exercised = 0;
    for s in m["samples"].as_array().unwrap().iter().filter(|s| s["expect"] == "reject") {
        let name = s["name"].as_str().unwrap();
        let bytes = sample_bytes(s, max);
        let Ok(msg) = serde_json::from_slice::<Message>(&bytes) else { continue };
        exercised += 1;
        let buf = SharedBuf::default();
        let mut em = Emitter::new(buf.clone(), "fastbull");
        em.emit(msg).unwrap();
        let raw = buf.raw();
        for line in raw.split(|b| *b == b'\n').filter(|l| !l.is_empty()) {
            assert_eq!(p.check_line(line), Ok(()), "{name}: emitter wrote an invalid line");
        }
    }
    assert!(exercised >= 4, "expected several type-parsable reject samples, got {exercised}");
}

#[test]
fn emitter_filter_drops_bad_items_and_warns_with_status_error() {
    let buf = SharedBuf::default();
    let mut em = Emitter::new(buf.clone(), "fake");
    let mut bad = item("", 5);
    bad.id = String::new();
    let rep = em.emit(Message::items(vec![item("a", 1), bad, item("b", 2)])).unwrap();
    assert!(rep.wrote_data && rep.wrote_status);
    let lines = buf.lines();
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0]["type"], "items");
    let ids: Vec<&str> = lines[0]["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap()).collect();
    assert_eq!(ids, ["a", "b"]);
    assert_eq!(lines[1]["type"], "status");
    assert_eq!(lines[1]["state"], "error");
    assert!(lines[1]["message"].as_str().unwrap().contains("dropped 1 invalid item"));
}

#[test]
fn emitter_filter_never_sends_empty_items_or_snapshot() {
    for snapshot in [false, true] {
        let buf = SharedBuf::default();
        let mut em = Emitter::new(buf.clone(), "fake");
        let mut bad = item("x", 1);
        bad.text = String::new();
        let msg = if snapshot { Message::snapshot(vec![bad.clone()]) } else { Message::items(vec![bad.clone()]) };
        let rep = em.emit(msg).unwrap();
        assert!(!rep.wrote_data && rep.wrote_status);
        let lines = buf.lines();
        assert_eq!(lines.len(), 1, "only a warning status");
        assert_eq!(lines[0]["type"], "status");
        assert_eq!(lines[0]["state"], "error");
    }
}

#[test]
fn emitter_oversize_line_is_not_written_and_warns() {
    let buf = SharedBuf::default();
    let mut em = Emitter::new(buf.clone(), "fake");
    let mut big = item("big", 1);
    big.text = "a".repeat(ticker_connect::protocol::MAX_LINE_BYTES);
    let rep = em.emit(Message::items(vec![big])).unwrap();
    assert!(!rep.wrote_data && rep.wrote_status);
    let lines = buf.lines();
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0]["type"], "status");
    assert!(lines[0]["message"].as_str().unwrap().contains("oversize"));
}

#[test]
fn emitter_wrong_order_message_is_not_written() {
    let buf = SharedBuf::default();
    let mut em = Emitter::new(buf.clone(), "fake");
    // items 必須舊到新；給新到舊 -> order 違規，不得輸出。
    let rep = em.emit(Message::items(vec![item("n", 9), item("o", 1)])).unwrap();
    assert!(!rep.wrote_data && rep.wrote_status);
    assert_eq!(buf.lines().len(), 1);
}
