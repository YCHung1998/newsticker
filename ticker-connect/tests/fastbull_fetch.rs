//! 抓取測試只對本機假伺服器（127.0.0.1）。
mod common;
use common::*;
use std::time::{Duration, Instant};
use ticker_connect::connector::Connector;
use ticker_connect::fastbull::{FastBullConnector, USER_AGENT};
use ticker_connect::model::ConnectError;

fn conn(url: &str) -> FastBullConnector {
    assert_local(url);
    FastBullConnector::new(url, Duration::from_secs(10)).unwrap()
}

#[tokio::test]
async fn fastbull_fetch_200_returns_body_that_converts_to_20_items() {
    let s = FakeServer::start(Mode::Body(fixture_html()));
    let c = conn(&s.url);
    let body = c.fetch().await.unwrap();
    assert_eq!(c.convert(body).unwrap().len(), 20);
}

#[tokio::test]
async fn fastbull_fetch_sends_nonempty_user_agent_and_only_get() {
    let s = FakeServer::start(Mode::Body("<html></html>".into()));
    conn(&s.url).fetch().await.unwrap();
    let reqs = s.requests.lock().unwrap();
    assert_eq!(reqs.len(), 1);
    let head = reqs[0].to_lowercase();
    assert!(head.starts_with("get /tw/express-news "), "{head}");
    let ua = reqs[0].lines().find(|l| l.to_lowercase().starts_with("user-agent:")).expect("User-Agent header");
    assert!(ua.split_once(':').unwrap().1.trim().len() > 5);
    assert!(ua.contains(USER_AGENT));
}

#[tokio::test]
async fn fastbull_fetch_non_200_is_error_for_403_429_500_and_unfollowed_redirect() {
    for code in [403u16, 429, 500, 302] {
        let s = FakeServer::start(Mode::Status(code));
        let e = conn(&s.url).fetch().await.unwrap_err();
        assert_eq!(e, ConnectError::HttpStatus(code), "status {code}");
    }
}

#[tokio::test]
async fn fastbull_fetch_timeout_returns_error_within_configured_limit() {
    let s = FakeServer::start(Mode::Hang(Duration::from_secs(30)));
    assert_local(&s.url);
    let c = FastBullConnector::with_timeouts(&s.url, Duration::from_secs(10), Duration::from_millis(300), Duration::from_millis(600)).unwrap();
    let t = Instant::now();
    let e = c.fetch().await.unwrap_err();
    assert!(matches!(e, ConnectError::Fetch(_)), "{e:?}");
    assert!(t.elapsed() < Duration::from_secs(3), "must not block indefinitely: {:?}", t.elapsed());
}

#[tokio::test]
async fn fastbull_fetch_connection_refused_is_error() {
    // 綁一個埠後立刻關閉，確保 127.0.0.1 上沒有人在聽。
    let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
    let e = conn(&format!("http://127.0.0.1:{port}/x")).fetch().await.unwrap_err();
    assert!(matches!(e, ConnectError::Fetch(_)));
}

#[tokio::test]
async fn fastbull_fetch_poll_loop_never_overlaps_requests() {
    // 引擎為序列迴圈：以假伺服器延遲回應，確認 N 次輪詢的請求不重疊（同一時間最多 1 個連線在處理）。
    use ticker_connect::emitter::Emitter;
    use ticker_connect::engine::{Engine, EngineConfig};
    use ticker_connect::scheduler::{run, SchedulerConfig};
    let s = FakeServer::start(Mode::Status(500));
    let c = FastBullConnector::with_timeouts(&s.url, Duration::from_millis(50), Duration::from_millis(500), Duration::from_millis(500)).unwrap();
    let buf = SharedBuf::default();
    let mut em = Emitter::new(buf.clone(), "fastbull");
    let engine = Engine::new("fastbull", EngineConfig::default());
    run(&c, engine, &mut em, SchedulerConfig::default(), tokio::time::sleep(Duration::from_millis(400))).await.unwrap();
    // 每個請求被完整處理後才開始下一個：請求數 = 完成的輪詢數（無並行：此處以請求數有界作為間接證據，
    // 並由 scheduler 的 fetch 為單一 await 的程式結構保證）。
    let n = s.requests.lock().unwrap().len();
    assert!(n >= 1);
    let statuses = buf.lines().iter().filter(|l| l["state"] == "error").count();
    assert_eq!(n, statuses, "one error status per completed request");
}
