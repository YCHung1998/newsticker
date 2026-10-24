mod common;
use common::{fixture_html, prod_origin};
use std::collections::HashSet;
use std::time::Duration;
use ticker_connect::connector::Connector;
use ticker_connect::fastbull::{parse_html, FastBullConnector, DEFAULT_INTERVAL, SOURCE_ID};
use ticker_connect::model::{ConnectError, Message};
use ticker_connect::protocol::Protocol;

fn conn() -> FastBullConnector {
    FastBullConnector::new("http://127.0.0.1:1/x", Duration::from_secs(10)).unwrap()
}

#[test]
fn fastbull_parse_snapshot_has_20_unique_items() {
    let items = conn().convert(fixture_html()).unwrap();
    assert_eq!(items.len(), 20);
    let ids: HashSet<_> = items.iter().map(|i| i.id.clone()).collect();
    assert_eq!(ids.len(), 20);
}

#[test]
fn fastbull_parse_first_item_matches_exactly() {
    let items = conn().convert(fixture_html()).unwrap();
    let f = &items[0];
    assert_eq!(f.source, "fastbull");
    assert_eq!(f.id, "4334051_1_2");
    assert_eq!(f.published_at_ms, 1792832201957);
    assert_eq!(f.text, "沙烏地阿拉伯領導的聯軍表示，已攔截並摧毀了也門胡塞武裝向塔伊夫和延布發射的兩枚彈道飛彈。");
}

#[test]
fn fastbull_parse_first_six_ids_and_timestamps() {
    let items = conn().convert(fixture_html()).unwrap();
    let want = [
        ("4334051_1_2", 1792832201957u64),
        ("4334047_212_2", 1792831327830),
        ("4334044_212_2", 1792830528511),
        ("4334043_1_2", 1792830445444),
        ("4334042_1_2", 1792830420009),
        ("4334041_214_2", 1792830328635),
    ];
    for (i, (id, ms)) in want.iter().enumerate() {
        assert_eq!((items[i].id.as_str(), items[i].published_at_ms), (*id, *ms), "index {i}");
    }
}

#[test]
fn fastbull_parse_output_passes_protocol_as_snapshot() {
    let items = conn().convert(fixture_html()).unwrap();
    let p = Protocol::new();
    for it in &items {
        assert_eq!(p.check_item(it), Ok(()), "{}", it.id);
    }
    let line = serde_json::to_vec(&Message::snapshot(items)).unwrap();
    assert_eq!(p.check_line(&line), Ok(()), "snapshot incl. newest-first order check");
}

#[test]
fn fastbull_parse_title_name_outside_news_list_is_not_picked_up() {
    let html = fixture_html();
    assert!(html.matches("class=\"title_name\"").count() > 100, "fixture has many title_name outside news-list");
    let items = conn().convert(html).unwrap();
    assert_eq!(items.len(), 20, "no extra items from other blocks");
}

#[test]
fn fastbull_parse_title_name_is_scoped_to_its_own_element() {
    // 第一個 news-list 沒有自己的 title_name，第二個之後才有；不得借用相鄰或文件其他處的 title_name。
    let html = r#"<span class="title_name">OUTSIDE BEFORE</span><div id="side_fast_news">
      <div class="news-list x" data-id="A" data-date="2"><p>no title here</p></div>
      <div class="news-list x" data-id="B" data-date="1"><span class="title_name">  B text &amp; more </span></div>
      <span class="title_name">OUTSIDE IN SCOPE BUT NOT IN ITEM</span></div>
      <span class="title_name">OUTSIDE AFTER</span>"#;
    let (items, skipped) = parse_html(html, "fastbull");
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].id, "B");
    assert_eq!(items[0].text, "B text & more", "trimmed and entity-decoded (assumption)");
    assert_eq!(skipped.len(), 1);
}

#[test]
fn fastbull_parse_published_at_comes_from_data_date_not_displayed_time() {
    let html = r#"<div id="side_fast_news"><div class="news-list" data-id="X" data-date="1792832201957"><span class="time_value" data-time="5">00:00:01</span><span class="title_name">T</span></div></div>"#;
    let (items, _) = parse_html(html, "fastbull");
    assert_eq!(items[0].published_at_ms, 1792832201957);
    assert_eq!((items[0].id.as_str(), items[0].text.as_str(), items[0].source.as_str()), ("X", "T", "fastbull"));
}

#[test]
fn fastbull_parse_important_flag_does_not_change_fields() {
    let a = r#"<div id="side_fast_news"><div class="news-list important-list" data-id="X" data-date="1"><span class="title_name">T</span></div></div>"#;
    let b = r#"<div id="side_fast_news"><div class="news-list" data-id="X" data-date="1"><span class="title_name">T</span></div></div>"#;
    assert_eq!(parse_html(a, "fastbull").0, parse_html(b, "fastbull").0);
}

#[test]
fn fastbull_parse_zero_items_is_error() {
    let c = conn();
    assert!(matches!(c.convert(String::new()), Err(ConnectError::Parse(_))));
    assert!(c.convert("<html><body>captcha</body></html>".into()).is_err());
}

#[test]
fn fastbull_parse_renamed_class_is_error() {
    let renamed = fixture_html().replace("class=\"news-list ", "class=\"newslist ");
    assert!(conn().convert(renamed).is_err());
}

#[test]
fn fastbull_parse_one_bad_element_is_skipped_not_whole_page() {
    let html = fixture_html().replacen("data-date=\"1792832201957\"", "data-date=\"abc\"", 1);
    let items = conn().convert(html).unwrap();
    assert_eq!(items.len(), 19);
    assert_eq!(items[0].id, "4334047_212_2");
}

#[test]
fn fastbull_parse_all_elements_bad_is_zero_items_error() {
    let html = r#"<div id="side_fast_news"><div class="news-list" data-id="A" data-date="x"><span class="title_name">T</span></div></div>"#;
    assert!(conn().convert(html.into()).is_err());
}

#[test]
fn fastbull_parse_convert_is_pure() {
    let c = conn();
    assert_eq!(c.convert(fixture_html()), c.convert(fixture_html()));
}

#[test]
fn fastbull_parse_identity_and_defaults() {
    let c = FastBullConnector::default_config().unwrap();
    assert_eq!(c.source_id(), SOURCE_ID);
    assert_eq!(c.source_id(), "fastbull");
    assert_eq!(c.interval(), Duration::from_secs(10));
    assert_eq!(DEFAULT_INTERVAL, Duration::from_secs(10));
    assert!(ticker_connect::fastbull::TOTAL_TIMEOUT < DEFAULT_INTERVAL);
}

#[test]
fn fastbull_parse_fixture_has_70_news_list_elements_but_only_the_side_list_is_taken() {
    // 記錄快照的實測事實：整份文件 70 個 div.news-list[data-id]（側欄 20 + 主內容 50），解析只取側欄 20 個。
    let html = fixture_html();
    let doc = scraper::Html::parse_document(&html);
    let all = scraper::Selector::parse("div.news-list[data-id]").unwrap();
    assert_eq!(doc.select(&all).count(), 70);
    assert_eq!(conn().convert(html).unwrap().len(), 20);
}

#[test]
fn fastbull_parse_elements_outside_the_list_scope_are_ignored() {
    let html = r#"<div id="main-content"><div class="news-list" data-id="M" data-date="1"><span class="title_name">M</span></div></div>"#;
    assert!(conn().convert(html.into()).is_err(), "only #side_fast_news counts");
}

// ---- url（ticker-navigation-link 2.1）----

#[test]
fn fastbull_parse_url_first_item_is_origin_plus_data_href() {
    let items = conn().convert(fixture_html()).unwrap();
    assert_eq!(items[0].url.as_deref(), Some(format!("{}/tw/fastshort/4334051_1_2", prod_origin()).as_str()));
}

#[test]
fn fastbull_parse_url_all_20_equal_origin_fastshort_id() {
    let items = conn().convert(fixture_html()).unwrap();
    assert_eq!(items.len(), 20);
    for it in &items {
        assert_eq!(it.url.as_deref(), Some(format!("{}/tw/fastshort/{}", prod_origin(), it.id).as_str()), "{}", it.id);
    }
}

#[test]
fn fastbull_parse_url_output_passes_protocol_as_snapshot() {
    let items = conn().convert(fixture_html()).unwrap();
    let p = Protocol::new();
    for it in &items {
        assert!(it.url.is_some());
        assert_eq!(p.check_item(it), Ok(()), "{}", it.id);
    }
    let line = serde_json::to_vec(&Message::snapshot(items)).unwrap();
    assert_eq!(p.check_line(&line), Ok(()));
    assert!(String::from_utf8(line).unwrap().contains("\"url\":\"https://www."));
}

fn one(inner: &str) -> String {
    format!(r#"<div id="side_fast_news"><div class="news-list" data-id="X" data-date="1"><span class="title_name">T</span>{inner}</div></div>"#)
}

#[test]
fn fastbull_parse_url_takes_first_data_href_in_document_order() {
    let html = one(r#"<div class="shear_box" data-href="/tw/fastshort/first"></div><div data-href="/tw/fastshort/second"></div>"#);
    let (items, skipped) = parse_html(&html, "fastbull");
    assert_eq!(items[0].url.as_deref(), Some(format!("{}/tw/fastshort/first", prod_origin()).as_str()));
    assert!(skipped.is_empty());
}

#[test]
fn fastbull_parse_url_data_href_outside_the_element_is_not_borrowed() {
    let html = r#"<div id="side_fast_news"><div data-href="/tw/fastshort/outside"></div>
      <div class="news-list" data-id="A" data-date="2"><span class="title_name">A</span></div>
      <div class="news-list" data-id="B" data-date="1"><span class="title_name">B</span><div data-href="/tw/fastshort/b"></div></div></div>"#;
    let (items, _) = parse_html(html, "fastbull");
    assert_eq!(items.len(), 2, "item without data-href is still emitted");
    assert_eq!(items[0].url, None);
    assert_eq!(items[1].url.as_deref(), Some(format!("{}/tw/fastshort/b", prod_origin()).as_str()));
}

#[test]
fn fastbull_parse_url_missing_or_bad_data_href_degrades_to_no_url_but_keeps_item() {
    let long = format!("/{}", "a".repeat(2100));
    let bad: Vec<String> = vec![
        "".into(),                           // 空值（index 0 不用）
        "".into(),                           // 空值
        "javascript:alert(1)".into(),
        "//evil.example/x".into(),
        "tw/fastshort/1".into(),             // 不以 / 開頭
        "/tw/a b".into(),                    // 空白
        "/tw/\u{4e2d}".into(),              // 非 ASCII
        "/x\ny".into(),                     // 換行
        long,
    ];
    for (i, v) in bad.iter().enumerate().skip(1) {
        let html = one(&format!(r#"<div data-href="{v}"></div>"#));
        let (items, _) = parse_html(&html, "fastbull");
        assert_eq!(items.len(), 1, "case {i}: item must survive");
        assert_eq!(items[0].url, None, "case {i}: {v:?}");
        let p = Protocol::new();
        assert_eq!(p.check_item(&items[0]), Ok(()), "case {i}: degraded item is valid");
    }
    let (items, _) = parse_html(&one(""), "fastbull");
    assert_eq!((items.len(), items[0].url.clone()), (1, None), "no data-href at all");
}

#[test]
fn fastbull_parse_url_exactly_at_limit_is_kept_and_over_limit_is_dropped() {
    let origin_len = prod_origin().len();
    let at = format!("/{}", "a".repeat(2048 - origin_len - 1));
    let (items, _) = parse_html(&one(&format!(r#"<div data-href="{at}"></div>"#)), "fastbull");
    assert_eq!(items[0].url.as_ref().map(String::len), Some(2048));
    let over = format!("{at}a");
    let (items, _) = parse_html(&one(&format!(r#"<div data-href="{over}"></div>"#)), "fastbull");
    assert_eq!(items[0].url, None);
}

#[test]
fn fastbull_parse_url_bad_data_href_writes_stderr_note_via_skipped_free_path() {
    // convert 對壞 data-href 不得回錯（item 照常輸出）。
    let html = one(r#"<div data-href="javascript:x"></div>"#);
    let items = conn().convert(html).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].url, None);
}

#[test]
fn fastbull_parse_url_origin_is_constant_not_derived_from_fetch_target() {
    let c = FastBullConnector::new("http://127.0.0.1:9/whatever", Duration::from_secs(10)).unwrap();
    let items = c.convert(fixture_html()).unwrap();
    assert!(items[0].url.as_deref().unwrap().starts_with(&prod_origin()));
    assert!(!items[0].url.as_deref().unwrap().contains("127.0.0.1"));
}
