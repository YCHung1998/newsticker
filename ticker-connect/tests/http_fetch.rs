//! src/http.rs（供新來源使用的抓取器）。只對本機假伺服器。
mod common;
use common::*;
use std::time::{Duration, Instant};
use ticker_connect::http::HttpFetcher;
use ticker_connect::model::ConnectError;

const UA: &str = "ticker-connect-test/0.1 (http_fetch)";

fn fetcher(url: &str, headers: &[(&str, &str)]) -> HttpFetcher {
    assert_local(url);
    HttpFetcher::new(url, UA, headers).unwrap()
}

#[tokio::test]
async fn http_fetch_200_returns_body_text() {
    let s = FakeServer::start(Mode::Body("hello 你好".into()));
    assert_eq!(fetcher(&s.url, &[]).get_text().await.unwrap(), "hello 你好");
}

#[tokio::test]
async fn http_fetch_non_200_is_http_status_error_incl_unfollowed_redirect() {
    for code in [403u16, 429, 500, 302] {
        let s = FakeServer::start(Mode::Status(code));
        let e = fetcher(&s.url, &[]).get_text().await.unwrap_err();
        assert_eq!(e, ConnectError::HttpStatus(code), "status {code}");
    }
}

#[tokio::test]
async fn http_fetch_sends_get_user_agent_and_custom_headers() {
    let s = FakeServer::start(Mode::Body("{}".into()));
    fetcher(&s.url_for("/api/flash?max=20"), &[("X-Test-Header", "abc"), ("Referer", "http://127.0.0.1/")]).get_text().await.unwrap();
    let reqs = s.requests.lock().unwrap();
    assert_eq!(reqs.len(), 1);
    let head = reqs[0].to_lowercase();
    assert!(head.starts_with("get /api/flash?max=20 "), "{head}");
    assert!(head.contains(&format!("user-agent: {}", UA.to_lowercase())), "{head}");
    assert!(head.contains("x-test-header: abc"), "{head}");
    assert!(head.contains("referer: http://127.0.0.1/"), "{head}");
}

#[tokio::test]
async fn http_fetch_timeout_is_fetch_error_within_limit() {
    let s = FakeServer::start(Mode::Hang(Duration::from_secs(30)));
    let f = HttpFetcher::with_timeouts(&s.url, UA, &[], Duration::from_millis(300), Duration::from_millis(600)).unwrap();
    let t = Instant::now();
    let e = f.get_text().await.unwrap_err();
    assert!(matches!(e, ConnectError::Fetch(_)), "{e:?}");
    assert!(t.elapsed() < Duration::from_secs(3), "{:?}", t.elapsed());
}

#[tokio::test]
async fn http_fetch_connection_refused_is_fetch_error() {
    let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
    let e = fetcher(&format!("http://127.0.0.1:{port}/x"), &[]).get_text().await.unwrap_err();
    assert!(matches!(e, ConnectError::Fetch(_)));
}

#[test]
fn http_fetch_invalid_header_is_rejected_at_construction() {
    let r = HttpFetcher::new("http://127.0.0.1:1/", UA, &[("bad header name", "x")]);
    assert!(matches!(r, Err(ConnectError::Fetch(_))));
}
