//! 端到端：binary 對本機假伺服器跑完整流程（快照 -> 新快訊 -> 失敗 -> 恢復），全程不連外網。
mod common;
use common::*;
use std::time::Duration;
use ticker_connect::protocol::Protocol;

const T: Duration = Duration::from_secs(10);

/// 在 fixture 的側欄清單最前面插入一則更新的快訊。
fn with_new_item(html: &str) -> String {
    let marker = "<div class=\"news-list content-list-4334051_1_2";
    assert!(html.contains(marker));
    let fresh = "<div class=\"news-list content-list-9999999_1_2 preview-content-list\" data-id=\"9999999_1_2\" data-date=\"1792832999999\"><div class=\"news-list-content\"><p class=\"content-title\"><span class=\"title_name\">E2E 新快訊</span></p></div></div>";
    html.replacen(marker, &format!("{fresh}{marker}"), 1)
}

#[test]
fn e2e_local_snapshot_then_items_then_error_then_recovery_without_resending() {
    let base = fixture_html();
    let server = FakeServer::start(Mode::Body(base.clone()));
    let mut h = spawn_helper(&server.url, 100, 300);

    // 1. snapshot（20 則，新到舊）
    let snap = h.wait_for("snapshot", T, |v| v["type"] == "snapshot");
    assert_eq!(snap["items"].as_array().unwrap().len(), 20);
    assert_eq!(snap["items"][0]["id"], "4334051_1_2");
    assert_eq!(snap["items"][0]["source"], "fastbull");

    // 2. 新增一則 -> items（只含新的）
    server.set(Mode::Body(with_new_item(&base)));
    let items = h.wait_for("items", T, |v| v["type"] == "items");
    assert_eq!(items["items"].as_array().unwrap().len(), 1);
    assert_eq!(items["items"][0]["id"], "9999999_1_2");
    assert_eq!(items["items"][0]["text"], "E2E 新快訊");

    // 3. 伺服器失敗 -> status error
    server.set(Mode::Status(500));
    let err = h.wait_for("status error", T, |v| v["type"] == "status" && v["state"] == "error");
    assert!(err["message"].as_str().unwrap().contains("500"));

    // 4. 恢復（含那則新快訊的同一頁）-> 不得重發任何舊訊息
    let before = h.all.len();
    server.set(Mode::Body(with_new_item(&base)));
    h.wait_for("status ok after recovery", T, |v| v["type"] == "status" && v["state"] == "ok");
    h.drain_for(Duration::from_millis(1500));
    for l in &h.all[before..] {
        let v: serde_json::Value = serde_json::from_str(l).unwrap();
        assert_eq!(v["type"], "status", "after recovery nothing but status lines expected, got {l}");
    }

    // 全程：stdout 每行合法、且順序為 snapshot < items < error
    let p = Protocol::new();
    let kinds: Vec<(String, String)> = h
        .all
        .iter()
        .map(|l| {
            assert_eq!(p.check_line(l.as_bytes()), Ok(()), "{l}");
            let v: serde_json::Value = serde_json::from_str(l).unwrap();
            (v["type"].as_str().unwrap().to_string(), v["state"].as_str().unwrap_or("").to_string())
        })
        .collect();
    let pos = |t: &str, st: &str| kinds.iter().position(|(a, b)| a == t && (st.is_empty() || b == st)).unwrap();
    assert!(pos("snapshot", "") < pos("items", ""));
    assert!(pos("items", "") < pos("status", "error"));
    assert_eq!(kinds.iter().filter(|(t, _)| t == "snapshot").count(), 1, "exactly one snapshot");
    assert_eq!(kinds.iter().filter(|(t, _)| t == "items").count(), 1, "exactly one items");
}
