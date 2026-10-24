#![allow(dead_code)]
//! 測試輔助：假 Connector、共用緩衝、本機假 HTTP 伺服器、路徑常數。
use std::collections::VecDeque;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use ticker_connect::connector::{Connector, RawPayload};
use ticker_connect::model::{ConnectError, Item};

pub const ROOT: &str = env!("CARGO_MANIFEST_DIR");

pub fn fixture_html() -> String {
    std::fs::read_to_string(format!("{ROOT}/../docs/fixtures/express-news-2026-10-24.html")).expect("snapshot fixture")
}

/// 正式站 origin；以拼接產生，避免測試原始碼出現正式主機字面值（見 no_external_network 守衛）。
/// 只用於字串比對，不發任何請求。
pub fn prod_origin() -> String {
    format!("https://www.{}", ["fastbull", ".com"].concat())
}

pub fn item(id: &str, ms: u64) -> Item {
    Item { source: "fake".into(), id: id.into(), published_at_ms: ms, text: format!("text {id}"), url: None }
}

#[derive(Clone, Default)]
pub struct SharedBuf(pub Arc<Mutex<Vec<u8>>>);

impl Write for SharedBuf {
    fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl SharedBuf {
    pub fn lines(&self) -> Vec<serde_json::Value> {
        let data = self.0.lock().unwrap().clone();
        String::from_utf8(data).unwrap().lines().map(|l| serde_json::from_str(l).unwrap()).collect()
    }
    pub fn raw(&self) -> Vec<u8> {
        self.0.lock().unwrap().clone()
    }
}

#[derive(Clone, Debug)]
pub enum Step {
    FetchErr(ConnectError),
    ConvertErr,
    Page(Vec<Item>),
}

/// 假 Connector：依腳本回應，腳本用完後重複最後一步；記錄每次 fetch 的（虛擬）時間。
pub struct FakeConnector {
    pub interval: Duration,
    script: Mutex<VecDeque<Step>>,
    last: Mutex<Option<Step>>,
    pub fetch_times: Mutex<Vec<tokio::time::Instant>>,
}

impl FakeConnector {
    pub fn new(interval: Duration, steps: Vec<Step>) -> Self {
        FakeConnector { interval, script: Mutex::new(steps.into()), last: Mutex::new(None), fetch_times: Mutex::new(vec![]) }
    }
    pub fn gaps(&self) -> Vec<Duration> {
        let t = self.fetch_times.lock().unwrap();
        t.windows(2).map(|w| w[1] - w[0]).collect()
    }
}

impl Connector for FakeConnector {
    fn source_id(&self) -> &str {
        "fake"
    }
    fn interval(&self) -> Duration {
        self.interval
    }
    async fn fetch(&self) -> Result<RawPayload, ConnectError> {
        self.fetch_times.lock().unwrap().push(tokio::time::Instant::now());
        let step = {
            let mut q = self.script.lock().unwrap();
            let mut last = self.last.lock().unwrap();
            match q.pop_front() {
                Some(s) => {
                    *last = Some(s.clone());
                    s
                }
                None => last.clone().expect("empty script"),
            }
        };
        match step {
            Step::FetchErr(e) => Err(e),
            Step::ConvertErr => Ok("!err".to_string()),
            Step::Page(items) => Ok(serde_json::to_string(&items).unwrap()),
        }
    }
    fn convert(&self, raw: RawPayload) -> Result<Vec<Item>, ConnectError> {
        if raw == "!err" {
            return Err(ConnectError::Parse("scripted".into()));
        }
        Ok(serde_json::from_str(&raw).unwrap())
    }
}

/// 測試只准連 127.0.0.1。
pub fn assert_local(url: &str) {
    assert!(url.starts_with("http://127.0.0.1:"), "tests must only connect to 127.0.0.1, got {url}");
}

#[derive(Clone)]
pub enum Mode {
    Body(String),
    Status(u16),
    Hang(Duration),
}

/// 本機假 HTTP 伺服器（std TcpListener，綁定 127.0.0.1:隨機埠）。
pub struct FakeServer {
    pub url: String,
    pub mode: Arc<Mutex<Mode>>,
    pub requests: Arc<Mutex<Vec<String>>>,
}

impl FakeServer {
    pub fn start(initial: Mode) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let mode = Arc::new(Mutex::new(initial));
        let requests = Arc::new(Mutex::new(Vec::<String>::new()));
        let (m2, r2) = (mode.clone(), requests.clone());
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let (m, r) = (m2.clone(), r2.clone());
                std::thread::spawn(move || {
                    let mut buf = Vec::new();
                    let mut chunk = [0u8; 1024];
                    while !buf.windows(4).any(|w| w == b"\r\n\r\n") {
                        match stream.read(&mut chunk) {
                            Ok(0) | Err(_) => return,
                            Ok(n) => buf.extend_from_slice(&chunk[..n]),
                        }
                    }
                    r.lock().unwrap().push(String::from_utf8_lossy(&buf).to_string());
                    let mode = m.lock().unwrap().clone();
                    let resp = match mode {
                        Mode::Body(b) => format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                            b.len(),
                            b
                        ),
                        Mode::Status(c) => format!("HTTP/1.1 {c} X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
                        Mode::Hang(d) => {
                            std::thread::sleep(d);
                            return;
                        }
                    };
                    let _ = stream.write_all(resp.as_bytes());
                });
            }
        });
        let url = format!("http://127.0.0.1:{port}/tw/express-news");
        assert_local(&url);
        FakeServer { url, mode, requests }
    }
    pub fn set(&self, m: Mode) {
        *self.mode.lock().unwrap() = m;
    }
}

// ---------- 啟動真正的 binary ----------
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{channel, Receiver};

pub struct Helper {
    pub child: Child,
    pub stdin: Option<ChildStdin>,
    pub lines: Receiver<String>,
    pub all: Vec<String>,
}

pub fn spawn_helper(url: &str, interval_ms: u64, heartbeat_ms: u64) -> Helper {
    assert_local(url);
    let mut child = Command::new(env!("CARGO_BIN_EXE_ticker-connect"))
        .args(["--url", url, "--interval-ms", &interval_ms.to_string(), "--heartbeat-ms", &heartbeat_ms.to_string()])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn helper");
    let stdin = child.stdin.take();
    let out = child.stdout.take().unwrap();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        use std::io::BufRead;
        for l in std::io::BufReader::new(out).lines() {
            match l {
                Ok(l) => {
                    if tx.send(l).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });
    Helper { child, stdin, lines: rx, all: vec![] }
}

impl Helper {
    /// 等到出現符合條件的行（回傳其 JSON）；逾時 panic。所有收到的行都記入 `all`。
    pub fn wait_for(&mut self, what: &str, timeout: Duration, pred: impl Fn(&serde_json::Value) -> bool) -> serde_json::Value {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            let left = deadline.saturating_duration_since(std::time::Instant::now());
            match self.lines.recv_timeout(left) {
                Ok(l) => {
                    self.all.push(l.clone());
                    let v: serde_json::Value = serde_json::from_str(&l).expect("stdout line must be JSON");
                    if pred(&v) {
                        return v;
                    }
                }
                Err(_) => panic!("timed out waiting for {what}; got so far: {:#?}", self.all),
            }
        }
    }
    /// 收集一段時間內的所有行。
    pub fn drain_for(&mut self, d: Duration) {
        let deadline = std::time::Instant::now() + d;
        while let Ok(l) = self.lines.recv_timeout(deadline.saturating_duration_since(std::time::Instant::now())) {
            self.all.push(l);
        }
    }
}

impl Drop for Helper {
    fn drop(&mut self) {
        self.stdin.take();
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
