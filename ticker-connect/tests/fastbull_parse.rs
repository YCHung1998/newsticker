mod common;
use common::fixture_html;
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
