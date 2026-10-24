//! 行程生命週期：stdin EOF 立即退出（含網路請求進行中）、stdout 每行皆為合法協定 JSON。
mod common;
use common::*;
use std::time::{Duration, Instant};
use ticker_connect::protocol::Protocol;

fn wait_exit(h: &mut Helper, within: Duration) -> Duration {
    let t = Instant::now();
    loop {
        if let Some(st) = h.child.try_wait().unwrap() {
            assert!(st.success(), "exit status {st:?}");
            return t.elapsed();
        }
        assert!(t.elapsed() < within, "helper did not exit within {within:?}");
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn lifecycle_exits_within_1s_when_stdin_closes_during_a_30s_hanging_request() {
    let server = FakeServer::start(Mode::Hang(Duration::from_secs(30)));
    let mut h = spawn_helper(&server.url, 100, 200);
    // 等到 helper 確實連上假伺服器、正卡在等回應。
    let t = Instant::now();
    while server.requests.lock().unwrap().is_empty() {
        assert!(t.elapsed() < Duration::from_secs(5), "helper never connected to the fake server");
        std::thread::sleep(Duration::from_millis(10));
    }
    h.stdin.take(); // 關閉 stdin
    let took = wait_exit(&mut h, Duration::from_secs(1));
    assert!(took < Duration::from_secs(1), "{took:?}");
}

#[test]
fn lifecycle_exits_within_1s_when_idle_and_stdin_closes() {
    let server = FakeServer::start(Mode::Status(500));
    let mut h = spawn_helper(&server.url, 5000, 5000);
    h.wait_for("first status error", Duration::from_secs(5), |v| v["type"] == "status");
    h.stdin.take();
    wait_exit(&mut h, Duration::from_secs(1));
}

#[test]
fn lifecycle_stdout_every_line_is_a_valid_protocol_message() {
    let server = FakeServer::start(Mode::Status(503));
    let mut h = spawn_helper(&server.url, 50, 100);
    for n in 0..4 {
        h.wait_for(&format!("status line #{n}"), Duration::from_secs(10), |_| true);
    }
    assert!(h.all.len() >= 3, "expected several status lines, got {:?}", h.all);
    let p = Protocol::new();
    for l in &h.all {
        assert_eq!(p.check_line(l.as_bytes()), Ok(()), "bad stdout line: {l}");
        let v: serde_json::Value = serde_json::from_str(l).unwrap();
        assert_eq!(v["type"], "status");
        assert_eq!(v["state"], "error");
    }
}
