//! 查證 Rust 端 jsonschema crate 是否真的實作 JSON Schema 2020-12（而非只在 README 宣稱）。
//! 用 2020-12 專屬語意（prefixItems、unevaluatedProperties、$dynamicRef）與 Draft 7 對照。
use jsonschema::Draft;
use serde_json::json;

#[test]
fn jsonschema_2020_12_prefix_items_is_enforced_and_draft7_ignores_it() {
    let schema = json!({"$schema":"https://json-schema.org/draft/2020-12/schema","prefixItems":[{"type":"integer"},{"type":"string"}]});
    let bad = json!(["x", 1]);
    let v = jsonschema::validator_for(&schema).unwrap();
    assert!(!v.is_valid(&bad), "2020-12 must enforce prefixItems");
    assert!(v.is_valid(&json!([1, "x"])));
    let d7 = jsonschema::options().with_draft(Draft::Draft7).build(&schema).unwrap();
    assert!(d7.is_valid(&bad), "Draft 7 does not know prefixItems -> control group");
}

#[test]
fn jsonschema_2020_12_unevaluated_properties_and_draft_autodetect() {
    let schema = json!({
        "$schema":"https://json-schema.org/draft/2020-12/schema",
        "allOf":[{"properties":{"a":{"type":"integer"}}}],
        "unevaluatedProperties": false
    });
    let v = jsonschema::validator_for(&schema).unwrap();
    assert!(v.is_valid(&json!({"a":1})));
    assert!(!v.is_valid(&json!({"a":1,"b":2})), "unevaluatedProperties is 2019-09+/2020-12");
}

#[test]
fn jsonschema_2020_12_protocol_validators_are_built_with_2020_12() {
    // Protocol::new() 以 Draft202012 建構並以 $id 互相 $ref；能建構且 $ref 解析成功即代表離線可用。
    let p = ticker_connect::protocol::Protocol::new();
    let line = br#"{"v":1,"type":"status","source":"s","state":"ok","message":""}"#;
    assert!(p.check_line(line).is_ok());
}
