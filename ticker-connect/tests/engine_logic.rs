mod common;
use common::item;
use ticker_connect::engine::{Engine, EngineConfig};
use ticker_connect::model::{ConnectError, Item, Message, State};

fn engine() -> Engine {
    Engine::new("fake", EngineConfig::default())
}
fn ids(items: &[Item]) -> Vec<&str> {
    items.iter().map(|i| i.id.as_str()).collect()
}
fn only_items(msgs: &[Message]) -> Vec<&str> {
    match msgs {
        [Message::Items { items, .. }] => ids(items),
        other => panic!("expected exactly one items message, got {other:?}"),
    }
}

// ---------- 1.2 dedup ----------
#[test]
fn dedup_first_poll_is_snapshot_newest_first_and_fills_seen() {
    let mut e = engine();
    let o = e.on_poll(Ok(vec![item("e", 5), item("d", 4), item("c", 3), item("b", 2), item("a", 1)]));
    match &o.messages[..] {
        [Message::Snapshot { items, .. }] => assert_eq!(ids(items), ["e", "d", "c", "b", "a"]),
        other => panic!("{other:?}"),
    }
    assert_eq!(e.seen_len(), 5);
}

#[test]
fn dedup_only_new_items_are_emitted() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("c", 3), item("b", 2), item("a", 1)]));
    let o = e.on_poll(Ok(vec![item("d", 4), item("c", 3), item("b", 2), item("a", 1)]));
    assert_eq!(only_items(&o.messages), ["d"]);
    assert!(e.has_seen("d"));
}

#[test]
fn dedup_multiple_new_items_are_oldest_first() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("a", 1)]));
    let o = e.on_poll(Ok(vec![item("e", 5), item("d", 4), item("a", 1)]));
    assert_eq!(only_items(&o.messages), ["d", "e"]);
}

#[test]
fn dedup_no_new_items_emits_nothing() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("b", 2), item("a", 1)]));
    let o = e.on_poll(Ok(vec![item("b", 2), item("a", 1)]));
    assert!(o.ok);
    assert!(o.messages.is_empty(), "no items/snapshot and never an empty items");
}

#[test]
fn dedup_equal_timestamps_tiebreak_is_reverse_page_order() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("a", 1)]));
    // 頁面順序 z, y, x（新到舊，時間相同）-> 舊到新時為頁面順序的反向：x, y, z
    let o = e.on_poll(Ok(vec![item("z", 7), item("y", 7), item("x", 7), item("a", 1)]));
    assert_eq!(only_items(&o.messages), ["x", "y", "z"]);
}

#[test]
fn dedup_duplicate_ids_in_one_page_are_collapsed() {
    let mut e = engine();
    let o = e.on_poll(Ok(vec![item("a", 2), item("a", 2), item("b", 1)]));
    match &o.messages[..] {
        [Message::Snapshot { items, .. }] => assert_eq!(ids(items), ["a", "b"]),
        other => panic!("{other:?}"),
    }
}

#[test]
fn dedup_seen_capacity_evicts_oldest_added() {
    let mut e = Engine::new("fake", EngineConfig { flood_threshold: 10, seen_capacity: 3 });
    e.on_poll(Ok(vec![item("a", 1)]));
    for (n, id) in ["b", "c", "d", "e"].iter().enumerate() {
        e.on_poll(Ok(vec![item(id, 2 + n as u64)]));
    }
    assert_eq!(e.seen_len(), 3);
    assert!(!e.has_seen("a") && !e.has_seen("b"), "oldest added are evicted");
    assert!(e.has_seen("c") && e.has_seen("d") && e.has_seen("e"));
}

// ---------- 1.3 snapshot / flood ----------
#[test]
fn snapshot_flood_exactly_threshold_is_items() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("seed", 1)]));
    let page: Vec<Item> = (0..10).rev().map(|n| item(&format!("n{n}"), 100 + n)).chain([item("seed", 1)]).collect();
    let o = e.on_poll(Ok(page));
    assert_eq!(only_items(&o.messages).len(), 10);
}

#[test]
fn snapshot_flood_over_threshold_resets_baseline_with_snapshot() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("seed", 1)]));
    let page: Vec<Item> = (0..11).rev().map(|n| item(&format!("n{n}"), 100 + n)).chain([item("seed", 1)]).collect();
    let o = e.on_poll(Ok(page));
    match &o.messages[..] {
        [Message::Snapshot { items, .. }] => {
            assert_eq!(items.len(), 12, "whole converted page (assumption)");
            assert_eq!(items[0].id, "n10", "newest first");
        }
        other => panic!("expected snapshot, got {other:?}"),
    }
    assert!(e.has_seen("n0") && e.has_seen("n10"));
    // 之後同一頁不再重發
    let again: Vec<Item> = (0..11).rev().map(|n| item(&format!("n{n}"), 100 + n)).chain([item("seed", 1)]).collect();
    assert!(e.on_poll(Ok(again)).messages.is_empty());
}

#[test]
fn snapshot_flood_threshold_is_configurable() {
    let mut e = Engine::new("fake", EngineConfig { flood_threshold: 2, seen_capacity: 500 });
    e.on_poll(Ok(vec![item("seed", 1)]));
    let o = e.on_poll(Ok(vec![item("c", 4), item("b", 3), item("a", 2), item("seed", 1)]));
    assert!(matches!(&o.messages[..], [Message::Snapshot { .. }]));
}

#[test]
fn snapshot_flood_first_success_after_failure_is_snapshot() {
    let mut e = engine();
    let o = e.on_poll(Err(ConnectError::HttpStatus(500)));
    assert!(!o.ok);
    assert!(!e.snapshot_sent());
    let o = e.on_poll(Ok(vec![item("a", 1)]));
    assert!(matches!(&o.messages[..], [Message::Snapshot { .. }]));
}

#[test]
fn snapshot_flood_snapshot_is_sorted_even_if_page_order_is_not() {
    let mut e = engine();
    let o = e.on_poll(Ok(vec![item("old", 1), item("new", 9)]));
    match &o.messages[..] {
        [Message::Snapshot { items, .. }] => assert_eq!(ids(items), ["new", "old"]),
        other => panic!("{other:?}"),
    }
}

// ---------- 1.4 errors keep state ----------
fn status_error(o: &ticker_connect::engine::PollOutcome) {
    assert!(!o.ok);
    match &o.messages[..] {
        [Message::Status { state: State::Error, source, message, .. }] => {
            assert_eq!(source, "fake");
            assert!(!message.is_empty());
        }
        other => panic!("expected one status error, got {other:?}"),
    }
}

#[test]
fn error_keeps_state_parse_zero_items_is_error_not_no_news() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("b", 2), item("a", 1)]));
    let before = e.seen_len();
    let o = e.on_poll(Ok(vec![]));
    status_error(&o);
    assert_eq!(e.seen_len(), before);
    assert!(e.snapshot_sent());
}

#[test]
fn error_keeps_state_fetch_failure_then_recovery_does_not_resend_old() {
    let mut e = engine();
    e.on_poll(Ok(vec![item("b", 2), item("a", 1)]));
    status_error(&e.on_poll(Err(ConnectError::Fetch("boom".into()))));
    status_error(&e.on_poll(Err(ConnectError::HttpStatus(429))));
    let o = e.on_poll(Ok(vec![item("c", 3), item("b", 2), item("a", 1)]));
    assert_eq!(only_items(&o.messages), ["c"]);
}

#[test]
fn error_keeps_state_first_poll_zero_items_then_success_still_snapshot() {
    let mut e = engine();
    status_error(&e.on_poll(Ok(vec![])));
    assert!(!e.snapshot_sent() && e.seen_len() == 0);
    let o = e.on_poll(Ok(vec![item("a", 1)]));
    assert!(matches!(&o.messages[..], [Message::Snapshot { .. }]));
}

#[test]
fn error_keeps_state_convert_error_is_error() {
    let mut e = engine();
    status_error(&e.on_poll(Err(ConnectError::Parse("x".into()))));
}
