use std::io::{Read, Write};
use std::time::Duration;
use ticker_connect::emitter::Emitter;
use ticker_connect::engine::{Engine, EngineConfig};
use ticker_connect::fastbull::{FastBullConnector, DEFAULT_INTERVAL, DEFAULT_URL, SOURCE_ID};
use ticker_connect::scheduler::{run, SchedulerConfig};

const USAGE: &str = "ticker-connect [--url URL] [--interval-ms N] [--heartbeat-ms N]\n\
stdout: protocol JSON-lines only; logs: stderr. Exits when stdin reaches EOF.\n\
--url / --interval-ms / --heartbeat-ms exist for local testing; defaults are the production values.";

fn main() {
    let mut url = DEFAULT_URL.to_string();
    let mut interval = DEFAULT_INTERVAL;
    let mut heartbeat = SchedulerConfig::default().heartbeat;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = |name: &str| -> String {
            args.next().unwrap_or_else(|| {
                eprintln!("missing value for {name}\n{USAGE}");
                std::process::exit(2)
            })
        };
        match a.as_str() {
            "--url" => url = val("--url"),
            "--interval-ms" => interval = Duration::from_millis(parse_u64(&val("--interval-ms"))),
            "--heartbeat-ms" => heartbeat = Duration::from_millis(parse_u64(&val("--heartbeat-ms"))),
            "-h" | "--help" => {
                println!("{USAGE}");
                return;
            }
            other => {
                eprintln!("unknown argument {other}\n{USAGE}");
                std::process::exit(2);
            }
        }
    }

    // 獨立 OS 執行緒監看 stdin；EOF 直接結束行程，不經過 async 執行環境，不會被進行中的網路請求卡住。
    std::thread::spawn(|| {
        let mut buf = [0u8; 256];
        let mut stdin = std::io::stdin().lock();
        loop {
            match stdin.read(&mut buf) {
                Ok(0) | Err(_) => {
                    eprintln!("[ticker-connect] stdin closed, exiting");
                    std::process::exit(0);
                }
                Ok(_) => {}
            }
        }
    });

    let connector = match FastBullConnector::new(&url, interval) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[ticker-connect] cannot build connector: {e}");
            std::process::exit(1);
        }
    };
    eprintln!("[ticker-connect] polling {} every {:?}", connector.url(), interval);
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("runtime");
    let mut emitter = Emitter::new(std::io::stdout(), SOURCE_ID);
    let engine = Engine::new(SOURCE_ID, EngineConfig::default());
    let result = rt.block_on(run(&connector, engine, &mut emitter, SchedulerConfig { heartbeat }, std::future::pending()));
    if let Err(e) = result {
        // 例如 stdout 管線已斷。
        let _ = writeln!(std::io::stderr(), "[ticker-connect] output error: {e}");
        std::process::exit(1);
    }
}

fn parse_u64(s: &str) -> u64 {
    s.parse().unwrap_or_else(|_| {
        eprintln!("not a number: {s}\n{USAGE}");
        std::process::exit(2)
    })
}
