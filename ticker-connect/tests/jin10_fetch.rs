//! jin10 抓取與端到端測試（由 docs/templates/source_fetch_test.rs.tmpl 產生）。只連本機假伺服器 127.0.0.1。
//! 測試原始碼不得出現正式網域字面值（守衛會掃描）；路徑可寫，網域不可。
mod common;
use common::*;
use std::time::Duration;
use ticker_connect::connector::Connector;
use ticker_connect::model::ConnectError;
use ticker_connect::jin10::Jin10Connector;

const PATH: &str = "/get_flash_list?channel=-8200&vip=1";

fn conn(url: &str) -> Jin10Connector {
    assert_local(url);
    Jin10Connector::new(url, Duration::from_secs(10)).unwrap()
}

#[tokio::test]
async fn jin10_fetch_200_body_converts_to_items() {
    let s = FakeServer::start(Mode::Body(fixture("jin10", "sample.json")));
    let c = conn(&s.url_for(PATH));
    let items = c.convert(c.fetch().await.unwrap()).unwrap();
    assert_eq!(items.len(), 5);
    let reqs = s.requests.lock().unwrap();
    assert!(reqs[0].starts_with(&format!("GET {PATH} ")), "{}", reqs[0]);
}

#[tokio::test]
async fn jin10_fetch_non_200_is_error() {
    for code in [403u16, 429, 500] {
        let s = FakeServer::start(Mode::Status(code));
        assert_eq!(conn(&s.url_for(PATH)).fetch().await.unwrap_err(), ConnectError::HttpStatus(code));
    }
}

/// 同時驗證「來源已登錄」：`--source jin10` 找不到來源時 helper 會以退出碼 2 結束，等不到 snapshot。
#[test]
fn jin10_e2e_helper_emits_snapshot_for_the_registered_source() {
    let s = FakeServer::start(Mode::Body(fixture("jin10", "sample.json")));
    let mut h = spawn_helper_with(&["--source", "jin10"], &s.url_for(PATH), 100, 300);
    let snap = h.wait_for("snapshot", Duration::from_secs(10), |v| v["type"] == "snapshot");
    assert_eq!(snap["items"].as_array().unwrap().len(), 5);
    assert_eq!(snap["items"][0]["source"], "jin10");
}
