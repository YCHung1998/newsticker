//! 輪詢排程：退避 10→30→60 秒封頂、心跳（含 fetch 進行中與退避期間）、可停止。
//! 時鐘使用 tokio::time；測試以 `start_paused` 的虛擬時鐘決定性推進（不真的等待）。
use crate::connector::Connector;
use crate::emitter::Emitter;
use crate::engine::Engine;
use crate::model::{Message, State};
use std::future::Future;
use std::io::{self, Write};
use std::time::Duration;
use tokio::time::{sleep_until, Instant};

#[derive(Debug, Clone, Copy)]
pub struct SchedulerConfig {
    /// 內部心跳週期（假設 25 秒，留餘裕給 30 秒上限）。
    pub heartbeat: Duration,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        SchedulerConfig { heartbeat: Duration::from_secs(25) }
    }
}

/// 退避：第 n 次連續失敗後的等待 = interval × [1, 3, 6][min(n-1, 2)]。
/// interval = 10 秒時即 10→30→60 秒；成功後重置為 interval。
pub fn backoff_delay(interval: Duration, consecutive_failures: u32) -> Duration {
    if consecutive_failures == 0 {
        return interval;
    }
    const FACTORS: [u32; 3] = [1, 3, 6];
    interval * FACTORS[(consecutive_failures as usize - 1).min(2)]
}

/// 執行到 `stop` 完成為止。輸出錯誤（例如 stdout 管線斷了）回傳 Err。
pub async fn run<C: Connector, W: Write>(
    connector: &C,
    mut engine: Engine,
    emitter: &mut Emitter<W>,
    cfg: SchedulerConfig,
    stop: impl Future<Output = ()>,
) -> io::Result<()> {
    let source = connector.source_id().to_string();
    let interval = connector.interval();
    let mut last_status = Instant::now();
    let mut last_error: Option<String> = None;
    let mut failures: u32 = 0;
    let mut next_poll = Instant::now();

    let body = async {
        loop {
            // 等到下次輪詢；其間依心跳週期補發 status。
            loop {
                let hb_at = last_status + cfg.heartbeat;
                if next_poll <= hb_at {
                    sleep_until(next_poll).await;
                    break;
                }
                sleep_until(hb_at).await;
                heartbeat(emitter, &source, &last_error, &mut last_status)?;
            }
            // 輪詢；fetch 進行中心跳照發。
            let fetch = connector.fetch();
            tokio::pin!(fetch);
            let raw = loop {
                tokio::select! {
                    r = &mut fetch => break r,
                    _ = sleep_until(last_status + cfg.heartbeat) => {
                        heartbeat(emitter, &source, &last_error, &mut last_status)?;
                    }
                }
            };
            let result = raw.and_then(|p| connector.convert(p));
            let outcome = engine.on_poll(result);
            if outcome.ok {
                failures = 0;
                last_error = None;
            } else {
                failures += 1;
                last_error = outcome.error.clone();
            }
            for m in outcome.messages {
                let report = emitter.emit(m)?;
                if report.wrote_status {
                    last_status = Instant::now();
                }
            }
            next_poll = Instant::now() + backoff_delay(interval, failures);
        }
        #[allow(unreachable_code)]
        Ok::<(), io::Error>(())
    };
    tokio::select! {
        r = body => r,
        _ = stop => Ok(()),
    }
}

fn heartbeat<W: Write>(
    emitter: &mut Emitter<W>,
    source: &str,
    last_error: &Option<String>,
    last_status: &mut Instant,
) -> io::Result<()> {
    let msg = match last_error {
        Some(e) => Message::status(source, State::Error, e.clone()),
        None => Message::status(source, State::Ok, ""),
    };
    // 無論是否寫出（驗證失敗時只記 stderr），避免忙迴圈，仍推進時間戳。
    emitter.emit(msg)?;
    *last_status = Instant::now();
    Ok(())
}
