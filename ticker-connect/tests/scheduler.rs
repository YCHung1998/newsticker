mod common;
use common::*;
use std::time::Duration;
use ticker_connect::emitter::Emitter;
use ticker_connect::engine::{Engine, EngineConfig};
use ticker_connect::model::ConnectError;
use ticker_connect::scheduler::{backoff_delay, run, SchedulerConfig};

const S: fn(u64) -> Duration = Duration::from_secs;

fn err() -> Step {
    Step::FetchErr(ConnectError::HttpStatus(500))
}
fn ok() -> Step {
    Step::Page(vec![item("a", 1)])
}

async fn drive(c: &FakeConnector, total: Duration) -> SharedBuf {
    let buf = SharedBuf::default();
    let mut em = Emitter::new(buf.clone(), "fake");
    let engine = Engine::new("fake", EngineConfig::default());
    run(c, engine, &mut em, SchedulerConfig::default(), tokio::time::sleep(total)).await.unwrap();
    buf
}

#[test]
fn backoff_ladder_is_10_30_60_capped_and_resets() {
    let secs: Vec<u64> = (0..=6).map(|n| backoff_delay(S(10), n).as_secs()).collect();
    assert_eq!(secs, [10, 10, 30, 60, 60, 60, 60]);
}

#[tokio::test(start_paused = true)]
async fn backoff_five_consecutive_failures_wait_10_30_60_60_60() {
    let c = FakeConnector::new(S(10), vec![err(), err(), err(), err(), err(), err()]);
    drive(&c, S(1000)).await;
    let gaps = c.gaps();
    assert_eq!(&gaps[..5], &[S(10), S(30), S(60), S(60), S(60)]);
}

#[tokio::test(start_paused = true)]
async fn backoff_success_resets_to_first_rung() {
    // 失敗, 失敗, 成功, 失敗, 失敗 ...
    let c = FakeConnector::new(S(10), vec![err(), err(), ok(), err(), err()]);
    drive(&c, S(1000)).await;
    let g = c.gaps();
    // 5 次呼叫間的等待：10(失敗1後) 30(失敗2後) 10(成功後=interval) 10(失敗1後) 30
    assert_eq!(&g[..4], &[S(10), S(30), S(10), S(10)]);
    assert_eq!(g[4], S(30));
}

#[tokio::test(start_paused = true)]
async fn backoff_normal_polling_uses_interval() {
    let c = FakeConnector::new(S(10), vec![ok()]);
    drive(&c, S(100)).await;
    assert!(c.gaps().iter().all(|g| *g == S(10)));
    assert!(c.gaps().len() >= 8);
}

// ---------- 2.2 heartbeat ----------
fn status_gaps(buf: &SharedBuf) {
    let _ = buf;
}

/// 以輸出時間戳檢查相鄰 status 間隔：Emitter 不帶時間，改用「包裝 Write 記錄虛擬時間」。
#[derive(Clone, Default)]
struct TimedBuf(std::sync::Arc<std::sync::Mutex<Vec<(tokio::time::Instant, String)>>>);
impl std::io::Write for TimedBuf {
    fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
        let s = String::from_utf8_lossy(b).to_string();
        if s != "\n" {
            self.0.lock().unwrap().push((tokio::time::Instant::now(), s));
        }
        Ok(b.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

async fn status_times(steps: Vec<Step>, total: Duration, start: tokio::time::Instant) -> Vec<Duration> {
    let c = FakeConnector::new(S(10), steps);
    let tb = TimedBuf::default();
    let mut em = Emitter::new(tb.clone(), "fake");
    let engine = Engine::new("fake", EngineConfig::default());
    run(&c, engine, &mut em, SchedulerConfig::default(), tokio::time::sleep(total)).await.unwrap();
    let rec = tb.0.lock().unwrap();
    rec.iter().filter(|(_, l)| l.contains("\"type\":\"status\"")).map(|(t, _)| *t - start).collect()
}

fn assert_max_gap(times: &[Duration], total: Duration) {
    assert!(times.len() >= 8, "expected many statuses in {total:?}, got {times:?}");
    let mut prev = Duration::ZERO;
    for t in times {
        assert!(*t - prev <= S(30), "gap {:?} > 30s between {prev:?} and {t:?}", *t - prev);
        prev = *t;
    }
    // 最後一則到結束也不得超過 30 秒
    assert!(total - prev <= S(30), "trailing gap too long");
}

#[tokio::test(start_paused = true)]
async fn heartbeat_five_minutes_success_without_new_items_gap_at_most_30s() {
    let start = tokio::time::Instant::now();
    let t = status_times(vec![ok()], S(300), start).await;
    assert_max_gap(&t, S(300));
}

#[tokio::test(start_paused = true)]
async fn heartbeat_five_minutes_during_backoff_gap_at_most_30s() {
    // 一路失敗：退避 60 秒等待期間仍須有心跳。
    let start = tokio::time::Instant::now();
    let t = status_times(vec![err()], S(300), start).await;
    assert_max_gap(&t, S(300));
}

#[tokio::test(start_paused = true)]
async fn heartbeat_mixed_success_and_failure_gap_at_most_30s() {
    let start = tokio::time::Instant::now();
    let t = status_times(vec![ok(), ok(), err(), err(), err(), ok(), ok()], S(300), start).await;
    assert_max_gap(&t, S(300));
}

#[tokio::test(start_paused = true)]
async fn heartbeat_state_is_error_while_failing_and_ok_when_healthy() {
    let c = FakeConnector::new(S(10), vec![err()]);
    let buf = drive(&c, S(100)).await;
    assert!(buf.lines().iter().all(|l| l["type"] == "status" && l["state"] == "error"));
    let c = FakeConnector::new(S(10), vec![ok()]);
    let buf = drive(&c, S(100)).await;
    let hb: Vec<_> = buf.lines().into_iter().filter(|l| l["type"] == "status").collect();
    assert!(!hb.is_empty() && hb.iter().all(|l| l["state"] == "ok"));
    let _ = status_gaps;
}
