//! jin10 解析測試（由 docs/templates/source_parse_test.rs.tmpl 產生）。fixture：tests/fixtures/jin10/sample.json。
mod common;
use common::fixture;
use std::collections::HashSet;
use std::time::Duration;
use ticker_connect::connector::Connector;
use ticker_connect::model::{ConnectError, Message};
use ticker_connect::protocol::Protocol;
use ticker_connect::jin10::{parse_payload, Jin10Connector, DEFAULT_INTERVAL, SOURCE_ID};

fn conn() -> Jin10Connector {
    Jin10Connector::new("http://127.0.0.1:1/x", Duration::from_secs(10)).unwrap()
}

#[test]
fn jin10_parse_fixture_items_are_unique_and_newest_first() {
    let items = conn().convert(fixture("jin10", "sample.json")).unwrap();
    // fixture 8 筆：1 筆 PLUS 鎖定(空內容)、2 筆廣告 => 5 則有效
    assert_eq!(items.len(), 5);
    let ids: HashSet<_> = items.iter().map(|i| i.id.clone()).collect();
    assert_eq!(ids.len(), items.len(), "ids must be unique");
    assert!(items.windows(2).all(|w| w[0].published_at_ms >= w[1].published_at_ms), "newest first");
}

#[test]
fn jin10_parse_first_item_matches_exactly() {
    let f = &conn().convert(fixture("jin10", "sample.json")).unwrap()[0];
    assert_eq!(f.source, SOURCE_ID);
    assert_eq!(f.id, "20261025201806546800");
    // 2026-10-25 20:18:06 UTC+8 = 12:18:06Z
    assert_eq!(f.published_at_ms, 1_792_930_686_000);
    assert!(f.published_at_ms > 1_000_000_000_000);
    assert!(f.text.starts_with("【武契奇：以负责任的态度面对选举结果】金十数据10月25日讯"), "{}", f.text);
    assert!(f.text.ends_with("可大致判断哪一方获胜。"), "{}", f.text);
    assert_eq!(f.url.as_deref(), Some("https://baijiahao.baidu.com/s?id=1880024004742377689"));
}

#[test]
fn jin10_parse_output_passes_protocol_as_snapshot() {
    let items = conn().convert(fixture("jin10", "sample.json")).unwrap();
    let p = Protocol::new();
    for it in &items {
        assert_eq!(p.check_item(it), Ok(()), "{}", it.id);
    }
    let line = serde_json::to_vec(&Message::snapshot(items)).unwrap();
    assert_eq!(p.check_line(&line), Ok(()));
}

#[test]
fn jin10_parse_zero_items_is_error_not_no_news() {
    let c = conn();
    for bad in ["", "not json", "{}", "{\"data\":[]}", "<html>captcha</html>"] {
        assert!(matches!(c.convert(bad.into()), Err(ConnectError::Parse(_))), "{bad:?}");
    }
}

#[test]
fn jin10_parse_one_bad_element_is_skipped_not_whole_page() {
    let raw = fixture("jin10", "sample.json").replacen("2026-10-25 20:18:06", "oops", 1);
    let (items, skipped) = parse_payload(&raw, SOURCE_ID);
    assert_eq!(items.len(), 4);
    assert!(skipped.iter().any(|s| s.contains("20261025201806546800")), "{skipped:?}");
}

#[test]
fn jin10_parse_convert_is_pure_and_identity_is_registered_shape() {
    let c = conn();
    assert_eq!(c.convert(fixture("jin10", "sample.json")), c.convert(fixture("jin10", "sample.json")));
    assert_eq!(c.source_id(), SOURCE_ID);
    assert!(DEFAULT_INTERVAL >= Duration::from_secs(10));
}

#[test]
fn jin10_parse_skips_locked_and_ads_and_keeps_order() {
    let items = conn().convert(fixture("jin10", "sample.json")).unwrap();
    let ids: Vec<_> = items.iter().map(|i| i.id.as_str()).collect();
    assert_eq!(
        ids,
        ["20261025201806546800", "20261025195824709800", "20261025193943725800", "20261025190439645800", "20261025190343103800"]
    );
}

#[test]
fn jin10_parse_overlong_source_link_degrades_to_no_url() {
    // fixture 第 2 則的 source_link 369 位元組合法 => 保留；另造一個 > 2048 位元組者 => url 降級為 None，item 保留。
    let items = conn().convert(fixture("jin10", "sample.json")).unwrap();
    assert!(items[1].url.is_some());
    let long = format!("https://a.example/{}", "x".repeat(2100));
    let raw = format!(
        r#"{{"status":200,"data":[{{"id":"1","time":"2026-10-25 20:18:06","extras":{{"ad":false}},"data":{{"content":"hi","source_link":"{long}"}}}}]}}"#
    );
    let (items, skipped) = parse_payload(&raw, SOURCE_ID);
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].url, None);
    assert!(!skipped.is_empty());
}

#[test]
fn jin10_parse_strips_html_and_collapses_whitespace() {
    let raw = r#"{"data":[{"id":"1","time":"2026-10-25 20:18:06","extras":{"ad":false},"data":{"content":"  A<b>B</b>&nbsp;&amp;\n\n C<br/>D  "}}]}"#;
    let (items, _) = parse_payload(raw, SOURCE_ID);
    assert_eq!(items[0].text, "AB & C D");
}
